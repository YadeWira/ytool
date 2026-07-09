unit PrecompPackPNG;

{$POINTERMATH ON}

interface

uses
  PackPNGDLL,
  Utils,
  PrecompUtils,
  SysUtils, Classes, Math;

var
  Codec: TPrecompressor;

implementation

const
  PackPNGName: PChar = 'packpng';
  PNG_SIG: Int64 = $A1A0A0D474E5089;
  JNG_SIG: Int64 = $A1A0A0D474E4A8B;
  MNG_SIG: Int64 = $A1A0A0D474E4D8A;
  IEND_TYPE = $444E4549; // 'IEND', same little-endian convention as PrecompZLib.PNG_END
  MEND_TYPE = $444E454D; // 'MEND', MNG's real terminator (not IEND)

type
  PChunkHdr = ^TChunkHdr;

  TChunkHdr = packed record
    Size, Header: Integer;
  end;

var
  CodecAvailable: Boolean;
  CodecEnabled: Boolean;

// Walks the [len(4)+type(4)+data+crc(4)] chunks of a PNG/JNG/MNG embedded
// in an arbitrary (larger) blob, validating each chunk's CRC (same
// technique as EncodePNG in PrecompZLib.pas) so an incidental byte pattern
// isn't mistaken for a real container. PNG/JNG terminate at IEND. MNG
// terminates at MEND -- its embedded PNG/JNG sub-images DO use IEND for
// each one, but that's an intermediate chunk of the container, not the
// end; that's why in MNG mode the walker ignores IEND entirely and only
// stops at MEND (the chunk layout is flat, with no real nesting, so there's
// no need to recurse to skip over the sub-streams).
function GetPNGFamilyInfo(Input: PByte; MaxSize: NativeInt;
  out TotalSize: Integer): Boolean;
var
  Sig: Int64;
  CurPos: NativeInt;
  Chunk: TChunkHdr;
  DataSize: Integer;
  CRC: Cardinal;
  StopType: Integer;
begin
  Result := False;
  TotalSize := 0;
  if MaxSize < 8 then
    exit;
  Sig := PInt64(Input)^;
  if Sig = MNG_SIG then
    StopType := MEND_TYPE
  else if (Sig = PNG_SIG) or (Sig = JNG_SIG) then
    StopType := IEND_TYPE
  else
    exit;
  CurPos := 8;
  while CurPos + SizeOf(TChunkHdr) <= MaxSize do
  begin
    Chunk := PChunkHdr(Input + CurPos)^;
    DataSize := EndianSwap(Chunk.Size);
    if (DataSize < 0) or
      (CurPos + SizeOf(TChunkHdr) + DataSize + Cardinal.Size > MaxSize) then
      exit;
    CRC := EndianSwap(CRC32(0, Input + CurPos + Integer.Size,
      DataSize + Integer.Size));
    if CRC <> PCardinal(Input + CurPos + SizeOf(TChunkHdr) + DataSize)^ then
      exit;
    Inc(CurPos, SizeOf(TChunkHdr) + DataSize + Cardinal.Size);
    if Chunk.Header = StopType then
    begin
      TotalSize := CurPos;
      Result := True;
      exit;
    end;
  end;
end;

function PackPNGInit(Command: PChar; Count: Integer;
  Funcs: PPrecompFuncs): Boolean;
var
  X: Integer;
  S: String;
begin
  Result := True;
  CodecAvailable := PackPNGDLL.DLLLoaded;
  CodecEnabled := False;
  X := 0;
  while Funcs^.GetCodec(Command, X, False) <> '' do
  begin
    S := Funcs^.GetCodec(Command, X, False);
    if (CompareText(S, PackPNGName) = 0) and PackPNGDLL.DLLLoaded then
      CodecEnabled := True;
    Inc(X);
  end;
end;

procedure PackPNGFree(Funcs: PPrecompFuncs);
begin
end;

