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

{$IFDEF UNIX}
Init(PluginsPath + 'liblz.so');
{$ELSE}
Init(PluginsPath + 'lzlib.dll');
{$ENDIF}

finalization

Lib.Free;

end.
