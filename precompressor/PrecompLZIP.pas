unit PrecompLZIP;

// -mlzip: lzip members (.lz, tar.lz, plzip and tarlz output), rebuilt with
// lzlib. A member is "LZIP", version 1, the coded dictionary size, LZMA data
// and a 20-byte trailer (CRC32, data size, member size); the whole member is
// re-encoded and compared.
//
// lzip's levels are a dictionary size and a match length limit; the
// dictionary is in the header, so only the limit is searched: the ten of
// lzip -0..-9 (-0 is lzip's fast encoder, chosen in lzlib by a 65535-byte
// dictionary and a limit of 16), plus 16 with the normal encoder. Measured:
// lzlib 1.16 rebuilds every level of lzip 1.22, 1.24 and 1.26.

interface

uses
  LZlibDLL,
  Utils,
  PrecompUtils,
  SysUtils, StrUtils, Classes, Math;

var
  Codec: TPrecompressor;

implementation

const
  LzipName: PChar = 'lzip';
  LZIP_MAGIC = $50495A4C; // "LZIP"
  HeaderSize = 6;
  TrailerSize = 20;
  MinMemberSize = HeaderSize + TrailerSize + 1;
  MaxDataSize = 256 * 1024 * 1024;
  WorkSize = 65536;
  // lzip -0 .. -9, then 16 with the normal encoder
  MatchLens: array [0 .. 10] of Integer = (16, 5, 6, 8, 12, 20, 36, 68, 132,
    273, 16);
  // the dictionary each level sets, to try that level first
  LevelDicts: array [0 .. 9] of Integer = (1 shl 16, 1 shl 20, 3 shl 19,
    1 shl 21, 3 shl 20, 1 shl 22, 1 shl 23, 1 shl 24, 3 shl 23, 1 shl 25);

var
  SOList: array of TSOList;
  CodecEnabled: Boolean;

// The dictionary size coded in a header byte; 0 if the byte is not valid.
function DictFromByte(B: Byte): Integer;
var
  Bits: Integer;
begin
  Result := 0;
  Bits := B and 31;
  if not InRange(Bits, 12, 29) then
    exit;
  Result := 1 shl Bits;
  if (Bits = 12) and (B shr 5 <> 0) then
    exit(0);
  Dec(Result, (Result div 16) * (B shr 5));
end;

// Encodes Src into Dst as one lzip member; its size, or -1 (an error, or more
// than Cap bytes: then it is not the stream that was found anyway).
function LZEncode(Src: PByte; SrcLen: Integer; Dict, MatchLen: Integer;
  Dst: PByte; Cap: Integer): Integer;
var
  E: Pointer;
  I, O, W, R: Integer;
  Finished: Boolean;
begin
  Result := -1;
  E := LZ_compress_open(Dict, MatchLen, UInt64(1) shl 51);
  if E = nil then
    exit;
  try
    I := 0;
    O := 0;
    Finished := False;
    while True do
    begin
      if I < SrcLen then
      begin
        W := LZ_compress_write(E, Src + I, Min(SrcLen - I, WorkSize));
        if W < 0 then
          exit;
        Inc(I, W);
      end;
      if (I >= SrcLen) and not Finished then
      begin
        if LZ_compress_finish(E) < 0 then
          exit;
        Finished := True;
      end;
      if O >= Cap then
        exit;
      R := LZ_compress_read(E, Dst + O, Min(Cap - O, WorkSize));
      if R < 0 then
        exit;
      Inc(O, R);
      if LZ_compress_finished(E) = 1 then
        break;
    end;
    Result := O;
  finally
    LZ_compress_close(E);
  end;
end;

function LzipInit(Command: PChar; Count: Integer; Funcs: PPrecompFuncs)
  : Boolean;
var
  X: Integer;
  S: String;
  Options: TArray<Integer>;
begin
  Result := True;
  CodecEnabled := False;
  SetLength(SOList, Count);
  Options := nil;
  for X := Low(MatchLens) to High(MatchLens) do
    Insert(X, Options, Length(Options));
  for X := Low(SOList) to High(SOList) do
  begin
    SOList[X] := TSOList.Create([], TSOMethod.MTF);
    SOList[X].Update(Options);
    SOList[X].Add(6); // lzip's default
  end;
  X := 0;
  while Funcs^.GetCodec(Command, X, False) <> '' do
  begin
    S := Funcs^.GetCodec(Command, X, False);
    if (CompareText(S, LzipName) = 0) and LZlibDLL.DLLLoaded then
      CodecEnabled := True;
    Inc(X);
  end;
