unit PrecompReserved;

// A codec module that does nothing, holding the place of one that was
// removed. The module's position in the Codecs array is stored in every
// stream header (TStreamHeader.Codec), so taking a module out would renumber
// every module after it. This one takes its place instead: no names, so no
// -m method reaches it, and Init returns False, so nothing scans with it.
//
// Holds the place of: packpng (removed in 0.9.9a; PPA, packPNG's successor,
// is not stable yet).

interface

uses
  PrecompUtils;

var
  Codec: TPrecompressor;

implementation

function ReservedInit(Command: PChar; Count: Integer;
  Funcs: PPrecompFuncs): Boolean;
begin
  Result := False;
end;

procedure ReservedFree(Funcs: PPrecompFuncs);
begin
end;

function ReservedParse(Command: PChar; Option: PInteger;
  Funcs: PPrecompFuncs): Boolean;
begin
  Result := False;
end;

procedure ReservedScan1(Instance, Depth: Integer; Input: PByte;
  Size, SizeEx: NativeInt; Output: _PrecompOutput; Add: _PrecompAdd;
  Funcs: PPrecompFuncs);
begin
end;

function ReservedScan2(Instance, Depth: Integer; Input: Pointer; Size: NativeInt;
  StreamInfo: PStrInfo2; Offset: PInteger; Output: _PrecompOutput;
  Funcs: PPrecompFuncs): Boolean;
begin
  Result := False;
end;

function ReservedProcess(Instance, Depth: Integer; OldInput, NewInput: Pointer;
  StreamInfo: PStrInfo2; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
begin
  Result := False;
end;

function ReservedRestore(Instance, Depth: Integer; Input, InputExt: Pointer;
  StreamInfo: _StrInfo3; Output: _PrecompOutput; Funcs: PPrecompFuncs): Boolean;
begin
  Result := False;
end;

initialization

Codec.Names := [];
Codec.Initialised := False;
Codec.Init := @ReservedInit;
Codec.Free := @ReservedFree;
Codec.Parse := @ReservedParse;
Codec.Scan1 := @ReservedScan1;
Codec.Scan2 := @ReservedScan2;
Codec.Process := @ReservedProcess;
Codec.Restore := @ReservedRestore;

end.
