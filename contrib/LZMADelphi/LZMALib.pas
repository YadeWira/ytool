unit LZMALib;

{ Minimal binding to the public-domain LZMA SDK's LzmaLib.h buffer API
  (Igor Pavlov), statically linked (same pattern as LZ4Delphi/ZSTD4Delphi).
  LzmaCompressEx/LzmaDecodeToEndMark are ytool's own thin wrappers added in
  lzmadelphi.c (LzmaLib.h's own LzmaCompress/LzmaUncompress can't control
  the end-of-stream marker, needed for the "unknown size" stream variant --
  see the comments in lzmadelphi.c). Everything else the SDK builds
  (LzmaEnc/LzmaDec internals) stays unused but linked in, same as the
  zstd/lz4 amalgamations. }

interface

const
  LZMA_PROPS_SIZE = 5;
  SZ_OK = 0;
  SZ_ERROR_DATA = 1;
  SZ_ERROR_MEM = 2;
  SZ_ERROR_UNSUPPORTED = 4;
  SZ_ERROR_PARAM = 5;
  SZ_ERROR_INPUT_EOF = 6;
  SZ_ERROR_OUTPUT_EOF = 7;

function LzmaCompressEx(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: NativeUInt; OutProps: PByte; OutPropsSize: PNativeUInt;
  Level: Integer; DictSize: Cardinal; Lc, Lp, Pb, Fb: Integer;
  NumThreads: Integer; WriteEndMark: Integer): Integer;
function LzmaUncompress(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: PNativeUInt; Props: PByte; PropsSize: NativeUInt): Integer;
{ Requires the stream's real end-of-data marker (unlike LzmaUncompress, which
  stops at DestLen regardless); needed to detect raw LZMA streams that don't
  record their uncompressed size in the header, e.g. what the "xz
  --format=lzma" CLI produces. }
function LzmaDecodeToEndMark(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: PNativeUInt; Props: PByte; PropsSize: NativeUInt): Integer;

implementation

{ Only 32-bit Windows needs explicit calling-convention keywords here: on
  Win64/Linux there's a single ABI regardless of what's declared (already
  proven working), but on Win32 the C side genuinely differs -- LzmaUncompress
  uses LzmaLib.h's MY_STDAPI (__stdcall under _WIN32, giving it "@N"
  name-decoration the linker must match), while LzmaCompressEx/
  LzmaDecodeToEndMark are ytool's own plain "int" functions (cdecl, no
  decoration). Getting this wrong wouldn't just fail to link on Win32 --
  a stdcall/cdecl mismatch corrupts the stack at runtime. }
function LzmaCompressEx(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: NativeUInt; OutProps: PByte; OutPropsSize: PNativeUInt;
  Level: Integer; DictSize: Cardinal; Lc, Lp, Pb, Fb: Integer;
  NumThreads: Integer; WriteEndMark: Integer): Integer;
  {$IFDEF WIN32}cdecl;{$ENDIF} external;

function LzmaUncompress(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: PNativeUInt; Props: PByte; PropsSize: NativeUInt): Integer;
  // FPC does NOT auto-decorate stdcall externals with a leading underscore
  // or the "@N" byte-count suffix the way it does for cdecl (verified: a
  // bare `stdcall; external;` here links against the literal, undecorated
  // Pascal name and fails) -- name it explicitly to match what the object
  // actually exports (6 params x 4 bytes = 24).
  {$IFDEF WIN32}stdcall; external name '_LzmaUncompress@24';{$ELSE}external;{$ENDIF}

function LzmaDecodeToEndMark(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: PNativeUInt; Props: PByte; PropsSize: NativeUInt): Integer;
  {$IFDEF WIN32}cdecl;{$ENDIF} external;

{$IFDEF WIN32}
{$L lzmadelphi.win32.x86.o}
{$ENDIF}
{$IFDEF WIN64}
{$L lzmadelphi.win64.x64.o}
{$ENDIF}
{$IFDEF LINUX}
{$IFDEF CPUX86_64}
{$linklib c}
{$L lzmadelphi.linux.x64.o}
{$ENDIF}
{$ENDIF}

end.