end;

procedure LzipFree(Funcs: PPrecompFuncs);
var
  X: Integer;
begin
  for X := Low(SOList) to High(SOList) do
    SOList[X].Free;
end;

function LzipParse(Command: PChar; Option: PInteger;
  Funcs: PPrecompFuncs): Boolean;
var
  I: Integer;
begin
  Result := False;
  Option^ := 0;
  I := 0;
  while Funcs^.GetCodec(Command, I, False) <> '' do
  begin
    if (CompareText(Funcs^.GetCodec(Command, I, False), LzipName) = 0) and
      LZlibDLL.DLLLoaded then
      Result := True;
    Inc(I);
  end;
end;

// Decodes the member at Input (Avail bytes there); its compressed and
// uncompressed sizes, with the data handed to Output, or False.
function DecodeMember(Instance: Integer; Input: PByte; Avail: NativeInt;
  Output: _PrecompOutput; out InSize, OutSize: Int64): Boolean;
var
  D: Pointer;
  Buf: array [0 .. WorkSize - 1] of Byte;
  Fed: NativeInt;
  W, R: Integer;
  Finished, MemberEnd: Boolean;
begin
  Result := False;
  InSize := 0;
  OutSize := 0;
  D := LZ_decompress_open;
  if D = nil then
    exit;
  try
    Fed := 0;
    Finished := False;
    Output(Instance, nil, 0);
    while True do
    begin
      // fed a little at a time, so it stops at the end of this member
      if Fed < Avail then
      begin
        W := LZ_decompress_write(D, Input + Fed, Min(Avail - Fed, 4096));
        if W < 0 then
          exit;
        Inc(Fed, W);
      end
      else if not Finished then
      begin
        LZ_decompress_finish(D);
        Finished := True;
      end;
      // member_finished is 1 right after the read that ends the member, and
      // no longer after the next one: asked after every read
      MemberEnd := False;
      repeat
        R := LZ_decompress_read(D, @Buf[0], WorkSize);
        if R < 0 then
          exit;
        if R > 0 then
        begin
          Inc(OutSize, R);
          if OutSize > MaxDataSize then
            exit;
          Output(Instance, @Buf[0], R);
        end;
        MemberEnd := LZ_decompress_member_finished(D) = 1;
      until (R = 0) or MemberEnd;
      if MemberEnd then
        break;
      if Finished and (Fed >= Avail) then
        exit;
    end;
    InSize := LZ_decompress_total_in_size(D);
    // the trailer's member size has to say the same
    Result := (InSize >= MinMemberSize) and (InSize <= Avail) and
      (PInt64(Input + InSize - 8)^ = InSize) and (OutSize > 0);
  finally
    LZ_decompress_close(D);
  end;
end;

procedure LzipScan1(Instance, Depth: Integer; Input: PByte;
  Size, SizeEx: NativeInt; Output: _PrecompOutput; Add: _PrecompAdd;
  Funcs: PPrecompFuncs);
var
  Pos: NativeInt;
  InSize, OutSize: Int64;
  SI: _StrInfo1;
begin
  if not CodecEnabled then
    exit;
  Pos := 0;
  while Pos < Size do
  begin
    if (SizeEx - Pos >= MinMemberSize) and
      (PCardinal(Input + Pos)^ = LZIP_MAGIC) and ((Input + Pos + 4)^ = 1) and
      (DictFromByte((Input + Pos + 5)^) > 0) then
      if DecodeMember(Instance, Input + Pos, SizeEx - Pos, Output, InSize,
        OutSize) then
      begin
        SI.Position := Pos;
        SI.OldSize := InSize;
        SI.NewSize := OutSize;
        SI.Resource := 0;
        SI.Option := 0;
        SetBits(SI.Option, (Input + Pos + 5)^, 4, 8);
        SI.Status := TStreamStatus.None;
        Funcs^.LogScan1(LzipName, SI.Position, SI.OldSize, SI.NewSize);
        Add(Instance, @SI, nil, nil);
        Inc(Pos, InSize);
        continue;
      end
      else
        Output(Instance, nil, 0);
    Inc(Pos);
  end;
end;

