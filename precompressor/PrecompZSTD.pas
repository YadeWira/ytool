unit PrecompZSTD;

interface

uses
  ZSTDDLL,
  Utils,
  Threading,
  PrecompUtils,
  SysUtils, Classes, Math, StrUtils, Generics.Collections;

var
  Codec: TPrecompressor;

implementation

const
  ZSTDCodecs: array of PChar = ['zstd'];
  CODEC_COUNT = 1;
  ZSTD_CODEC = 0;

const
  Z_MAXSIZE = 16 * 1024 * 1024;
  Z_FASTMODE = 0;
  Z_WINDOWLOG = 0;
  Z_BLOCKSIZE = 0;

var
  SOList: array of array [0 .. CODEC_COUNT - 1] of TSOList;
  cctx, dctx: array of Pointer;
  // cdict, ddict: Pointer;
  CodecAvailable, CodecEnabled: TArray<Boolean>;
  ZMaxSize: Integer = Z_MAXSIZE;
  ZFastMode: Integer = Z_FASTMODE;
  ZWindowLog: Integer = Z_WINDOWLOG;
  ZBlockSize: Integer = Z_BLOCKSIZE;
  // -cfgzstd (xtool 0.9.9): advanced parameters every encode attempt uses, for
  // frames a level alone does not reproduce. Keys, as 0.9.9 reads them, each
  // set only when given (0.9.9's x and b are ytool's -mzstd:s and :b):
  //   wl hl cl sl mm tl st -> windowLog hashLog chainLog searchLog minMatch
  //                           targetLength strategy (101-107)
  //   cs                   -> targetCBlockSize (130)
  //   ldm lhl lmm lbs lhr  -> enableLongDistanceMatching, ldmHashLog,
  //                           ldmMinMatch, ldmBucketSizeLog, ldmHashRateLog
  //                           (160-164)
  // Stored per stream in its Resource field, so decode needs no option:
  //  - wl hl cl sl mm only (as in 0.9.9a): packed, hl 0-4, cl 5-9, sl 10-14,
  //    mm 15-17, wl 18-22, bit 31 set; containers written before have 0.
  //  - anything else: the 13 values go once into a container resource, and
  //    Resource is that resource's index with bits 31 and 30 set.
  ZCFG_KEYS: array [0 .. 12] of String = ('wl', 'hl', 'cl', 'sl', 'mm', 'tl',
    'st', 'cs', 'ldm', 'lhl', 'lmm', 'lbs', 'lhr');
  ZCFG_PARAMS: array [0 .. 12] of Integer = (101, 102, 103, 104, 105, 106, 107,
    130, 160, 161, 162, 163, 164);

type
  TZCfg = array [0 .. 12] of Integer;

