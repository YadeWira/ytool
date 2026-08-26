unit LZ4DLL;

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, Math;

const
  LZ4F_VERSION = 100;

type
  size_t = NativeUInt;
  PLZ4_streamDecode_t = Pointer;
  PLZ4_stream_t = Pointer;
  PLZ4_streamHC_t = Pointer;

  LZ4F_errorCode_t = type size_t;

  LZ4F_blockSizeID_t = (LZ4F_default = 0, LZ4F_max64KB = 4, LZ4F_max256KB = 5,
    LZ4F_max1MB = 6, LZ4F_max4MB = 7, LZ4F_blockSizeID_Force32 = $40000000);
  LZ4F_blockMode_t = (LZ4F_blockLinked = 0, LZ4F_blockIndependent,
    LZ4F_blockMode_Force32 = $40000000);

  LZ4F_contentChecksum_t = (LZ4F_noContentChecksum = 0,
    LZ4F_contentChecksumEnabled, LZ4F_contentChecksum_Force32 = $40000000);

  LZ4F_blockChecksum_t = (LZ4F_noBlockChecksum = 0, LZ4F_blockChecksumEnabled,
    LZ4F_blockChecksum_Force32 = $40000000);

  LZ4F_frameType_t = (LZ4F_frame = 0, LZ4F_skippableFrame,
    LZ4F_frameType_Force32 = $40000000);

  LZ4F_frameInfo_t = record
    blockSizeID: LZ4F_blockSizeID_t;
    blockMode: LZ4F_blockMode_t;
    contentChecksumFlag: LZ4F_contentChecksum_t;
    frameType: LZ4F_frameType_t;
    contentSize: UInt64;
    dictID: Cardinal;
    blockChecksumFlag: LZ4F_blockChecksum_t;
  end;

  LZ4F_preferences_t = record
    frameInfo: LZ4F_frameInfo_t;
    compressionLevel: Integer;
    autoFlush: Cardinal;
    favorDecSpeed: Cardinal;
    reserved: packed array [0 .. 2] of Cardinal;
  end;

  PLZ4F_preferences_t = ^LZ4F_preferences_t;

  LZ4F_dctx = type Pointer;

  LZ4F_decompressOptions_t = record
    stableDst: Cardinal;
    reserved: packed array [0 .. 2] of Cardinal;
  end;

  PLZ4F_decompressOptions_t = ^LZ4F_decompressOptions_t;

var
  LZ4_decompress_safe: function(source: Pointer; dest: Pointer;
    compressedSize: Integer; maxDecompressedSize: Integer): Integer cdecl;
  LZ4_decompress_fast: function(source: Pointer; dest: Pointer;
    originalSize: Integer): Integer cdecl;
  LZ4_compress_default: function(src, dst: Pointer;
    srcSize, dstCapacity: Integer): Integer cdecl;
  LZ4_compress_fast: function(src, dst: Pointer; srcSize, dstCapacity: Integer;
    acceleration: Integer): Integer cdecl;
  LZ4_compress_HC: function(const src: Pointer; dst: Pointer; srcSize: Integer;
    maxDstSize: Integer; compressionLevel: Integer): Integer cdecl;
  LZ4F_compressFrame: function(dstBuffer: Pointer; dstCapacity: size_t;
    srcBuffer: Pointer; srcSize: size_t; preferencesPtr: PLZ4F_preferences_t)
    : size_t cdecl;
  LZ4_compressHC2: function(const src: Pointer; dst: Pointer; srcSize: Integer;
    compressionLevel: Integer): Integer cdecl;
  LZ4F_compressFrameBound: function(srcSize: size_t;
    preferencesPtr: PLZ4F_preferences_t): size_t cdecl;
  LZ4F_createDecompressionContext: function(out dctxPtr: LZ4F_dctx;
    version: Cardinal = LZ4F_VERSION): LZ4F_errorCode_t cdecl;
  LZ4F_freeDecompressionContext: function(dctx: LZ4F_dctx)
    : LZ4F_errorCode_t cdecl;
  LZ4F_decompress: function(dctx: LZ4F_dctx; dstBuffer: Pointer;
    var dstSizePtr: size_t; srcBuffer: Pointer; var srcSizePtr: size_t;
    dOptPtr: PLZ4F_decompressOptions_t): size_t cdecl;
  LZ4F_getFrameInfo: function(dctx: LZ4F_dctx;
    out frameInfoPtr: LZ4F_frameInfo_t; srcBuffer: Pointer;
    out srcSizePtr: size_t): size_t cdecl;
  LZ4_createStreamDecode: function: PLZ4_streamDecode_t cdecl;
  LZ4_freeStreamDecode: function(LZ4_stream: PLZ4_streamDecode_t)
    : Integer cdecl;
  LZ4_decompress_safe_continue: function(LZ4_stream: PLZ4_streamDecode_t;
    const src: Pointer; dst: Pointer; srcSize: Integer; dstCapacity: Integer)
    : Integer cdecl;
  LZ4_createStream: function: PLZ4_stream_t cdecl;
  LZ4_freeStream: function(streamPtr: PLZ4_stream_t): Integer cdecl;
  LZ4_resetStream: procedure(streamHCPtr: PLZ4_stream_t)cdecl;
  LZ4_compress_fast_continue: function(streamPtr: PLZ4_stream_t;
    const src: Pointer; dst: Pointer; srcSize: Integer; maxDstSize: Integer;
    acceleration: Integer): Integer cdecl;
  LZ4_createStreamHC: function: PLZ4_streamHC_t cdecl;
  LZ4_freeStreamHC: function(streamHCPtr: PLZ4_streamHC_t): Integer cdecl;
  LZ4_resetStreamHC: procedure(streamHCPtr: PLZ4_streamHC_t;
    compressionLevel: Integer)cdecl;
  LZ4_compress_HC_continue: function(streamHCPtr: PLZ4_streamHC_t;
    const src: Pointer; dst: Pointer; srcSize: Integer; maxDstSize: Integer)
    : Integer cdecl;

  DLLLoaded: Boolean = False;

