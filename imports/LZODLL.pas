unit LZODLL;

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils;

const
  Success = 0;
  GenericError = -1;
  OutOfMemory = -2;
  NotCompressible = -3;
  InputOverrun = -4;
  OutputOverrun = -5;
  LookbehindOverrun = -6;
  EndOfFileNotFound = -7;
  InputNotConsumed = -8;
  NotImplemented = -9;
  InvalidArgument = -10;

type
  lzo_free_func_t = procedure(self: Pointer; ptr: Pointer); cdecl;
  lzo_alloc_func_t = function(self: Pointer; items, size: LongWord)
    : Pointer; cdecl;
  lzo_progress_func_t = procedure(self: Pointer; a, b: LongWord;
    c: integer); cdecl;

  lzo_callback_t = Record
    nalloc: lzo_alloc_func_t;
    nfree: lzo_free_func_t;
    nprogress: lzo_progress_func_t;
    user1: Pointer;
    user2: LongWord;
    user3: LongWord;
  end;

var
  lzo1x_1_compress: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt; wrkmem: Pointer): integer; cdecl;
  lzo1x_1_11_compress: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt; wrkmem: Pointer): integer; cdecl;
  lzo1x_1_12_compress: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt; wrkmem: Pointer): integer; cdecl;
  lzo1x_1_15_compress: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt; wrkmem: Pointer): integer; cdecl;
  lzo1x_999_compress: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt; wrkmem: Pointer): integer; cdecl;
  lzo1x_999_compress_level: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt; wrkmem: Pointer; const dict: Pointer;
    dict_len: Cardinal; cb: Pointer; compression_level: integer)
    : integer; cdecl;
  lzo1x_decompress_safe: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt): integer cdecl;
  lzo1c_999_compress: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt; wrkmem: Pointer): integer; cdecl;
  lzo1c_decompress_safe: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt): integer cdecl;
  lzo2a_999_compress: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt; wrkmem: Pointer): integer; cdecl;
  lzo2a_decompress_safe: function(const src: Pointer; src_len: NativeUInt;
    dst: Pointer; dst_len: PNativeUInt): integer cdecl;

  DLLLoaded: Boolean = False;

implementation

var
  Lib: TLibImport;

// 0.9.9f: lzo 2.10 built in (contrib/build-native-*.sh -> StaticLibs/). Linux
// loaded the system's liblzo2.so.2; a library is used only with -lzo<path>.
// Untyped externals (cdecl for i386-win32's underscore): addresses only.
{$IFDEF LINUX}
{$IFDEF CPUX86_64}
{$L lzo_lzo1c_rr.linux.x64.o}
{$L lzo_lzo1x_1.linux.x64.o}
{$L lzo_lzo1x_1k.linux.x64.o}
{$L lzo_lzo1x_1l.linux.x64.o}
{$L lzo_lzo1x_1o.linux.x64.o}
{$L lzo_lzo1x_9x.linux.x64.o}
{$L lzo_lzo1x_d2.linux.x64.o}
{$L lzo_lzo1c_9x.linux.x64.o}
{$L lzo_lzo1c_d2.linux.x64.o}
{$L lzo_lzo2a_9x.linux.x64.o}
{$L lzo_lzo2a_d2.linux.x64.o}
{$L lzo_lzo_init.linux.x64.o}
{$L lzo_lzo_util.linux.x64.o}
{$L lzo_lzo_ptr.linux.x64.o}
{$L lzo_lzo_str.linux.x64.o}
{$L lzo_lzo_crc.linux.x64.o}
{$ENDIF}
{$IFDEF CPUI386}
{$L lzo_lzo1c_rr.linux.x86.o}
{$L lzo_lzo1x_1.linux.x86.o}
{$L lzo_lzo1x_1k.linux.x86.o}
{$L lzo_lzo1x_1l.linux.x86.o}
{$L lzo_lzo1x_1o.linux.x86.o}
{$L lzo_lzo1x_9x.linux.x86.o}
{$L lzo_lzo1x_d2.linux.x86.o}
{$L lzo_lzo1c_9x.linux.x86.o}
{$L lzo_lzo1c_d2.linux.x86.o}
{$L lzo_lzo2a_9x.linux.x86.o}
{$L lzo_lzo2a_d2.linux.x86.o}
{$L lzo_lzo_init.linux.x86.o}
{$L lzo_lzo_util.linux.x86.o}
{$L lzo_lzo_ptr.linux.x86.o}
{$L lzo_lzo_str.linux.x86.o}
{$L lzo_lzo_crc.linux.x86.o}
{$ENDIF}
{$ENDIF}
{$IFDEF WIN64}
{$L lzo_lzo1c_rr.win64.x64.o}
{$L lzo_lzo1x_1.win64.x64.o}
{$L lzo_lzo1x_1k.win64.x64.o}
{$L lzo_lzo1x_1l.win64.x64.o}
{$L lzo_lzo1x_1o.win64.x64.o}
{$L lzo_lzo1x_9x.win64.x64.o}
{$L lzo_lzo1x_d2.win64.x64.o}
{$L lzo_lzo1c_9x.win64.x64.o}
{$L lzo_lzo1c_d2.win64.x64.o}
{$L lzo_lzo2a_9x.win64.x64.o}
{$L lzo_lzo2a_d2.win64.x64.o}
{$L lzo_lzo_init.win64.x64.o}
{$L lzo_lzo_util.win64.x64.o}
{$L lzo_lzo_ptr.win64.x64.o}
{$L lzo_lzo_str.win64.x64.o}
{$L lzo_lzo_crc.win64.x64.o}
{$ENDIF}
{$IFDEF WIN32}
{$L lzo_lzo1c_rr.win32.x86.o}
{$L lzo_lzo1x_1.win32.x86.o}
{$L lzo_lzo1x_1k.win32.x86.o}
{$L lzo_lzo1x_1l.win32.x86.o}
{$L lzo_lzo1x_1o.win32.x86.o}
{$L lzo_lzo1x_9x.win32.x86.o}
{$L lzo_lzo1x_d2.win32.x86.o}
{$L lzo_lzo1c_9x.win32.x86.o}
{$L lzo_lzo1c_d2.win32.x86.o}
{$L lzo_lzo2a_9x.win32.x86.o}
{$L lzo_lzo2a_d2.win32.x86.o}
{$L lzo_lzo_init.win32.x86.o}
{$L lzo_lzo_util.win32.x86.o}
{$L lzo_lzo_ptr.win32.x86.o}
{$L lzo_lzo_str.win32.x86.o}
{$L lzo_lzo_crc.win32.x86.o}
{$ENDIF}
procedure b_lzo1c_999_compress; cdecl; external name 'lzo1c_999_compress';
procedure b_lzo1c_decompress_safe; cdecl; external name 'lzo1c_decompress_safe';
procedure b_lzo1x_1_11_compress; cdecl; external name 'lzo1x_1_11_compress';
procedure b_lzo1x_1_12_compress; cdecl; external name 'lzo1x_1_12_compress';
procedure b_lzo1x_1_15_compress; cdecl; external name 'lzo1x_1_15_compress';
procedure b_lzo1x_1_compress; cdecl; external name 'lzo1x_1_compress';
procedure b_lzo1x_999_compress; cdecl; external name 'lzo1x_999_compress';
procedure b_lzo1x_999_compress_level; cdecl; external name 'lzo1x_999_compress_level';
procedure b_lzo1x_decompress_safe; cdecl; external name 'lzo1x_decompress_safe';
procedure b_lzo2a_999_compress; cdecl; external name 'lzo2a_999_compress';
procedure b_lzo2a_decompress_safe; cdecl; external name 'lzo2a_decompress_safe';