function PackPNGParse(Command: PChar; Option: PInteger;
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
    if (CompareText(S, PackPNGName) = 0) and PackPNGDLL.DLLLoaded then
      Result := True;
    Inc(I);
  end;
end;

procedure PackPNGScan1(Instance, Depth: Integer; Input: PByte;
  Size, SizeEx: NativeInt; Output: _PrecompOutput; Add: _PrecompAdd;
  Funcs: PPrecompFuncs);
var
  Pos: NativeInt;
  TotalSize: Integer;
  SI: _StrInfo1;
begin
  if not CodecEnabled then
    exit;
  Pos := 0;
  while Pos < Size do
  begin
    if GetPNGFamilyInfo(Input + Pos, SizeEx - Pos, TotalSize) then
    begin
      Output(Instance, Input + Pos, TotalSize);
      SI.Position := Pos;
      SI.OldSize := TotalSize;
      SI.NewSize := TotalSize;
      SI.Option := 0;
      SI.Status := TStreamStatus.None;
      Funcs^.LogScan1(PackPNGName, SI.Position, SI.OldSize, -1);
      Add(Instance, @SI, nil, nil);
      Inc(Pos, TotalSize);
      continue;
    end;
    Inc(Pos);
  end;
end;

function PackPNGScan2(Instance, Depth: Integer; Input: Pointer; Size: NativeInt;
  StreamInfo: PStrInfo2; Offset: PInteger; Output: _PrecompOutput;
  Funcs: PPrecompFuncs): Boolean;
var
  TotalSize: Integer;
begin
  Result := False;
  if StreamInfo^.OldSize <= 0 then
    exit;
  if GetPNGFamilyInfo(Input, StreamInfo^.OldSize, TotalSize) and
    (TotalSize > 0) then
  begin
    Output(Instance, Input, TotalSize);
    StreamInfo^.NewSize := TotalSize;
    Funcs^.LogScan2(PackPNGName, StreamInfo^.OldSize, -1);
    Result := True;
  end;
end;

function PackPNGProcess(Instance, Depth: Integer; OldInput, NewInput: Pointer;
  StreamInfo: PStrInfo2; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  OutBuf: PByte;
  OutLen: NativeUInt;
  Res: Integer;
begin
  Result := False;
  if not CodecAvailable then
    exit;
  OutBuf := nil;
  OutLen := 0;
  Res := packpng_compress_mem(PByte(OldInput), StreamInfo^.OldSize, nil,
    @OutBuf, @OutLen, PACKPNG_TCIP);
  if (Res = 0) and (OutLen > 0) and (OutLen < NativeUInt(StreamInfo^.NewSize))
  then
  begin
    Move(OutBuf^, NewInput^, OutLen);
    StreamInfo^.NewSize := OutLen;
    Result := True;
  end;
  if Assigned(OutBuf) then
    packpng_free(OutBuf);
end;

function PackPNGRestore(Instance, Depth: Integer; Input, InputExt: Pointer;
  StreamInfo: _StrInfo3; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
var
  OutBuf: PByte;
  OutLen: NativeUInt;
  Res: Integer;
begin
  Result := False;
  if not CodecAvailable then
    exit;
  OutBuf := nil;
  OutLen := 0;
  Res := packpng_decompress_mem(PByte(Input), StreamInfo.NewSize, @OutBuf,
    @OutLen);
  if (Res = 0) and (OutLen = NativeUInt(StreamInfo.OldSize)) then
  begin
    Output(Instance, OutBuf, OutLen);
    Result := True;
  end;
  if Assigned(OutBuf) then
    packpng_free(OutBuf);
end;

initialization

Codec.Names := [PackPNGName];
Codec.Initialised := False;
Codec.Init := @PackPNGInit;
Codec.Free := @PackPNGFree;
Codec.Parse := @PackPNGParse;
Codec.Scan1 := @PackPNGScan1;
Codec.Scan2 := @PackPNGScan2;
Codec.Process := @PackPNGProcess;
Codec.Restore := @PackPNGRestore;

end.