// frameFlags (optional) returns the parts of the frame descriptor that must be
// reproduced byte-for-byte when the frame is re-encoded, packed as:
//   bit 0 = contentChecksumFlag   bit 1 = blockChecksumFlag
//   bit 2 = contentSize present   bit 3 = blockMode
// Without these the re-encoder cannot rebuild a frame that used any of them --
// notably the content checksum, which the lz4 CLI writes by default.
function LZ4F_decompress_safe(source: Pointer; dest: Pointer;
  sourceSize: Integer; destSize: Integer; compressedSize: PInteger = nil;
  blockSize: PInteger = nil; frameFlags: PInteger = nil): Integer;

implementation

function LZ4F_decompress_safe(source: Pointer; dest: Pointer;
  sourceSize: Integer; destSize: Integer; compressedSize: PInteger;
  blockSize: PInteger; frameFlags: PInteger): Integer;
var
  ctx: LZ4F_dctx;
  fi: LZ4F_frameInfo_t;
  srcSizePtr, dstSizePtr, srcSizePtr2: size_t;
begin
  Result := 0;
  if Assigned(compressedSize) then
    compressedSize^ := 0;
  if Assigned(blockSize) then
    blockSize^ := 4;
  if Assigned(frameFlags) then
    frameFlags^ := 0;
  if NativeUInt(LZ4F_createDecompressionContext(ctx)) = 0 then
    try
      srcSizePtr := sourceSize;
      dstSizePtr := destSize;
      try
        FillChar(fi, SizeOf(LZ4F_frameInfo_t), 0);
        srcSizePtr2 := sourceSize;
        if LZ4F_decompress(ctx, dest, dstSizePtr, source, srcSizePtr, nil) = 0
        then
        begin
          LZ4F_getFrameInfo(ctx, fi, source, srcSizePtr2);
          if Assigned(compressedSize) then
            compressedSize^ := srcSizePtr;
          if Assigned(blockSize) then
            blockSize^ := Max(4, Integer(fi.blockSizeID));
          if Assigned(frameFlags) then
          begin
            frameFlags^ := 0;
            if fi.contentChecksumFlag <> LZ4F_noContentChecksum then
              frameFlags^ := frameFlags^ or 1;
            if fi.blockChecksumFlag <> LZ4F_noBlockChecksum then
              frameFlags^ := frameFlags^ or 2;
            if fi.contentSize <> 0 then
              frameFlags^ := frameFlags^ or 4;
            if fi.blockMode <> LZ4F_blockLinked then
              frameFlags^ := frameFlags^ or 8;
          end;
          Result := dstSizePtr;
        end;
      finally
        LZ4F_freeDecompressionContext(ctx);
      end;
    except
    end;
