unit PackPNGDLL;

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Math, SysUtils, Classes;

const
  PACKPNG_TCIP = 0; // preflate + WebP-lossless (default, best ratio, fast decode)
  PACKPNG_TVCP = 1; // kanzi BWT + zstd (fastest, weaker ratio)
  PACKPNG_TMCP = 2; // preflate + kanzi-TPAQX (archival, slow)
  PACKPNG_TPCL = 3; // preflate + multi-threaded LZMA2 (precomp-style)

var
  packpng_compress_mem: function(in_buf: PByte; in_len: NativeUInt;
    name_hint: PAnsiChar; out_buf: PPByte; out_len: PNativeUInt;
    backend: Integer): Integer cdecl;
  packpng_decompress_mem: function(in_buf: PByte; in_len: NativeUInt;
    out_buf: PPByte; out_len: PNativeUInt): Integer cdecl;
  packpng_free: procedure(p: PByte)cdecl;
  packpng_set_threads: procedure(n: Integer)cdecl;
  packpng_last_error: function: PAnsiChar cdecl;
  packpng_version: function: PAnsiChar cdecl;

  DLLLoaded: Boolean = False;

implementation

var
  Lib: TLibImport;

procedure Init;
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(PluginsPath + 'packpng.dll', True));
{$IFDEF UNIX}
  if not Lib.Loaded then
    Lib.LoadLib(ExpandPath(PluginsPath + 'libpackpng.so', True));
{$ENDIF}
  if Lib.Loaded then
  begin
    @packpng_compress_mem := Lib.GetProcAddr('packpng_compress_mem');
    @packpng_decompress_mem := Lib.GetProcAddr('packpng_decompress_mem');
    @packpng_free := Lib.GetProcAddr('packpng_free');
    @packpng_set_threads := Lib.GetProcAddr('packpng_set_threads');
    @packpng_last_error := Lib.GetProcAddr('packpng_last_error');
    @packpng_version := Lib.GetProcAddr('packpng_version');
    DLLLoaded := Assigned(packpng_compress_mem) and
      Assigned(packpng_decompress_mem) and Assigned(packpng_free);
    // packpng usa WebP-lossless/kanzi/LZMA2 internamente (punto flotante); mismo
    // gotcha que packjpg/packmp3: FPC desenmascara excepciones FPU por defecto.
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