var
  ZCfgVals: TZCfg = (-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
  ZCfgExt: Boolean = False;   // needs the resource form
  ZCfgResIdx: Integer = -1;
  ZCfg: Integer = 0;
  ZFuncs: PPrecompFuncs = nil;
  ZThreads: Integer = 1;
  ZLock: TRTLCriticalSection;

function ZCfgPack(WL, HL, CL, SL, MM: Integer): Integer;
begin
  Result := 0;
  if (WL or HL or CL or SL or MM) = 0 then
    exit;
  Result := (HL and 31) or ((CL and 31) shl 5) or ((SL and 31) shl 10) or
    ((MM and 7) shl 15) or ((WL and 31) shl 18) or Integer($80000000);
end;

// The Resource value a stream encoded now carries. In the resource form the
// resource is added on first use, while encoding (decode never calls this).
function ZCfgForStream: Integer;
begin
  if not ZCfgExt then
    exit(ZCfg);
  if ZCfgResIdx < 0 then
  begin
    EnterCriticalSection(ZLock);
    try
      if ZCfgResIdx < 0 then
        ZCfgResIdx := ZFuncs^.AddResourceEx(@ZCfgVals, SizeOf(ZCfgVals));
    finally
      LeaveCriticalSection(ZLock);
    end;
  end;
  Result := ZCfgResIdx or Integer($C0000000);
end;

// The 13 values a stream's Resource stands for (-1: not given).
function ZCfgOf(Cfg: Integer): TZCfg;
var
  I, Size: Integer;
begin
  for I := Low(Result) to High(Result) do
    Result[I] := -1;
  if Cfg >= 0 then
    exit;
  if (Cfg and $40000000) <> 0 then
  begin
    Size := 0;
    if Assigned(ZFuncs) and ZFuncs^.GetResource(Cfg and $3FFFFFFF, nil, @Size)
      and (Size = SizeOf(Result)) then
      ZFuncs^.GetResource(Cfg and $3FFFFFFF, @Result, @Size);
    exit;
  end;
  // the packed form: 0 means the library default, as -1 does here
  Result[1] := Cfg and 31;
  Result[2] := (Cfg shr 5) and 31;
  Result[3] := (Cfg shr 10) and 31;
  Result[4] := (Cfg shr 15) and 7;
  if (Cfg shr 18) and 31 > 0 then
    Result[0] := (Cfg shr 18) and 31;
end;

// Sets (or, with no configuration, resets to the library default) the
// parameters -cfgzstd controls. Always called: the context is reused from
// stream to stream, so a value left by one would reach the next. windowLog is
// set only when given: the streaming path leaves the window to the level.
procedure ZCfgApply(Ctx: Pointer; Cfg: Integer);
var
  V: TZCfg;
  I: Integer;
begin
  V := ZCfgOf(Cfg);
  for I := 1 to High(V) do
    ZSTD_CCtx_setParameter(Ctx, ZSTD_cParameter(ZCFG_PARAMS[I]), Max(V[I], 0));
  if V[0] > 0 then
    ZSTD_CCtx_setParameter(Ctx, ZSTD_c_windowLog, V[0]);
end;

function ZSTDInit(Command: PChar; Count: Integer; Funcs: PPrecompFuncs)
  : Boolean;
var
  I: Integer;
  Options: TArray<Integer>;
  S: String;
  X, Y: Integer;
begin
  Result := True;
  // -cfgzstd, read as xtool 0.9.9 does: the rest of the argument, fields
  // split on ':' or ','. Out-of-range values are left to the library, which
  // rejects them (the attempt then fails and the stream stays raw).
  ZFuncs := Funcs;
  ZThreads := Max(1, Count);
  for I := 1 to ParamCount do
    if ParamStr(I).StartsWith('-cfgzstd', True) then
    begin
      for S in ParamStr(I).Substring(8).Split([':', ',']) do
        // longest key first: "lhl" before "hl"
        for X := High(ZCFG_KEYS) downto Low(ZCFG_KEYS) do
          if S.StartsWith(ZCFG_KEYS[X]) and
            (Length(S) > Length(ZCFG_KEYS[X])) and
            CharInSet(S[Length(ZCFG_KEYS[X]) + 1], ['0' .. '9']) then
          begin
            ZCfgVals[X] := StrToIntDef(S.Substring(Length(ZCFG_KEYS[X])), -1);
            break;
          end;
      // The 0.9.9a form when it holds everything given.
      ZCfgExt := False;
      for X := 5 to High(ZCfgVals) do
        if ZCfgVals[X] >= 0 then
          ZCfgExt := True;
      if (ZCfgVals[4] > 7) or (ZCfgVals[0] > 31) or (ZCfgVals[1] > 31) or
        (ZCfgVals[2] > 31) or (ZCfgVals[3] > 31) then
        ZCfgExt := True;
      ZCfg := ZCfgPack(Max(ZCfgVals[0], 0), Max(ZCfgVals[1], 0),
        Max(ZCfgVals[2], 0), Max(ZCfgVals[3], 0), Max(ZCfgVals[4], 0));
    end;
  SetLength(SOList, Count);
  for X := Low(SOList) to High(SOList) do
    for Y := Low(SOList[X]) to High(SOList[X]) do
      SOList[X, Y] := TSOList.Create([], TSOMethod.MTF);
  for X := Low(CodecAvailable) to High(CodecAvailable) do
  begin
    CodecAvailable[X] := False;
    CodecEnabled[X] := False;
  end;
  for X := Low(CodecAvailable) to High(CodecAvailable) do
    CodecAvailable[X] := ZSTDDLL.DLLLoaded;
  X := 0;
  while Funcs^.GetCodec(Command, X, False) <> '' do
  begin
    S := Funcs^.GetCodec(Command, X, False);
    if (CompareText(S, ZSTDCodecs[ZSTD_CODEC]) = 0) and ZSTDDLL.DLLLoaded then
    begin
      CodecEnabled[ZSTD_CODEC] := True;
      if Funcs^.GetParam(Command, X, 'l') <> '' then
        for I := Low(SOList) to High(SOList) do
          SOList[I][ZSTD_CODEC].Update
            ([StrToInt(Funcs^.GetParam(Command, X, 'l'))], True);
      if Funcs^.GetParam(Command, X, 's') <> '' then
        ZMaxSize := ConvertToBytes(Funcs^.GetParam(Command, X, 's'));
      if Funcs^.GetParam(Command, X, 'f') <> '' then
        ZFastMode := ConvertToBytes(Funcs^.GetParam(Command, X, 'f'));
      if Funcs^.GetParam(Command, X, 'w') <> '' then
        ZWindowLog := ConvertToBytes(Funcs^.GetParam(Command, X, 'w'));
      if Funcs^.GetParam(Command, X, 'b') <> '' then
        ZBlockSize := StrToInt(Funcs^.GetParam(Command, X, 'b'));
    end;
    Inc(X);
  end;
  if CodecAvailable[ZSTD_CODEC] then
  begin
    SetLength(cctx, Count);
    SetLength(dctx, Count);
    for X := Low(cctx) to High(cctx) do
    begin
      cctx[X] := nil;
      dctx[X] := nil;
    end;
  end;
  SetLength(Options, 0);
  for I := 1 to 22 do
    Insert(I, Options, Length(Options));
  for X := Low(SOList) to High(SOList) do
    for Y := Low(SOList[X]) to High(SOList[X]) do
      if SOList[X, Y].Count = 0 then
        SOList[X, Y].Update(Options);
end;

procedure ZSTDFree(Funcs: PPrecompFuncs);
var
  X, Y: Integer;
begin
  for X := Low(SOList) to High(SOList) do
    for Y := Low(SOList[X]) to High(SOList[X]) do
      SOList[X, Y].Free;
  if CodecAvailable[ZSTD_CODEC] then
  begin
    for X := Low(cctx) to High(cctx) do
    begin
      if Assigned(cctx[X]) then
        ZSTD_freeCCtx(cctx[X]);
      if Assigned(dctx[X]) then
        ZSTD_freeDCtx(dctx[X]);
    end;
  end;
end;

function ZSTDParse(Command: PChar; Option: PInteger;
  Funcs: PPrecompFuncs): Boolean;
var
  S: String;
  I: Integer;
begin
  Result := False;
  Option^ := 0;
  SetBits(Option^, ZFastMode, 8, 1);
  SetBits(Option^, ZWindowLog, 9, 5);
  SetBits(Option^, ZBlockSize, 14, 13);
  I := 0;
  while Funcs^.GetCodec(Command, I, False) <> '' do
  begin
    S := Funcs^.GetCodec(Command, I, False);
    if (CompareText(S, ZSTDCodecs[ZSTD_CODEC]) = 0) and ZSTDDLL.DLLLoaded then
    begin
      SetBits(Option^, ZSTD_CODEC, 0, 3);
      if Funcs^.GetParam(Command, I, 'l') <> '' then
        SetBits(Option^, StrToInt(Funcs^.GetParam(Command, I, 'l')), 3, 5);
      if String(Funcs^.GetParam(Command, I, 'f')) = '1' then
        SetBits(Option^, 1, 8, 1);
      if Funcs^.GetParam(Command, I, 'w') <> '' then
        SetBits(Option^, StrToInt(Funcs^.GetParam(Command, I, 'w')), 9, 5);
      if Funcs^.GetParam(Command, I, 'b') <> '' then
        SetBits(Option^, StrToInt(Funcs^.GetParam(Command, I, 'b')), 14, 13);
      Result := True;
    end;
    Inc(I);
  end;
end;

procedure ZSTDScan1(Instance, Depth: Integer; Input: PByte;
  Size, SizeEx: NativeInt; Output: _PrecompOutput; Add: _PrecompAdd;
  Funcs: PPrecompFuncs);
var
  Buffer: PByte;
  Pos: NativeInt;
  X, Y, Z: Integer;
  SI: _StrInfo1;
begin
  if BoolArray(CodecEnabled, False) then
    exit;
  Pos := 0;
  while Pos < Size do
  begin
    if PCardinal(Input + Pos)^ = $FD2FB528 then
    begin
      X := ZSTD_findFrameCompressedSize(Input + Pos, SizeEx - Pos);
      if X > 0 then
      begin
        Z := ZSTD_findDecompressedSize(Input + Pos, X);
        if Z <= 0 then
          Z := ZMaxSize;
        Buffer := Funcs^.Allocator(Instance, Z);
        if not Assigned(dctx[Instance]) then
          dctx[Instance] := ZSTD_createDCtx;
        Y := ZSTD_decompressDCtx(dctx[Instance], Buffer, Z, Input + Pos, X);
        // Y := ZSTD_decompress_usingDDict(dctx[Instance], Buffer, Z, Input + Pos, X, ddict);
        if (X < Y) then
        begin
          Output(Instance, Buffer, Y);
          SI.Position := Pos;
          SI.OldSize := X;
          SI.NewSize := Y;
          SI.Resource := 0;
          SI.Option := 0;
          SetBits(SI.Option, ZFastMode, 8, 1);
          SetBits(SI.Option, ZWindowLog, 9, 5);
          SetBits(SI.Option, ZBlockSize, 14, 13);
          // Descriptor del frame: el byte que sigue al magic. Hasta aca solo se
          // guardaban los defaults del codec y el frame NUNCA se miraba, asi que
          // el re-encode salia con los defaults de la libreria, entre ellos
          // ZSTD_c_checksumFlag=0. El CLI de zstd escribe el checksum por
          // defecto, asi que sus bytes nunca coincidian, CompareMem fallaba y el
          // stream terminaba guardado literal sin ningun error. Medido sobre el
          // mismo binario: material con checksum 0/4 procesados, sin checksum
          // 4/4. Bit 2 = checksum de contenido; bits 6..7 = campo de tamano.
          SetBits(SI.Option, Ord((Input + Pos + 4)^ and $04 <> 0), 27, 1);
          SetBits(SI.Option, ((Input + Pos + 4)^ shr 6) and $03, 28, 2);
          // HUECO CONOCIDO, y no es un parametro: es COMO el productor le dio
          // los datos a zstd. Quedan dos casos medidos que siguen en literal.
          //
          // 1) Una sola pasada contra streaming por chunks, niveles 5..15.
          //    El CLI alimenta ZSTD_compressStream2 en trozos de
          //    ZSTD_CStreamInSize (131072 bytes); aca se llama ZSTD_compress2
          //    sobre el buffer entero. Reproducido con libzstd puro, sin ytool
          //    de por medio: los dos bitstreams difieren en 5..15, y el chunked
          //    es el que coincide con el CLI. Identicos hasta 524288 bytes de
          //    entrada (4 chunks), divergen desde ~530000 (5 chunks). El motivo
          //    interno de libzstd no se establecio.
          // 2) Frames sin campo de tamano (entrada por pipe: FCS_flag=0,
          //    single_segment=0). Aca siempre se re-encodea con un srcSize
          //    conocido, asi que el framing no coincide. Guardar el flag no
          //    alcanza -- esta guardado y el caso sigue fallando.
          //
          // NO "ARREGLAR" ESTO RUTEANDO TODO POR STREAMING: se probó y se
          // refuto con tres verificaciones independientes. Rompe el caso de una
          // sola pasada, que es como escribe zstd una aplicacion que llama
          // ZSTD_compress() sobre un buffer -- la forma dominante en el
          // material que ytool procesa. Medido: 9 de 20 casos que hoy andan
          // pasan a literal. Y registrar nbWorkers sin chequear el retorno de
          // ZSTD_CCtx_setParameter corrompe en una libzstd compilada sin
          // ZSTD_MULTITHREAD, donde esa llamada falla en silencio.
          //
          // Descartado ademas el windowLog: Z_WINDOWLOG es 0, que zstd ya lee
          // como "derivalo vos", asi que el codec no lo estaba forzando.
          // Probado explicitamente y el conteo no se movio.
          //
          // Todo esto es seguro: esos streams se guardan literales y el
          // round-trip sigue siendo bit-exacto, solo no comprimen.
          SI.Status := TStreamStatus.None;
          Funcs^.LogScan1(ZSTDCodecs[GetBits(SI.Option, 0, 3)], SI.Position,
            SI.OldSize, SI.NewSize);
          Add(Instance, @SI, nil, nil);
          Inc(Pos, SI.OldSize);
          continue;
        end;
      end;
    end;
    Inc(Pos);
  end;
end;

function ZSTDScan2(Instance, Depth: Integer; Input: Pointer; Size: NativeInt;
  StreamInfo: PStrInfo2; Offset: PInteger; Output: _PrecompOutput;
  Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  X: Integer;
  Res: Integer;
begin
  Result := False;
  X := GetBits(StreamInfo^.Option, 0, 3);
  if StreamInfo^.OldSize <= 0 then
    StreamInfo^.OldSize := ZSTD_findFrameCompressedSize(Input, Size);
  if StreamInfo^.OldSize <= 0 then
    exit;
  if StreamInfo^.NewSize <= 0 then
    StreamInfo^.NewSize := ZSTD_findDecompressedSize(Input, Size);
  if StreamInfo^.NewSize <= 0 then
    StreamInfo^.NewSize := ZMaxSize;
  Buffer := Funcs^.Allocator(Instance, StreamInfo^.NewSize);
  case X of
    ZSTD_CODEC:
      begin
        if not Assigned(dctx[Instance]) then
          dctx[Instance] := ZSTD_createDCtx;
        Res := ZSTD_decompressDCtx(dctx[Instance], Buffer, StreamInfo^.NewSize,
          Input, StreamInfo^.OldSize);
      end;
  end;
  if Res > StreamInfo^.OldSize then
  begin
    Output(Instance, Buffer, Res);
    StreamInfo^.NewSize := Res;
    Funcs^.LogScan2(ZSTDCodecs[GetBits(StreamInfo^.Option, 0, 3)],
      StreamInfo^.OldSize, StreamInfo^.NewSize);
    Result := True;
  end;
end;

// --- -b (brute) for zstd ---------------------------------------------------
//
// xtool 0.9.9's list, read from its binary: every combination of
//   wl 14..27, hl 1..27, cl 12..25, sl 1..13, mm 3..7,
//   tl in (0 1 2 4 8 12 16 32 48 64 128 256 512 999 1024), st 1..9
// in that nesting (st innermost): 46,437,300 candidates. 0.9.9 shuffles them
// (Fisher-Yates, Delphi's Random with RandSeed = 12911), tries the first
// BruteCount of the shuffled list (5% by default: 2,321,865) with each
// parameter set on a reset context (no level), and prints the matching ones as
// -cfgzstdwl#:hl#:cl#:sl#:mm#:tl#:st#. Same list, same order, same lines here.
//
// Faster here, with the same result: two candidates whose parameters zstd
// resolves to the same values (it rejects hl 1..5, shrinks the window to the
// stream's size, ...) write the same bytes, so each set of resolved
// parameters is compressed once (zstd's own ZSTD_getCParamsFromCCtxParams
// says what they resolve to), and a stream's candidates run on several
// threads. Also, the frame's checksum and content-size flags are set as the
// frame has them, where 0.9.9 leaves the defaults and so never matches a
// frame with a checksum.
const
  ZB_WL = 14; ZB_NWL = 14;
  ZB_HL = 1; ZB_NHL = 27;
  ZB_CL = 12; ZB_NCL = 14;
  ZB_SL = 1; ZB_NSL = 13;
  ZB_MM = 3; ZB_NMM = 5;
  ZB_TL: array [0 .. 14] of Integer = (0, 1, 2, 4, 8, 12, 16, 32, 48, 64, 128,
    256, 512, 999, 1024);
  ZB_NST = 9;
  ZB_TOTAL = ZB_NWL * ZB_NHL * ZB_NCL * ZB_NSL * ZB_NMM * 15 * ZB_NST;
  ZB_CHUNK = 4096;

type
  TZBParams = array [0 .. 6] of Integer;   // wl hl cl sl mm tl st

  PZBJob = ^TZBJob;

  TZBJob = record
    NewInput, OldInput: Pointer;
    NewSize, OldSize: Integer;
    Checksum, ContentSize: Integer;
    Raw: TArray<Integer>;      // candidates to compress (indices into the list)
    Hit: TArray<Boolean>;
    Count: Integer;
    Next: Integer;
  end;

var
  ZBPerm: TArray<Integer>;
  ZBActive: Integer = 0;

function ZBParams(Raw: Integer): TZBParams;
begin
  Result[6] := Raw mod ZB_NST + 1;          Raw := Raw div ZB_NST;
  Result[5] := ZB_TL[Raw mod 15];           Raw := Raw div 15;
  Result[4] := Raw mod ZB_NMM + ZB_MM;      Raw := Raw div ZB_NMM;
  Result[3] := Raw mod ZB_NSL + ZB_SL;      Raw := Raw div ZB_NSL;
  Result[2] := Raw mod ZB_NCL + ZB_CL;      Raw := Raw div ZB_NCL;
  Result[1] := Raw mod ZB_NHL + ZB_HL;      Raw := Raw div ZB_NHL;
  Result[0] := Raw + ZB_WL;
end;

function ZBLine(Raw: Integer): String;
var
  P: TZBParams;
begin
  P := ZBParams(Raw);
  Result := Format('-cfgzstdwl%d:hl%d:cl%d:sl%d:mm%d:tl%d:st%d',
    [P[0], P[1], P[2], P[3], P[4], P[5], P[6]]);
end;

{$PUSH}{$Q-}{$R-}
// Delphi's Random(Range) with its default generator, as 0.9.9 calls it.
function ZBRandom(var Seed: Cardinal; Range: Cardinal): Cardinal;
begin
  Seed := Seed * $08088405 + 1;
  Result := (UInt64(Seed) * Range) shr 32;
end;

// 0.9.9's shuffled order, built once (186 MB, as an array of the 46 million
// candidate indices; 0.9.9 keeps the parameter records themselves, 1.3 GB).
procedure ZBBuildPerm;
var
  I, J, T: Integer;
  Seed: Cardinal;
begin
  EnterCriticalSection(ZLock);
  try
    if Length(ZBPerm) = ZB_TOTAL then
      exit;
    SetLength(ZBPerm, ZB_TOTAL);
    for I := 0 to ZB_TOTAL - 1 do
      ZBPerm[I] := I;
    Seed := 12911;
    for I := ZB_TOTAL - 1 downto 1 do
    begin
      J := ZBRandom(Seed, I + 1);
      T := ZBPerm[I];
      ZBPerm[I] := ZBPerm[J];
      ZBPerm[J] := T;
    end;
  finally
    LeaveCriticalSection(ZLock);
  end;
end;
{$POP}

procedure ZBSetParams(Ctx: Pointer; const P: TZBParams);
var
  I: Integer;
begin
  for I := 0 to 6 do
    ZSTD_CCtx_setParameter(Ctx, ZSTD_cParameter(101 + I), P[I]);
end;

procedure ZBWorker(JobPtr, Unused: IntPtr);
var
  Job: PZBJob;
  Ctx: Pointer;
  Dst: Pointer;
  I, Cap: Integer;
  R: size_t;
begin
  Job := PZBJob(JobPtr);
  Ctx := ZSTD_createCCtx;
  // zstd refuses a capacity short of its worst case (measured: exactly the
  // frame's size gives an error), so no stopping early on a long output.
  Cap := Job^.NewSize + (Job^.NewSize shr 7) + 65536;
  GetMem(Dst, Cap);
  try
    while True do
    begin
      I := AtomicIncrement(Job^.Next) - 1;
      if I >= Job^.Count then
        break;
      ZSTD_CCtx_reset(Ctx, ZSTD_reset_parameters);
      ZSTD_CCtx_setParameter(Ctx, ZSTD_c_checksumFlag, Job^.Checksum);
      ZSTD_CCtx_setParameter(Ctx, ZSTD_c_contentSizeFlag, Job^.ContentSize);
      ZBSetParams(Ctx, ZBParams(Job^.Raw[I]));
      R := ZSTD_compress2(Ctx, Dst, Cap, Job^.NewInput, Job^.NewSize);
      Job^.Hit[I] := (ZSTD_isError(R) = 0) and (R = size_t(Job^.OldSize)) and
        CompareMem(Dst, Job^.OldInput, Job^.OldSize);
    end;
  finally
    FreeMem(Dst);
    ZSTD_freeCCtx(Ctx);
  end;
end;

procedure ZSTDBrute(OldInput, NewInput: Pointer; StreamInfo: PStrInfo2);
var
  N, Pos, I, J, Matches, Threads: Integer;
  Key: UInt64;
  Keys: TDictionary<UInt64, Integer>;
  Results: TArray<Boolean>;
  Slot: TArray<Integer>;
  Job: TZBJob;
  Tasks: TArray<TTask>;
  CP: Pointer;
  P: TZBParams;
  C: ZSTD_compressionParameters;

  function KeyOf(Raw: Integer): UInt64;
  var
    K: Integer;
  begin
    P := ZBParams(Raw);
    if Assigned(CP) then
    begin
      ZSTD_CCtxParams_init(CP, 3);
      for K := 0 to 6 do
        ZSTD_CCtxParams_setParameter(CP, ZSTD_cParameter(101 + K), P[K]);
      C := ZSTD_getCParamsFromCCtxParams(CP, StreamInfo^.NewSize, 0, 0);
      // Parameters zstd 1.6.0 does not read for that strategy (its sources:
      // zstd_fast.c, zstd_double_fast.c, zstd_lazy.c, zstd_opt.c; checked on
      // 831 pairs that differ only there: identical output every time).
      case Ord(C.strategy) of
        1:
          begin
            C.chainLog := 0;
            C.searchLog := 0;
          end;
        2:
          begin
            C.searchLog := 0;
            C.targetLength := 0;
          end;
        3 .. 5:
          begin
            C.targetLength := 0;
            if C.windowLog > 14 then   // row matchfinder: no chain table
              C.chainLog := 0;
          end;
        6:
          C.targetLength := 0;
      end;
      Result := UInt64(C.windowLog) or (UInt64(C.hashLog) shl 6) or
        (UInt64(C.chainLog) shl 12) or (UInt64(C.searchLog) shl 18) or
        (UInt64(C.minMatch) shl 24) or (UInt64(Ord(C.strategy)) shl 28) or
        (UInt64(C.targetLength) shl 32);
    end
    else
      // without it, only exact repeats are skipped
      Result := UInt64(Raw);
  end;

begin
  N := BruteCount(ZB_TOTAL);
  ZBBuildPerm;
  CP := nil;
  if Assigned(ZSTD_getCParamsFromCCtxParams) and Assigned(ZSTD_createCCtxParams)
    and Assigned(ZSTD_versionNumber) and (ZSTD_versionNumber >= 10500) then
    CP := ZSTD_createCCtxParams;
  Threads := Max(1, ZThreads div Max(1, AtomicIncrement(ZBActive)));
  Keys := TDictionary<UInt64, Integer>.Create;
  try
    Job.OldInput := OldInput;
    Job.NewInput := NewInput;
    Job.OldSize := StreamInfo^.OldSize;
    Job.NewSize := StreamInfo^.NewSize;
    Job.Checksum := GetBits(StreamInfo^.Option, 27, 1);
    Job.ContentSize := Ord(GetBits(StreamInfo^.Option, 28, 2) <> 0);
    SetLength(Slot, ZB_CHUNK);
    Matches := 0;
    Pos := 0;
    while (Pos < N) and (Matches < BRUTE_MATCHES) do
    begin
      // the chunk's candidates, each new set of resolved parameters once
      Job.Count := 0;
      SetLength(Job.Raw, ZB_CHUNK);
      for I := Pos to Min(N, Pos + ZB_CHUNK) - 1 do
      begin
        Key := KeyOf(ZBPerm[I]);
        if not Keys.TryGetValue(Key, J) then
        begin
          J := Length(Results) + Job.Count;
          Keys.Add(Key, J);
          Job.Raw[Job.Count] := ZBPerm[I];
          Inc(Job.Count);
        end;
        Slot[I - Pos] := J;
      end;
      if Job.Count > 0 then
      begin
        SetLength(Job.Hit, Job.Count);
        Job.Next := 0;
        SetLength(Tasks, Min(Threads, Job.Count));
        for I := 0 to High(Tasks) do
        begin
          Tasks[I] := TTask.Create(IntPtr(@Job), I);
          Tasks[I].Perform(ZBWorker);
          Tasks[I].Start;
        end;
        for I := 0 to High(Tasks) do
        begin
          Tasks[I].Wait;
          Tasks[I].Free;
        end;
        J := Length(Results);
        SetLength(Results, J + Job.Count);
        for I := 0 to Job.Count - 1 do
          Results[J + I] := Job.Hit[I];
      end;
      // matches in the list's order
      for I := Pos to Min(N, Pos + ZB_CHUNK) - 1 do
        if Results[Slot[I - Pos]] then
        begin
          BruteAdd(ZBLine(ZBPerm[I]));
          Inc(Matches);
          if Matches >= BRUTE_MATCHES then
            break;
        end;
      Inc(Pos, ZB_CHUNK);
    end;
  finally
    AtomicDecrement(ZBActive);
    Keys.Free;
    if Assigned(CP) then
      ZSTD_freeCCtxParams(CP);
  end;
end;

function ZSTDProcess(Instance, Depth: Integer; OldInput, NewInput: Pointer;
  StreamInfo: PStrInfo2; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  Params: String;
  A, B: Integer;
  I: Integer;
  X: Integer;
  Res1: NativeInt;
  Res2: NativeUInt;
  Inp: ZSTD_inBuffer;
  Oup: ZSTD_outBuffer;
  Progress: NativeInt;
  EndOp: ZSTD_EndDirective;
  Rem: size_t;
begin
  Result := False;
  X := GetBits(StreamInfo^.Option, 0, 3);
  if BoolArray(CodecAvailable, False) or (CodecAvailable[X] = False) then
    exit;
  // -b: search the stream's parameters instead of processing it (as 0.9.9)
  if BRUTE then
  begin
    BruteRan;
    if StreamInfo^.NewSize <= BRUTE_MAXSIZE then
      ZSTDBrute(OldInput, NewInput, StreamInfo);
    exit;
  end;
  Buffer := Funcs^.Allocator(Instance, StreamInfo^.NewSize);
  SOList[Instance][X].Index := 0;
  while SOList[Instance][X].Get(I) >= 0 do
  begin
    if StreamInfo^.Status >= TStreamStatus.Predicted then
    begin
      if GetBits(StreamInfo^.Option, 3, 5) <> I then
        continue;
      if (StreamInfo^.Status = TStreamStatus.Database) and
        (GetBits(StreamInfo^.Option, 31, 1) = 0) then
      begin
        Res1 := StreamInfo^.OldSize;
        Result := True;
      end;
    end;
    Params := '';
    case X of
      ZSTD_CODEC:
        begin
          Params := 'l' + I.ToString + ':' + 'f' + GetBits(StreamInfo^.Option,
            8, 1).ToString + ':' + 'w' + GetBits(StreamInfo^.Option, 9, 5)
            .ToString + ':' + 'b' + GetBits(StreamInfo^.Option, 14, 13)
            .ToString;
          if not Assigned(cctx[Instance]) then
            cctx[Instance] := ZSTD_createCCtx;
          if StreamInfo^.Status <> TStreamStatus.Database then
            StreamInfo^.Resource := ZCfgForStream;
          if not Result then
          begin
            if GetBits(StreamInfo^.Option, 14, 13) = 0 then
            begin
              ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_compressionLevel,
                IfThen(GetBits(StreamInfo^.Option, 8, 1) = 0, I, -I));
              ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_windowLog,
                GetBits(StreamInfo^.Option, 9, 5));
              ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_checksumFlag,
                GetBits(StreamInfo^.Option, 27, 1));
              ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_contentSizeFlag,
                Ord(GetBits(StreamInfo^.Option, 28, 2) <> 0));
              ZCfgApply(cctx[Instance], StreamInfo^.Resource);
              if Assigned(ZSTD_compress2) then
                Res1 := ZSTD_compress2(cctx[Instance], Buffer,
                  StreamInfo^.NewSize, NewInput, StreamInfo^.NewSize)
              else if Assigned(ZSTD_compress_generic) then
              begin
                Oup.dst := Buffer;
                Oup.Size := StreamInfo^.NewSize;
                Oup.Pos := 0;
                Inp.src := PByte(NewInput);
                Inp.Size := StreamInfo^.NewSize;
                Inp.Pos := 0;
                ZSTD_compress_generic(cctx[Instance], @Oup, @Inp, ZSTD_e_end);
                Res1 := Oup.Pos;
              end
              else
                Res1 := ZSTD_compressCCtx(cctx[Instance], Buffer,
                  StreamInfo^.NewSize, NewInput, StreamInfo^.NewSize,
                  IfThen(GetBits(StreamInfo^.Option, 8, 1) = 0, I, -I))
            end
            else
            begin
              Progress := 0;
              Oup.dst := Buffer;
              Oup.Size := StreamInfo^.NewSize;
              Oup.Pos := 0;
              // initCStream resetea el contexto, asi que los parametros van
              // DESPUES. Antes esta rama no recibia el flag de checksum ni el
              // de tamaño -- solo se seteaban en la rama de una-pasada -- asi
              // que el streaming nunca podia reproducir un frame del CLI.
              ZSTD_initCStream(cctx[Instance],
                IfThen(GetBits(StreamInfo^.Option, 8, 1) = 0, I, -I));
              ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_checksumFlag,
                GetBits(StreamInfo^.Option, 27, 1));
              ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_contentSizeFlag,
                Ord(GetBits(StreamInfo^.Option, 28, 2) <> 0));
              ZCfgApply(cctx[Instance], StreamInfo^.Resource);
              if Assigned(ZSTD_CCtx_setPledgedSrcSize) then
                ZSTD_CCtx_setPledgedSrcSize(cctx[Instance],
                  StreamInfo^.NewSize);
              while Progress < StreamInfo^.NewSize do
              begin
                Inp.src := PByte(NewInput) + Progress;
                Inp.Size := Min(StreamInfo^.NewSize - Progress,
                  GetBits(StreamInfo^.Option, 14, 13) * 1024);
                Inp.Pos := 0;
                if Progress + NativeInt(Inp.Size) >= StreamInfo^.NewSize then
                  EndOp := ZSTD_e_end
                else
                  EndOp := ZSTD_e_continue;
                // Sin ZSTD_flushStream por chunk: el CLI no lo hace y forzarlo
                // cambia el bitstream. Medido con libzstd 1.5.7 sobre 450KB,
                // niveles 3/9/15: chunked con pledged size y sin flush da el
                // mismo hash que el CLI; con flush difiere en los tres.
                repeat
                  if Assigned(ZSTD_compressStream2) then
                    Rem := ZSTD_compressStream2(cctx[Instance], @Oup, @Inp,
                      EndOp)
                  else
                    Rem := ZSTD_compress_generic(cctx[Instance], @Oup, @Inp,
                      EndOp);
                until (Inp.Pos >= Inp.Size) and
                  ((EndOp <> ZSTD_e_end) or (Rem = 0));
                Inc(Progress, NativeInt(Inp.Size));
              end;
              Res1 := Oup.Pos;
            end;
            { Res1 := ZSTD_compress_usingCDict(cctx[Instance], Buffer,
              StreamInfo^.NewSize, NewInput, StreamInfo^.NewSize, cdict); }
          end;
        end;
    end;
    if not Result then
      Result := (Res1 = StreamInfo^.OldSize) and CompareMem(OldInput, Buffer,
        StreamInfo^.OldSize);
    Funcs^.LogProcess(ZSTDCodecs[GetBits(StreamInfo^.Option, 0, 3)],
      PChar(Params), StreamInfo^.OldSize, StreamInfo^.NewSize, Res1, Result);
    if Result or (StreamInfo^.Status >= TStreamStatus.Predicted) then
      break;
  end;
  if Result and OPTIMISE_DEC and (StreamInfo^.Status <> TStreamStatus.Database)
    and (GetBits(StreamInfo^.Option, 8, 1) = 0) then
  begin
    A := Pred(I);
    for B := A downto 1 do
    begin
      if not Assigned(cctx[Instance]) then
        cctx[Instance] := ZSTD_createCCtx;
      Res1 := ZSTD_compressCCtx(cctx[Instance], Buffer, StreamInfo^.NewSize,
        NewInput, StreamInfo^.NewSize, B);
      if (Res1 = StreamInfo^.OldSize) and CompareMem(OldInput, Buffer,
        StreamInfo^.OldSize) then
        I := B
      else
        break;
    end;
  end
  else if (Result = False) and (PATCH_ALL or
    (StreamInfo^.Status >= TStreamStatus.Predicted)
    or (SOList[Instance][X].Count = 1)) and (DIFF_TOLERANCE > 0) then
  begin
    Res2 := PrecompEncodePatchEx(Instance, OldInput, StreamInfo^.OldSize,
      Buffer, Res1, Output);
    Funcs^.LogPatch1(StreamInfo^.OldSize, Res1, Res2,
      Funcs^.AcceptPatch(StreamInfo^.OldSize, Res1, Res2));
    if Funcs^.AcceptPatch(StreamInfo^.OldSize, Res1, Res2) then
    begin
      SetBits(StreamInfo^.Option, 1, 31, 1);
      SOList[Instance][X].Add(I);
      Result := True;
    end;
  end;
  if Result then
  begin
    SetBits(StreamInfo^.Option, I, 3, 5);
    SOList[Instance][X].Add(I);
  end;
