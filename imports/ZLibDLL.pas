unit ZLibDLL;

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, Types, IOUtils, ctypes;
  // FPC's ZLib unit is not used: it is a binding to the system libz
  // (libz.so.1 / zlib1.dll, loaded at start-up). zlib is built in.

const
  Z_NO_FLUSH = 0;
  Z_PARTIAL_FLUSH = 1;
  Z_SYNC_FLUSH = 2;
  Z_FULL_FLUSH = 3;
  Z_FINISH = 4;
  Z_BLOCK = 5;
  Z_TREES = 6;

  Z_OK = 0;
  Z_STREAM_END = 1;
  Z_NEED_DICT = 2;
  Z_ERRNO = (-1);
  Z_STREAM_ERROR = (-2);
  Z_DATA_ERROR = (-3);
  Z_MEM_ERROR = (-4);
  Z_BUF_ERROR = (-5);
  Z_VERSION_ERROR = (-6);

  Z_FILTERED = 1;
  Z_HUFFMAN_ONLY = 2;
  Z_RLE = 3;
  Z_FIXED = 4;
  Z_DEFAULT_STRATEGY = 0;

  Z_DEFLATED = 8;

  _z_errmsg: array [0 .. 9] of PAnsiChar = ('need dictionary', 'stream end', '',
    'file error', 'stream error', 'data error', 'insufficient memory',
    'buffer error', 'incompatible version', '');

type
  alloc_func = function(opaque: Pointer; Items, Size: cardinal): Pointer; cdecl;
  free_func = procedure(opaque, address: Pointer); cdecl;

  internal_state = record
  end;

  Pinternal_state = ^internal_state;

  // zlib.h's z_stream; uLong is 64-bit on Linux x64 and 32-bit on Windows,
  // which ctypes' culong follows
  z_stream = record
    next_in: PByte;
    avail_in: cuint;
    total_in: culong;
    next_out: PByte;
    avail_out: cuint;
    total_out: culong;
    msg: PAnsiChar;
    state: Pinternal_state;
    zalloc: alloc_func;
    zfree: free_func;
    opaque: Pointer;
    data_type: cint;
    adler: culong;
    reserved: culong;
  end;
  z_streamp = ^z_stream;

  EZLibError = class(Exception);
  EZCompressionError = class(EZLibError);
  EZDecompressionError = class(EZLibError);

var
  _zlibVersion: function: PAnsiChar; stdcall;
  _zlibCompileFlags: function: LongWord; stdcall;

  s_deflateInit2_: function(var strm: z_stream;
    level, method, windowBits, memLevel, strategy: integer; version: PAnsiChar;
    stream_size: integer): integer stdcall;
  s_deflate: function(var strm: z_stream; flush: integer): integer stdcall;
  s_deflateEnd: function(var strm: z_stream): integer stdcall;
  s_deflateReset: function(var strm: z_stream): integer stdcall;

  c_deflateInit2_: function(var strm: z_stream;
    level, method, windowBits, memLevel, strategy: integer; version: PAnsiChar;
    stream_size: integer): integer cdecl;
  c_deflate: function(var strm: z_stream; flush: integer): integer cdecl;
  c_deflateEnd: function(var strm: z_stream): integer cdecl;
  c_deflateReset: function(var strm: z_stream): integer cdecl;

  DLLLoaded: boolean = False;

function deflateInit2(var strm: z_stream; level, method, windowBits, memLevel,
  strategy: integer): integer;
function deflate(var strm: z_stream; flush: integer): integer;
function deflateEnd(var strm: z_stream): integer;
function deflateReset(var strm: z_stream): integer;
function inflateInit2(var strm: z_stream; windowBits: integer): integer;
function inflate(var strm: z_stream; flush: integer): integer;
function inflateEnd(var strm: z_stream): integer;
function inflateReset(var strm: z_stream): integer;

implementation

// 0.9.9f: zlib built in (contrib/build-native-linux.sh -> StaticLibs/), the
// default; a library is used only when asked for with -zlib<path>. Linux used
// the system's libz.so.1, whose deflate another distro build (zlib-ng in
// compatibility mode) could change. docs/ROADMAP-1.0.0.md point 3.
{$DEFINE ZLIB_BUILTIN}
{$IFDEF LINUX}
{$IFDEF CPUX86_64}
{$L zlibstatic.linux.x64.o}
{$ENDIF}
{$IFDEF CPUI386}
{$L zlibstatic.linux.x86.o}
{$ENDIF}
{$ENDIF}
{$IFDEF WIN64}
{$L zlib_deflate.win64.x64.o}
{$L zlib_trees.win64.x64.o}
{$L zlib_adler32.win64.x64.o}
{$L zlib_crc32.win64.x64.o}
{$L zlib_zutil.win64.x64.o}
{$L zlib_inflate.win64.x64.o}
{$L zlib_inftrees.win64.x64.o}
{$L zlib_inffast.win64.x64.o}
{$ENDIF}
{$IFDEF WIN32}
{$L zlib_deflate.win32.x86.o}
{$L zlib_trees.win32.x86.o}
{$L zlib_adler32.win32.x86.o}
{$L zlib_crc32.win32.x86.o}
{$L zlib_zutil.win32.x86.o}
{$L zlib_inflate.win32.x86.o}
{$L zlib_inftrees.win32.x86.o}
{$L zlib_inffast.win32.x86.o}
{$ENDIF}

