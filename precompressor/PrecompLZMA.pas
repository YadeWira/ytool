unit PrecompLZMA;

interface

uses
  LZMALib,
  Utils,
  PrecompUtils,
  SysUtils, StrUtils, Classes, Math, Generics.Collections;

var
  Codec: TPrecompressor;

implementation

const
  LzmaName: PChar = 'lzma';
  { dictSize/lc/lp/pb are always taken verbatim from the stream's own header
    (they're stored there), so re-encoding always targets the exact same
    properties. "level" isn't stored in the format at all -- it only
    influences the match finder (algo/fb), so it has to be guessed like
    LZ4HC's compression level. These 7 span both algo classes (fast for
    level<5, normal for >=5) and both fb defaults (32 vs 64 for level>=7),
    covering the presets real encoders actually ship. }
  LzmaLevels: array [0 .. 6] of Integer = (0, 1, 3, 5, 6, 7, 9);
  MinLzmaSize = 64;
  MaxLzmaUncompSize = 64 * 1024 * 1024;
  MaxLzmaDictSize = 1 shl 30;
  HeaderSize = 13;
  LZMA_UNKNOWN_SIZE = UInt64($FFFFFFFFFFFFFFFF);

var
  SOList: array of TSOList;
  CodecEnabled: Boolean;

{ The 13-byte header's size field is either the real uncompressed size, or
  $FFFFFFFFFFFFFFFF meaning "unknown, decode until the end-of-data marker"
  -- what the "xz --format=lzma" CLI actually writes by default. Both are
  handled; KnownSize has to be persisted (in Option) so Process/Restore
  reconstruct the exact same header byte for byte. }
function LzmaHeaderValid(Input: PByte; SizeEx, Pos: NativeInt;
  out UncompSize: UInt64; out DictSize: Cardinal;
  out KnownSize: Boolean): Boolean;
begin
  Result := False;
  if SizeEx - Pos < HeaderSize + 1 then
    exit;
  if (Input + Pos)^ >= 225 then
    exit;
  DictSize := PCardinal(Input + Pos + 1)^;
  if (DictSize = 0) or (DictSize > MaxLzmaDictSize) then
    exit;
  UncompSize := PUInt64(Input + Pos + 5)^;
  KnownSize := UncompSize <> LZMA_UNKNOWN_SIZE;
  if KnownSize and ((UncompSize < MinLzmaSize) or
    (UncompSize > MaxLzmaUncompSize)) then
    exit;
  Result := True;
end;

function LzmaProps(Option: Integer; out Lc, Lp, Pb: Integer): Byte;
begin
  Result := Byte(GetBits(Option, 0, 8));
  Lc := Result mod 9;
  Lp := (Result div 9) mod 5;
  Pb := Result div 45;
end;

function LZMAInit(Command: PChar; Count: Integer; Funcs: PPrecompFuncs): Boolean;
var
  X: Integer;
  S: String;
  Options: TArray<Integer>;
begin
  Result := True;
  CodecEnabled := False;
  SetLength(SOList, Count);
  SetLength(Options, 0);
  for X := Low(LzmaLevels) to High(LzmaLevels) do
    Insert(X, Options, Length(Options));
  for X := Low(SOList) to High(SOList) do
  begin
    SOList[X] := TSOList.Create([], TSOMethod.MTF);
    SOList[X].Update(Options);
  end;
  X := 0;
  while Funcs^.GetCodec(Command, X, False) <> '' do
  begin
    S := Funcs^.GetCodec(Command, X, False);
    if CompareText(S, LzmaName) = 0 then
      CodecEnabled := True;
    Inc(X);
  end;
end;

procedure LZMAFree(Funcs: PPrecompFuncs);
var
  X: Integer;
begin
  for X := Low(SOList) to High(SOList) do
    SOList[X].Free;
end;

function LZMAParse(Command: PChar; Option: PInteger;
  Funcs: PPrecompFuncs): Boolean;
var
  S: String;
  I: Integer;
begin
  Result := False;
  Option^ := 0;
  I := 0;
  while Funcs^.GetCodec(Command, I, False) <> '' do
  begin
    S := Funcs^.GetCodec(Command, I, False);
    if CompareText(S, LzmaName) = 0 then
      Result := True;
    Inc(I);
  end;
end;

procedure LZMAScan1(Instance, Depth: Integer; Input: PByte;
  Size, SizeEx: NativeInt; Output: _PrecompOutput; Add: _PrecompAdd;
  Funcs: PPrecompFuncs);
var
  Pos: NativeInt;
  UncompSize: UInt64;
  DictSize: Cardinal;
  KnownSize: Boolean;
  Buffer: PByte;
  DestLen, SrcLen: NativeUInt;
  Res: Integer;
  Accepted: Boolean;
  SI: _StrInfo1;
