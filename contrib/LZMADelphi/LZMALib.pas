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

function LzmaCompressEx(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: NativeUInt; OutProps: PByte; OutPropsSize: PNativeUInt;
  Level: Integer; DictSize: Cardinal; Lc, Lp, Pb, Fb: Integer;
  NumThreads: Integer; WriteEndMark: Integer): Integer; external;

function LzmaUncompress(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: PNativeUInt; Props: PByte; PropsSize: NativeUInt): Integer;
  external;

function LzmaDecodeToEndMark(Dest: PByte; DestLen: PNativeUInt; Src: PByte;
  SrcLen: PNativeUInt; Props: PByte; PropsSize: NativeUInt): Integer;
  external;

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