{$IFDEF ZLIB_BUILTIN}
function b_zlibVersion: PAnsiChar; cdecl; external name 'z_zlibVersion';
function b_deflateInit2_(var strm: z_stream; level, method, windowBits,
  memLevel, strategy: integer; version: PAnsiChar; stream_size: integer)
  : integer; cdecl; external name 'z_deflateInit2_';
function b_deflate(var strm: z_stream; flush: integer): integer; cdecl;
  external name 'z_deflate';
function b_deflateEnd(var strm: z_stream): integer; cdecl;
  external name 'z_deflateEnd';
function b_deflateReset(var strm: z_stream): integer; cdecl;
  external name 'z_deflateReset';
function b_inflateInit2_(var strm: z_stream; windowBits: integer;
  version: PAnsiChar; stream_size: integer): integer; cdecl;
  external name 'z_inflateInit2_';
function b_inflate(var strm: z_stream; flush: integer): integer; cdecl;
  external name 'z_inflate';
function b_inflateEnd(var strm: z_stream): integer; cdecl;
  external name 'z_inflateEnd';
function b_inflateReset(var strm: z_stream): integer; cdecl;
  external name 'z_inflateReset';
{$ENDIF}

var
  WinAPIDLL: boolean;

function deflateInit2(var strm: z_stream; level, method, windowBits, memLevel,
  strategy: integer): integer;
begin
  if WinAPIDLL then
    Result := s_deflateInit2_(strm, level, method, windowBits, memLevel,
      strategy, _zlibVersion, SizeOf(z_stream))
  else
    Result := c_deflateInit2_(strm, level, method, windowBits, memLevel,
      strategy, _zlibVersion, SizeOf(z_stream));
end;

function deflate(var strm: z_stream; flush: integer): integer;
begin
  if WinAPIDLL then
    Result := s_deflate(strm, flush)
  else
    Result := c_deflate(strm, flush);
end;

function deflateEnd(var strm: z_stream): integer;
begin
  if WinAPIDLL then
    Result := s_deflateEnd(strm)
  else
    Result := c_deflateEnd(strm);
end;

function deflateReset(var strm: z_stream): integer;
begin
  if WinAPIDLL then
    Result := s_deflateReset(strm)
  else
    Result := c_deflateReset(strm);
end;

{$IFDEF ZLIB_BUILTIN}
function inflateInit2(var strm: z_stream; windowBits: integer): integer;
begin
  Result := b_inflateInit2_(strm, windowBits, b_zlibVersion, SizeOf(z_stream));
end;

function inflate(var strm: z_stream; flush: integer): integer;
begin
  Result := b_inflate(strm, flush);
end;

function inflateEnd(var strm: z_stream): integer;
begin
  Result := b_inflateEnd(strm);
end;

function inflateReset(var strm: z_stream): integer;
begin
  Result := b_inflateReset(strm);
end;
{$ENDIF}

var
  Lib: TLibImport;

procedure Init(Filename: String; Explicit: Boolean);
begin
  Lib := TLibImport.Create;
{$IFDEF ZLIB_BUILTIN}
  if not Explicit then
  begin
    WinAPIDLL := False;
    @_zlibVersion := @b_zlibVersion;
    @c_deflateInit2_ := @b_deflateInit2_;
    @c_deflate := @b_deflate;
    @c_deflateEnd := @b_deflateEnd;
    @c_deflateReset := @b_deflateReset;
    DLLLoaded := True;
    exit;
  end;
{$ENDIF}
  Lib.LoadLib(ExpandPath(Filename, True));
  if not(Lib.Loaded and Assigned(Lib.GetProcAddr('zlibVersion'))) then
    Lib.LoadLib(ExpandPath(PluginsPath + 'zlib1.dll', True));
{$IFDEF UNIX}
  if not(Lib.Loaded and Assigned(Lib.GetProcAddr('zlibVersion'))) then
    Lib.LoadLib('libz.so.1');
{$ENDIF}
  if Lib.Loaded and Assigned(Lib.GetProcAddr('zlibVersion')) then
  begin
    DLLLoaded := True;
    @_zlibVersion := Lib.GetProcAddr('zlibVersion');
    @_zlibCompileFlags := Lib.GetProcAddr('zlibCompileFlags');
    DLLLoaded := Assigned(_zlibVersion) and Assigned(_zlibCompileFlags);
    if DLLLoaded then
    begin
      WinAPIDLL := _zlibCompileFlags and $400 = $400;
      if WinAPIDLL then
      begin
        @s_deflateInit2_ := Lib.GetProcAddr('deflateInit2_');
        @s_deflate := Lib.GetProcAddr('deflate');
        @s_deflateEnd := Lib.GetProcAddr('deflateEnd');
        @s_deflateReset := Lib.GetProcAddr('deflateReset');
      end
      else
      begin
        @c_deflateInit2_ := Lib.GetProcAddr('deflateInit2_');
        @c_deflate := Lib.GetProcAddr('deflate');
        @c_deflateEnd := Lib.GetProcAddr('deflateEnd');
        @c_deflateReset := Lib.GetProcAddr('deflateReset');
      end;
    end;
  end;
end;

procedure Deinit;
begin
  Lib.Free;
end;

const
  DLLParam = '-zlib';

var
  I: integer;
  DLLFile: String;
  Explicit: Boolean;

initialization

DLLFile := PluginsPath + 'zlibwapi.dll';
Explicit := False;
for I := 1 to ParamCount do
begin
  if ParamStr(I).StartsWith(DLLParam) then
  begin
    DLLFile := ParamStr(I).Substring(DLLParam.Length);
    Explicit := True;
    break;
  end;
end;

Init(DLLFile, Explicit);

finalization

Deinit;

end.