begin
  if not CodecEnabled then
    exit;
  Pos := 0;
  while Pos < Size do
  begin
    if LzmaHeaderValid(Input, SizeEx, Pos, UncompSize, DictSize, KnownSize)
    then
    begin
      SrcLen := SizeEx - Pos - HeaderSize;
      if KnownSize then
      begin
        Buffer := Funcs^.Allocator(Instance, UncompSize);
        DestLen := UncompSize;
        Res := LzmaUncompress(Buffer, @DestLen, Input + Pos + HeaderSize,
          @SrcLen, Input + Pos, LZMA_PROPS_SIZE);
        Accepted := (Res = SZ_OK) and (DestLen = UncompSize);
      end
      else
      begin
        Buffer := Funcs^.Allocator(Instance, MaxLzmaUncompSize);
        DestLen := MaxLzmaUncompSize;
        Res := LzmaDecodeToEndMark(Buffer, @DestLen, Input + Pos + HeaderSize,
          @SrcLen, Input + Pos, LZMA_PROPS_SIZE);
        Accepted := (Res = SZ_OK) and (DestLen >= MinLzmaSize);
      end;
      if Accepted then
      begin
        Output(Instance, Buffer, DestLen);
        SI.Position := Pos;
        SI.OldSize := HeaderSize + SrcLen;
        SI.NewSize := DestLen;
        SI.Resource := Integer(DictSize);
        SI.Option := 0;
        SetBits(SI.Option, (Input + Pos)^, 0, 8);
        SetBits(SI.Option, Ord(KnownSize), 11, 1);
        SI.Status := TStreamStatus.None;
        Funcs^.LogScan1(LzmaName, SI.Position, SI.OldSize, SI.NewSize);
        Add(Instance, @SI, nil, nil);
        Inc(Pos, SI.OldSize);
        continue;
      end;
    end;
    Inc(Pos);
  end;
end;

