unit PJADLL;

// PJA (github.com/YadeWira/PJA, MIT): lossless recompression of JPEG,
// JPEG-LS and JPEG 2000, the successor of packJPG, which it replaces here
// since 0.9.9a. libpja's C interface (pja.h) is stable since PJA 0.9.0, every
// function may be called from several threads at once, and errors come back
// as return codes, never as exceptions or signals. pja_compress verifies its
// own output before returning it, and pja_decompress checks the size and the
// BLAKE3 hash stored in the .pja.

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Math, SysUtils, Classes;

const
  PJA_OK = 0;
  PJA_E_NOT_TAKEN = 1;
  PJA_E_DATA = 2;
  PJA_E_MEMORY = 3;
  PJA_E_VERSION = 7;

var
  pja_version: function: PAnsiChar cdecl;
  pja_compress: function(input: Pointer; in_size: NativeUInt;
    output: PPointer; out_size: PNativeUInt; threads: Integer): Integer cdecl;
  pja_decompress: function(input: Pointer; in_size: NativeUInt;
    output: PPointer; out_size: PNativeUInt; max_size: NativeUInt;
    threads: Integer): Integer cdecl;
  pja_free: procedure(p: Pointer)cdecl;

  DLLLoaded: Boolean = False;

implementation

var
  Lib: TLibImport;

procedure Init;
begin
  Lib := TLibImport.Create;
  // PJA's release names the library pja.dll / pja.so; the Linux package
  // ships it as libpja.so, like the other plugins.
  Lib.LoadLib(ExpandPath(PluginsPath + 'pja.dll', True));
{$IFDEF UNIX}
  if not Lib.Loaded then
    Lib.LoadLib(ExpandPath(PluginsPath + 'libpja.so', True));
  if not Lib.Loaded then
    Lib.LoadLib(ExpandPath(PluginsPath + 'pja.so', True));
{$ENDIF}
  if Lib.Loaded then
  begin
    @pja_version := Lib.GetProcAddr('pja_version');
    @pja_compress := Lib.GetProcAddr('pja_compress');
    @pja_decompress := Lib.GetProcAddr('pja_decompress');
    @pja_free := Lib.GetProcAddr('pja_free');
    DLLLoaded := Assigned(pja_compress) and Assigned(pja_decompress) and
      Assigned(pja_free);
    // Same reason as packJPG/packMP3: FPC unmasks FPU exceptions, and the
    // library's C core assumes C's masked default.
    if DLLLoaded then
      SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
        exUnderflow, exPrecision]);
  end;
end;

procedure Deinit;
begin
  Lib.Free;
end;

initialization

Init;

finalization

Deinit;

end.
