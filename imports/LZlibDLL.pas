unit LZlibDLL;

// lzlib (nongnu.org/lzip/lzlib.html, 2-clause BSD), the lzip compression
// library, for -mlzip. Only the build shipped next to ytool is loaded (pinned
// in contrib/pin-repo.sh): lzlib 1.16 rebuilds byte for byte the members lzip
// 1.22, 1.24 and 1.26 write at every level (measured), and a .ytp restores
// only with the encoder that matched.

interface

uses
  InitCode,
  Utils, LibImport,
  SysUtils;

var
  LZ_compress_open: function(dictionary_size, match_len_limit: Integer;
    member_size: UInt64): Pointer cdecl;
  LZ_compress_close: function(encoder: Pointer): Integer cdecl;
  LZ_compress_finish: function(encoder: Pointer): Integer cdecl;
  LZ_compress_read: function(encoder: Pointer; buffer: Pointer;
    size: Integer): Integer cdecl;
  LZ_compress_write: function(encoder: Pointer; const buffer: Pointer;
    size: Integer): Integer cdecl;
  LZ_compress_finished: function(encoder: Pointer): Integer cdecl;

  LZ_decompress_open: function: Pointer cdecl;
  LZ_decompress_close: function(decoder: Pointer): Integer cdecl;
  LZ_decompress_finish: function(decoder: Pointer): Integer cdecl;
  LZ_decompress_read: function(decoder: Pointer; buffer: Pointer;
    size: Integer): Integer cdecl;
  LZ_decompress_write: function(decoder: Pointer; const buffer: Pointer;
    size: Integer): Integer cdecl;
  LZ_decompress_member_finished: function(decoder: Pointer): Integer cdecl;
  LZ_decompress_total_in_size: function(decoder: Pointer): UInt64 cdecl;
  LZ_decompress_total_out_size: function(decoder: Pointer): UInt64 cdecl;

  DLLLoaded: Boolean = False;

implementation

var
  Lib: TLibImport;

// 0.9.9f: lzlib 1.16 built in (contrib/build-native-*.sh -> StaticLibs/), from
// the same pinned sources as the library that was shipped next to ytool.
// Untyped externals: only their addresses are taken.
{$IFDEF LINUX}
{$IFDEF CPUX86_64}
{$L lzlib.linux.x64.o}
{$ENDIF}
{$IFDEF CPUI386}
{$L lzlib.linux.x86.o}
{$ENDIF}
{$ENDIF}
{$IFDEF WIN64}
{$L lzlib.win64.x64.o}
{$ENDIF}
{$IFDEF WIN32}
{$L lzlib.win32.x86.o}
{$ENDIF}
procedure b_LZ_compress_open; cdecl; external name 'LZ_compress_open';
procedure b_LZ_compress_close; cdecl; external name 'LZ_compress_close';
procedure b_LZ_compress_finish; cdecl; external name 'LZ_compress_finish';
procedure b_LZ_compress_read; cdecl; external name 'LZ_compress_read';
procedure b_LZ_compress_write; cdecl; external name 'LZ_compress_write';
procedure b_LZ_compress_finished; cdecl; external name 'LZ_compress_finished';
procedure b_LZ_decompress_open; cdecl; external name 'LZ_decompress_open';
procedure b_LZ_decompress_close; cdecl; external name 'LZ_decompress_close';
procedure b_LZ_decompress_finish; cdecl; external name 'LZ_decompress_finish';
procedure b_LZ_decompress_read; cdecl; external name 'LZ_decompress_read';
procedure b_LZ_decompress_write; cdecl; external name 'LZ_decompress_write';
procedure b_LZ_decompress_member_finished; cdecl; external name 'LZ_decompress_member_finished';
procedure b_LZ_decompress_total_in_size; cdecl; external name 'LZ_decompress_total_in_size';
procedure b_LZ_decompress_total_out_size; cdecl; external name 'LZ_decompress_total_out_size';

procedure InitBuiltin;
begin
  @LZ_compress_open := @b_LZ_compress_open;
  @LZ_compress_close := @b_LZ_compress_close;
  @LZ_compress_finish := @b_LZ_compress_finish;
  @LZ_compress_read := @b_LZ_compress_read;
  @LZ_compress_write := @b_LZ_compress_write;
  @LZ_compress_finished := @b_LZ_compress_finished;
  @LZ_decompress_open := @b_LZ_decompress_open;
  @LZ_decompress_close := @b_LZ_decompress_close;
  @LZ_decompress_finish := @b_LZ_decompress_finish;
  @LZ_decompress_read := @b_LZ_decompress_read;
  @LZ_decompress_write := @b_LZ_decompress_write;
  @LZ_decompress_member_finished := @b_LZ_decompress_member_finished;
  @LZ_decompress_total_in_size := @b_LZ_decompress_total_in_size;
  @LZ_decompress_total_out_size := @b_LZ_decompress_total_out_size;
  DLLLoaded := True;
end;

procedure Init(const Filename: String);
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(Filename, True));
  if not Lib.Loaded then
    exit;
  @LZ_compress_open := Lib.GetProcAddr('LZ_compress_open');
  @LZ_compress_close := Lib.GetProcAddr('LZ_compress_close');
  @LZ_compress_finish := Lib.GetProcAddr('LZ_compress_finish');
  @LZ_compress_read := Lib.GetProcAddr('LZ_compress_read');
  @LZ_compress_write := Lib.GetProcAddr('LZ_compress_write');
  @LZ_compress_finished := Lib.GetProcAddr('LZ_compress_finished');
  @LZ_decompress_open := Lib.GetProcAddr('LZ_decompress_open');
  @LZ_decompress_close := Lib.GetProcAddr('LZ_decompress_close');
  @LZ_decompress_finish := Lib.GetProcAddr('LZ_decompress_finish');
  @LZ_decompress_read := Lib.GetProcAddr('LZ_decompress_read');
  @LZ_decompress_write := Lib.GetProcAddr('LZ_decompress_write');
  @LZ_decompress_member_finished :=
    Lib.GetProcAddr('LZ_decompress_member_finished');
  @LZ_decompress_total_in_size := Lib.GetProcAddr('LZ_decompress_total_in_size');
  @LZ_decompress_total_out_size :=
    Lib.GetProcAddr('LZ_decompress_total_out_size');
  DLLLoaded := Assigned(LZ_compress_open) and Assigned(LZ_compress_close) and
    Assigned(LZ_compress_finish) and Assigned(LZ_compress_read) and
    Assigned(LZ_compress_write) and Assigned(LZ_compress_finished) and
    Assigned(LZ_decompress_open) and Assigned(LZ_decompress_close) and
    Assigned(LZ_decompress_finish) and Assigned(LZ_decompress_read) and
    Assigned(LZ_decompress_write) and Assigned(LZ_decompress_member_finished)
    and Assigned(LZ_decompress_total_in_size) and
    Assigned(LZ_decompress_total_out_size);
end;

initialization

InitBuiltin;

finalization

Lib.Free;

end.