function LZMAScan2(Instance, Depth: Integer; Input: Pointer; Size: NativeInt;
  StreamInfo: PStrInfo2; Offset: PInteger; Output: _PrecompOutput;
  Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  DestLen, SrcLen: NativeUInt;
  Res: Integer;
  KnownSize: Boolean;
begin
  Result := False;
  if StreamInfo^.OldSize <= HeaderSize then
    exit;
  KnownSize := GetBits(StreamInfo^.Option, 11, 1) = 1;
  SrcLen := StreamInfo^.OldSize - HeaderSize;
  if KnownSize then
  begin
    Buffer := Funcs^.Allocator(Instance, StreamInfo^.NewSize);
    DestLen := StreamInfo^.NewSize;
    Res := LzmaUncompress(Buffer, @DestLen, PByte(Input) + HeaderSize,
      @SrcLen, Input, LZMA_PROPS_SIZE);
  end
  else
  begin
    Buffer := Funcs^.Allocator(Instance, StreamInfo^.NewSize);
    DestLen := StreamInfo^.NewSize;
    Res := LzmaDecodeToEndMark(Buffer, @DestLen, PByte(Input) + HeaderSize,
      @SrcLen, Input, LZMA_PROPS_SIZE);
  end;
  if (Res = SZ_OK) and (DestLen = NativeUInt(StreamInfo^.NewSize)) then
  begin
    Output(Instance, Buffer, DestLen);
    Funcs^.LogScan2(LzmaName, StreamInfo^.OldSize, StreamInfo^.NewSize);
    Result := True;
  end;
end;

function LZMAEncodeInto(Buffer: PByte; BufSize: NativeInt; NewInput: Pointer;
  NewSize, Level: Integer; DictSize: Cardinal; Lc, Lp, Pb: Integer;
  KnownSize: Boolean): NativeInt;
var
  DestLen, OutPropsLen: NativeUInt;
  CRes: Integer;
begin
  Result := 0;
  DestLen := BufSize - HeaderSize;
  OutPropsLen := LZMA_PROPS_SIZE;
  CRes := LzmaCompressEx(Buffer + HeaderSize, @DestLen, NewInput, NewSize,
    Buffer, @OutPropsLen, Level, DictSize, Lc, Lp, Pb, -1, 1,
    Ord(not KnownSize));
  if (CRes <> SZ_OK) or (OutPropsLen <> LZMA_PROPS_SIZE) then
    exit;
  if KnownSize then
    PUInt64(Buffer + 5)^ := UInt64(NewSize)
  else
    PUInt64(Buffer + 5)^ := LZMA_UNKNOWN_SIZE;
  Result := HeaderSize + DestLen;
end;

function LZMAProcess(Instance, Depth: Integer; OldInput, NewInput: Pointer;
  StreamInfo: PStrInfo2; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  BufSize: NativeInt;
  I: Integer;
  Res1: NativeInt;
  Res2: NativeUInt;
  Lc, Lp, Pb: Integer;
  DictSize: Cardinal;
  KnownSize: Boolean;
begin
  Result := False;
  Res1 := 0;
  DictSize := Cardinal(StreamInfo^.Resource);
  KnownSize := GetBits(StreamInfo^.Option, 11, 1) = 1;
  LzmaProps(StreamInfo^.Option, Lc, Lp, Pb);
  BufSize := StreamInfo^.OldSize + (StreamInfo^.OldSize div 2) + 4096;
  Buffer := Funcs^.Allocator(Instance, BufSize);
  SOList[Instance].Index := 0;
  while SOList[Instance].Get(I) >= 0 do
  begin
    if StreamInfo^.Status >= TStreamStatus.Predicted then
    begin
      if GetBits(StreamInfo^.Option, 8, 3) <> I then
        continue;
      if (StreamInfo^.Status = TStreamStatus.Database) and
        (GetBits(StreamInfo^.Option, 31, 1) = 0) then
      begin
        Res1 := StreamInfo^.OldSize;
        Result := True;
      end;
    end;
    if not Result then
      Res1 := LZMAEncodeInto(Buffer, BufSize, NewInput, StreamInfo^.NewSize,
        LzmaLevels[I], DictSize, Lc, Lp, Pb, KnownSize);
    if not Result then
      Result := (Res1 = StreamInfo^.OldSize) and CompareMem(OldInput, Buffer,
        StreamInfo^.OldSize);
    Funcs^.LogProcess(LzmaName, PChar('lv' + LzmaLevels[I].ToString),
      StreamInfo^.OldSize, StreamInfo^.NewSize, Res1, Result);
    if Result or (StreamInfo^.Status >= TStreamStatus.Predicted) then
      break;
  end;
  if (Result = False) and ((StreamInfo^.Status >= TStreamStatus.Predicted) or
    (SOList[Instance].Count = 1)) and (DIFF_TOLERANCE > 0) then
  begin
    Res2 := PrecompEncodePatchEx(Instance, OldInput, StreamInfo^.OldSize,
      Buffer, Res1, Output);
    Funcs^.LogPatch1(StreamInfo^.OldSize, Res1, Res2,
      Funcs^.AcceptPatch(StreamInfo^.OldSize, Res1, Res2));
    if Funcs^.AcceptPatch(StreamInfo^.OldSize, Res1, Res2) then
    begin
      SetBits(StreamInfo^.Option, 1, 31, 1);
      SOList[Instance].Add(I);
      Result := True;
    end;
  end;
  if Result then
  begin
    SetBits(StreamInfo^.Option, I, 8, 3);
    SOList[Instance].Add(I);
  end;
end;

function LZMARestore(Instance, Depth: Integer; Input, InputExt: Pointer;
  StreamInfo: _StrInfo3; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  BufSize: NativeInt;
  Lc, Lp, Pb: Integer;
  DictSize: Cardinal;
  KnownSize: Boolean;
  Res1: NativeInt;
  Res2: NativeUInt;
  Level: Integer;
begin
  Result := False;
  DictSize := Cardinal(StreamInfo.Resource);
  KnownSize := GetBits(StreamInfo.Option, 11, 1) = 1;
  LzmaProps(StreamInfo.Option, Lc, Lp, Pb);
  Level := LzmaLevels[GetBits(StreamInfo.Option, 8, 3)];
  BufSize := StreamInfo.OldSize + (StreamInfo.OldSize div 2) + 4096;
  Buffer := Funcs^.Allocator(Instance, BufSize);
  Res1 := LZMAEncodeInto(Buffer, BufSize, Input, StreamInfo.NewSize, Level,
    DictSize, Lc, Lp, Pb, KnownSize);
  Funcs^.LogRestore(LzmaName, PChar('lv' + Level.ToString), StreamInfo.OldSize,
    StreamInfo.NewSize, Res1, True);
  if GetBits(StreamInfo.Option, 31, 1) = 1 then
  begin
    Res2 := PrecompDecodePatchEx(Instance, InputExt, StreamInfo.ExtSize,
      Buffer, Res1, Output);
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

initialization

Codec.Names := [LzmaName];
Codec.Initialised := False;
Codec.Init := @LZMAInit;
Codec.Free := @LZMAFree;
Codec.Parse := @LZMAParse;
Codec.Scan1 := @LZMAScan1;
Codec.Scan2 := @LZMAScan2;
Codec.Process := @LZMAProcess;
Codec.Restore := @LZMARestore;
StockMethods.Add(LzmaName);

end.
