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

// 0.9.9f: libdeflate 1.26 built in (contrib/build-native-*.sh -> StaticLibs/), from
// the same pinned sources as the library that was shipped next to ytool.
// Untyped externals: only their addresses are taken.
{$IFDEF LINUX}
{$IFDEF CPUX86_64}
{$L libdeflate_utils.linux.x64.o}
{$L libdeflate_deflate_compress.linux.x64.o}
{$ENDIF}
{$IFDEF CPUI386}
{$L libdeflate_utils.linux.x86.o}
{$L libdeflate_deflate_compress.linux.x86.o}
{$ENDIF}
{$ENDIF}
{$IFDEF WIN64}
{$L libdeflate_utils.win64.x64.o}
{$L libdeflate_deflate_compress.win64.x64.o}
{$ENDIF}
{$IFDEF WIN32}
{$L libdeflate_utils.win32.x86.o}
{$L libdeflate_deflate_compress.win32.x86.o}
{$ENDIF}
procedure b_libdeflate_alloc_compressor; cdecl; external name 'libdeflate_alloc_compressor';
procedure b_libdeflate_deflate_compress; cdecl; external name 'libdeflate_deflate_compress';
procedure b_libdeflate_deflate_compress_bound; cdecl; external name 'libdeflate_deflate_compress_bound';
procedure b_libdeflate_free_compressor; cdecl; external name 'libdeflate_free_compressor';

procedure InitBuiltin;
begin
  @libdeflate_alloc_compressor := @b_libdeflate_alloc_compressor;
  @libdeflate_deflate_compress := @b_libdeflate_deflate_compress;
  @libdeflate_deflate_compress_bound := @b_libdeflate_deflate_compress_bound;
  @libdeflate_free_compressor := @b_libdeflate_free_compressor;
  DLLLoaded := True;
end;

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

InitBuiltin;

finalization

Lib.Free;

end.