end;

var
  Lib: TLibImport;

procedure Init(Filename: String);
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(Filename, True));
{$IFDEF UNIX}
  // Ultimo recurso: el liblz4 de la distro. Se conserva para que un ytool
  // suelto (sin el liblz4.so al lado) siga funcionando, pero NO es
  // equivalente a la lib shipeada, y por eso va despues y no antes.
  //
  // Entre lz4 1.9.4 y 1.10.0 cambio LZ4HC_CLEVEL_MIN (3 -> 2), y el nivel 2
  // es el primer candidato que prueba la busqueda de nivel de PrecompLZ4.
  // Con versiones distintas de un lado y del otro, un .pmp puede no
  // restaurarse: medido, con una variante silenciosa (mismo largo, bytes
  // distintos) que pasa el chequeo de tamano de PrecompLZ4.pas:599.
  //
  // Un binario que caiga aca queda a merced de la version que tenga instalada
  // la maquina que decodifica. Ver contrib/build-plugins-linux.sh.
  if not Lib.Loaded then
    Lib.LoadLib('liblz4.so.1');
{$ENDIF}
  if Lib.Loaded then
  begin
    @LZ4_decompress_safe := Lib.GetProcAddr('LZ4_decompress_safe');
    @LZ4_decompress_fast := Lib.GetProcAddr('LZ4_decompress_fast');
    @LZ4_compress_default := Lib.GetProcAddr('LZ4_compress_default');
    @LZ4_compress_fast := Lib.GetProcAddr('LZ4_compress_fast');
    @LZ4_compress_HC := Lib.GetProcAddr('LZ4_compress_HC');
    @LZ4_compressHC2 := Lib.GetProcAddr('LZ4_compressHC2');
    @LZ4F_compressFrame := Lib.GetProcAddr('LZ4F_compressFrame');
    @LZ4F_compressFrameBound := Lib.GetProcAddr('LZ4F_compressFrameBound');
    @LZ4F_createDecompressionContext :=
      Lib.GetProcAddr('LZ4F_createDecompressionContext');
    @LZ4F_freeDecompressionContext :=
      Lib.GetProcAddr('LZ4F_freeDecompressionContext');
    @LZ4F_decompress := Lib.GetProcAddr('LZ4F_decompress');
    @LZ4F_getFrameInfo := Lib.GetProcAddr('LZ4F_getFrameInfo');
    @LZ4_createStreamDecode := Lib.GetProcAddr('LZ4_createStreamDecode');
    @LZ4_freeStreamDecode := Lib.GetProcAddr('LZ4_freeStreamDecode');
    @LZ4_decompress_safe_continue :=
      Lib.GetProcAddr('LZ4_decompress_safe_continue');
    @LZ4_createStream := Lib.GetProcAddr('LZ4_createStream');
    @LZ4_freeStream := Lib.GetProcAddr('LZ4_freeStream');
    @LZ4_resetStream := Lib.GetProcAddr('LZ4_resetStream');
    @LZ4_compress_fast_continue :=
      Lib.GetProcAddr('LZ4_compress_fast_continue');
    @LZ4_createStreamHC := Lib.GetProcAddr('LZ4_createStreamHC');
    @LZ4_freeStreamHC := Lib.GetProcAddr('LZ4_freeStreamHC');
    @LZ4_resetStreamHC := Lib.GetProcAddr('LZ4_resetStreamHC');
    @LZ4_compress_HC_continue := Lib.GetProcAddr('LZ4_compress_HC_continue');
    DLLLoaded := Assigned(LZ4_decompress_safe);
  end;
end;

procedure Deinit;
begin
  Lib.Free;
end;

const
  DLLParam = '-lz4';

var
  I: Integer;
  DLLFile: String;

initialization

{$IFDEF UNIX}
DLLFile := PluginsPath + 'liblz4.so';
{$ELSE}
DLLFile := PluginsPath + 'liblz4.dll';
{$ENDIF}
for I := 1 to ParamCount do
begin
  if ParamStr(I).StartsWith(DLLParam) then
  begin
    DLLFile := ParamStr(I).Substring(DLLParam.Length);
    break;
  end;
end;

Init(DLLFile);

finalization

Deinit;

end.