procedure InitBuiltin;
begin
  @lzo1c_999_compress := @b_lzo1c_999_compress;
  @lzo1c_decompress_safe := @b_lzo1c_decompress_safe;
  @lzo1x_1_11_compress := @b_lzo1x_1_11_compress;
  @lzo1x_1_12_compress := @b_lzo1x_1_12_compress;
  @lzo1x_1_15_compress := @b_lzo1x_1_15_compress;
  @lzo1x_1_compress := @b_lzo1x_1_compress;
  @lzo1x_999_compress := @b_lzo1x_999_compress;
  @lzo1x_999_compress_level := @b_lzo1x_999_compress_level;
  @lzo1x_decompress_safe := @b_lzo1x_decompress_safe;
  @lzo2a_999_compress := @b_lzo2a_999_compress;
  @lzo2a_decompress_safe := @b_lzo2a_decompress_safe;
  DLLLoaded := True;
end;

procedure Init(Filename: String);
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(Filename, True));
{$IFDEF UNIX}
  if not Lib.Loaded then
    Lib.LoadLib('liblzo2.so.2');
{$ENDIF}
  if Lib.Loaded then
  begin
    @lzo1x_1_compress := Lib.GetProcAddr('lzo1x_1_compress');
    @lzo1x_1_11_compress := Lib.GetProcAddr('lzo1x_1_11_compress');
    @lzo1x_1_12_compress := Lib.GetProcAddr('lzo1x_1_12_compress');
    @lzo1x_1_15_compress := Lib.GetProcAddr('lzo1x_1_15_compress');
    @lzo1x_999_compress := Lib.GetProcAddr('lzo1x_999_compress');
    @lzo1x_999_compress_level := Lib.GetProcAddr('lzo1x_999_compress_level');
    @lzo1x_decompress_safe := Lib.GetProcAddr('lzo1x_decompress_safe');
    @lzo1c_999_compress := Lib.GetProcAddr('lzo1c_999_compress');
    @lzo1c_decompress_safe := Lib.GetProcAddr('lzo1c_decompress_safe');
    @lzo2a_999_compress := Lib.GetProcAddr('lzo2a_999_compress');
    @lzo2a_decompress_safe := Lib.GetProcAddr('lzo2a_decompress_safe');
    DLLLoaded := Assigned(lzo1x_decompress_safe);
  end;
end;

procedure Deinit;
begin
  Lib.Free;
end;

const
  DLLParam = '-lzo';

var
  I: integer;
  DLLFile: String;

initialization

DLLFile := '';
for I := 1 to ParamCount do
begin
  if ParamStr(I).StartsWith(DLLParam) then
  begin
    DLLFile := ParamStr(I).Substring(DLLParam.Length);
    break;
  end;
end;

if DLLFile <> '' then
  Init(DLLFile)
else
  InitBuiltin;

finalization

Deinit;

end.