end;

function ZSTDRestore(Instance, Depth: Integer; Input, InputExt: Pointer;
  StreamInfo: _StrInfo3; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  Params: String;
  X: Integer;
  Res1: NativeInt;
  Res2: NativeUInt;
  Inp: ZSTD_inBuffer;
  Oup: ZSTD_outBuffer;
  Progress: NativeInt;
  EndOp: ZSTD_EndDirective;
  Rem: size_t;
begin
  Result := False;
  X := GetBits(StreamInfo.Option, 0, 3);
  if BoolArray(CodecAvailable, False) or (CodecAvailable[X] = False) then
    exit;
  Buffer := Funcs^.Allocator(Instance, StreamInfo.NewSize);
  Params := 'l' + GetBits(StreamInfo.Option, 3, 5).ToString + ':' + 'f' +
    GetBits(StreamInfo.Option, 8, 1).ToString + ':' + 'b' +
    GetBits(StreamInfo.Option, 14, 13).ToString;
  case X of
    ZSTD_CODEC:
      begin
        if not Assigned(cctx[Instance]) then
          cctx[Instance] := ZSTD_createCCtx;
        if GetBits(StreamInfo.Option, 14, 13) = 0 then
        begin
          ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_compressionLevel,
            IfThen(GetBits(StreamInfo.Option, 8, 1) = 0,
            GetBits(StreamInfo.Option, 3, 5),
            -GetBits(StreamInfo.Option, 3, 5)));
          ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_windowLog,
            GetBits(StreamInfo.Option, 9, 5));
          // Simetrico con Process: sin esto el decode reconstruiria un frame
          // distinto del que se codifico.
          ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_checksumFlag,
            GetBits(StreamInfo.Option, 27, 1));
          ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_contentSizeFlag,
            Ord(GetBits(StreamInfo.Option, 28, 2) <> 0));
          ZCfgApply(cctx[Instance], StreamInfo.Resource);
          if Assigned(ZSTD_compress2) then
            Res1 := ZSTD_compress2(cctx[Instance], Buffer, StreamInfo.NewSize,
              Input, StreamInfo.NewSize)
          else if Assigned(ZSTD_compress_generic) then
          begin
            Oup.dst := Buffer;
            Oup.Size := StreamInfo.NewSize;
            Oup.Pos := 0;
            Inp.src := PByte(Input);
            Inp.Size := StreamInfo.NewSize;
            Inp.Pos := 0;
            ZSTD_compress_generic(cctx[Instance], @Oup, @Inp, ZSTD_e_end);
            Res1 := Oup.Pos;
          end
          else
            Res1 := ZSTD_compressCCtx(cctx[Instance], Buffer,
              StreamInfo.NewSize, Input, StreamInfo.NewSize,
              IfThen(GetBits(StreamInfo.Option, 8, 1) = 0,
              GetBits(StreamInfo.Option, 3, 5),
              -GetBits(StreamInfo.Option, 3, 5)));
        end
        else
        begin
          Progress := 0;
          Oup.dst := Buffer;
          Oup.Size := StreamInfo.NewSize;
          Oup.Pos := 0;
          // SIMETRICO CON ZSTDProcess. Tiene que serlo: mientras Process uso
          // la receta nueva y Restore la vieja, Process aceptaba un candidato
          // que Restore no podia reconstruir -- medido, 1/1 en el scan y
          // round-trip roto. Cualquier cambio de un lado va del otro.
          ZSTD_initCStream(cctx[Instance],
            IfThen(GetBits(StreamInfo.Option, 8, 1) = 0,
            GetBits(StreamInfo.Option, 3, 5),
            -GetBits(StreamInfo.Option, 3, 5)));
          ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_checksumFlag,
            GetBits(StreamInfo.Option, 27, 1));
          ZSTD_CCtx_setParameter(cctx[Instance], ZSTD_c_contentSizeFlag,
            Ord(GetBits(StreamInfo.Option, 28, 2) <> 0));
          ZCfgApply(cctx[Instance], StreamInfo.Resource);
          if Assigned(ZSTD_CCtx_setPledgedSrcSize) then
            ZSTD_CCtx_setPledgedSrcSize(cctx[Instance], StreamInfo.NewSize);
          while Progress < StreamInfo.NewSize do
          begin
            Inp.src := PByte(Input) + Progress;
            Inp.Size := Min(StreamInfo.NewSize - Progress,
              GetBits(StreamInfo.Option, 14, 13) * 1024);
            Inp.Pos := 0;
            if Progress + NativeInt(Inp.Size) >= StreamInfo.NewSize then
              EndOp := ZSTD_e_end
            else
              EndOp := ZSTD_e_continue;
            repeat
              if Assigned(ZSTD_compressStream2) then
                Rem := ZSTD_compressStream2(cctx[Instance], @Oup, @Inp, EndOp)
              else
                Rem := ZSTD_compress_generic(cctx[Instance], @Oup, @Inp, EndOp);
            until (Inp.Pos >= Inp.Size) and
              ((EndOp <> ZSTD_e_end) or (Rem = 0));
            Inc(Progress, NativeInt(Inp.Size));
          end;
          Res1 := Oup.Pos;
        end;
        { Res1 := ZSTD_compress_usingCDict(cctx[Instance], Buffer,
          StreamInfo.NewSize, Input, StreamInfo.NewSize, cdict); }
      end;
  end;
  Funcs^.LogRestore(ZSTDCodecs[GetBits(StreamInfo.Option, 0, 3)], PChar(Params),
    StreamInfo.OldSize, StreamInfo.NewSize, Res1, True);
  if GetBits(StreamInfo.Option, 31, 1) = 1 then
  begin
    Res2 := PrecompDecodePatchEx(Instance, InputExt, StreamInfo.ExtSize, Buffer,
      Res1, Output);
    Funcs^.LogPatch2(StreamInfo.OldSize, Res1, StreamInfo.ExtSize, Res2 > 0);
    if Res2 = StreamInfo.OldSize then
      Result := True;
    exit;
  end;
  if Res1 = StreamInfo.OldSize then
  begin
    Output(Instance, Buffer, StreamInfo.OldSize);
    Result := True;
  end;
end;

var
  I: Integer;

initialization

InitCriticalSection(ZLock);
Codec.Names := [];
for I := Low(ZSTDCodecs) to High(ZSTDCodecs) do
begin
  Codec.Names := Codec.Names + [ZSTDCodecs[I]];
  StockMethods.Add(ZSTDCodecs[I]);
end;
Codec.Initialised := False;
Codec.Init := @ZSTDInit;
Codec.Free := @ZSTDFree;
Codec.Parse := @ZSTDParse;
Codec.Scan1 := @ZSTDScan1;
Codec.Scan2 := @ZSTDScan2;
Codec.Process := @ZSTDProcess;
Codec.Restore := @ZSTDRestore;
SetLength(CodecAvailable, Length(Codec.Names));
SetLength(CodecEnabled, Length(Codec.Names));

end.
