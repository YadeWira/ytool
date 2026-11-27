unit LibDeflateDLL;

// libdeflate (github.com/ebiggers/libdeflate, MIT): a deflate encoder of its
// own, levels 0-12, whose output zlib does not reproduce. -mlibdeflate rebuilds
// such streams.
//
// Only the library shipped next to ytool is loaded, never the system's:
// libdeflate's own documentation says that different versions write different
// bytes at the same level, and a .ytp restores only with the version that
// wrote it. The build is pinned in contrib/build-plugins-*.sh (v1.26), and
// writes the same bytes on x86 and x86-64.

interface

uses
  InitCode,
  Utils, LibImport,
  SysUtils;

type
  size_t = NativeUInt;

var
  libdeflate_alloc_compressor: function(compression_level: Integer)
    : Pointer cdecl;
  libdeflate_deflate_compress: function(compressor: Pointer; const inp: Pointer;
    in_nbytes: size_t; outp: Pointer; out_nbytes_avail: size_t): size_t cdecl;
  libdeflate_deflate_compress_bound: function(compressor: Pointer;
    in_nbytes: size_t): size_t cdecl;
  libdeflate_free_compressor: procedure(compressor: Pointer)cdecl;

  DLLLoaded: Boolean = False;

implementation

var
  Lib: TLibImport;

procedure Init(const Filename: String);
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(Filename, True));
  if Lib.Loaded then
  begin
    @libdeflate_alloc_compressor := Lib.GetProcAddr('libdeflate_alloc_compressor');
    @libdeflate_deflate_compress := Lib.GetProcAddr('libdeflate_deflate_compress');
    @libdeflate_deflate_compress_bound :=
      Lib.GetProcAddr('libdeflate_deflate_compress_bound');
    @libdeflate_free_compressor := Lib.GetProcAddr('libdeflate_free_compressor');
    DLLLoaded := Assigned(libdeflate_alloc_compressor) and
      Assigned(libdeflate_deflate_compress) and
      Assigned(libdeflate_deflate_compress_bound) and
      Assigned(libdeflate_free_compressor);
  end;
end;

initialization

{$IFDEF UNIX}
Init(PluginsPath + 'libdeflate.so');
{$ELSE}
Init(PluginsPath + 'libdeflate.dll');
{$ENDIF}

finalization

Lib.Free;

end.