function LzipScan2(Instance, Depth: Integer; Input: Pointer; Size: NativeInt;
  StreamInfo: PStrInfo2; Offset: PInteger; Output: _PrecompOutput;
  Funcs: PPrecompFuncs): Boolean;
var
  InSize, OutSize: Int64;
begin
  Result := DecodeMember(Instance, Input, StreamInfo^.OldSize, Output, InSize,
    OutSize) and (InSize = StreamInfo^.OldSize) and
    (OutSize = StreamInfo^.NewSize);
  if Result then
    Funcs^.LogScan2(LzipName, StreamInfo^.OldSize, StreamInfo^.NewSize);
end;

function EncodeLevel(Input: Pointer; Size, K, Dict: Integer; Buffer: PByte;
  Cap: Integer): Integer;
begin
  // lzip -0: lzlib picks its fast encoder for exactly these two values
  if (K = 0) and (Dict = 1 shl 16) then
    Dict := 65535;
  Result := LZEncode(Input, Size, Dict, MatchLens[K], Buffer, Cap);
end;

function LzipProcess(Instance, Depth: Integer; OldInput, NewInput: Pointer;
  StreamInfo: PStrInfo2; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  Cap, Dict, I, J, Res: Integer;
  Tried: array [0 .. High(MatchLens)] of Boolean;

  function TryLevel(K: Integer): Boolean;
  begin
    Tried[K] := True;
    Res := EncodeLevel(NewInput, StreamInfo^.NewSize, K, Dict, Buffer, Cap);
    Result := (Res = StreamInfo^.OldSize) and
      CompareMem(OldInput, Buffer, Res);
    Funcs^.LogProcess(LzipName, PChar('l' + MatchLens[K].ToString + IfThen(K = 0,
      'f', '')), StreamInfo^.OldSize, StreamInfo^.NewSize, Res, Result);
  end;

begin
  Result := False;
  if not LZlibDLL.DLLLoaded then
    exit;
  Dict := DictFromByte(GetBits(StreamInfo^.Option, 4, 8));
  if Dict = 0 then
    exit;
  Cap := StreamInfo^.OldSize + 1;
  Buffer := Funcs^.Allocator(Instance, Cap);
  FillChar(Tried, SizeOf(Tried), 0);
  I := -1;
  // the level whose dictionary this is, first: lzip writes it unchanged
  for J := Low(LevelDicts) to High(LevelDicts) do
    if LevelDicts[J] = Dict then
    begin
      if TryLevel(J) then
        I := J;
      break;
    end;
  if I < 0 then
  begin
    SOList[Instance].Index := 0;
    while SOList[Instance].Get(J) >= 0 do
      if not Tried[J] and TryLevel(J) then
      begin
        I := J;
        break;
      end;
  end;
  if I >= 0 then
  begin
    SetBits(StreamInfo^.Option, I, 0, 4);
    SOList[Instance].Add(I);
    Result := True;
  end;
end;

function LzipRestore(Instance, Depth: Integer; Input, InputExt: Pointer;
  StreamInfo: _StrInfo3; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  Buffer: PByte;
  K, Dict, Res: Integer;
begin
  Result := False;
  if not LZlibDLL.DLLLoaded then
    exit;
  K := GetBits(StreamInfo.Option, 0, 4);
  Dict := DictFromByte(GetBits(StreamInfo.Option, 4, 8));
  if (Dict = 0) or not InRange(K, Low(MatchLens), High(MatchLens)) then
    exit;
  Buffer := Funcs^.Allocator(Instance, StreamInfo.OldSize + 1);
  Res := EncodeLevel(Input, StreamInfo.NewSize, K, Dict, Buffer,
    StreamInfo.OldSize + 1);
  Result := Res = StreamInfo.OldSize;
  if Result then
    Output(Instance, Buffer, Res);
  Funcs^.LogRestore(LzipName, PChar('l' + MatchLens[K].ToString),
    StreamInfo.OldSize, StreamInfo.NewSize, Res, Result);
end;

initialization

Codec.Names := [LzipName];
Codec.Initialised := False;
Codec.Init := @LzipInit;
Codec.Free := @LzipFree;
Codec.Parse := @LzipParse;
Codec.Scan1 := @LzipScan1;
Codec.Scan2 := @LzipScan2;
Codec.Process := @LzipProcess;
Codec.Restore := @LzipRestore;
StockMethods.Add(LzipName);

end.
