unit ZSTDDLL;

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils;

type
  size_t = NativeUInt;
  SSIZE_T = NativeInt;
  ZSTD_strategy = (ZSTD_fast = 1, ZSTD_dfast = 2, ZSTD_greedy = 3,
    ZSTD_lazy = 4, ZSTD_lazy2 = 5, ZSTD_btlazy2 = 6, ZSTD_btopt = 7,
    ZSTD_btultra = 8, ZSTD_btultra2 = 9, ZSTD_strategy_Force32 = $40000000);

  ZSTD_ResetDirective = (ZSTD_reset_session_only = 1, ZSTD_reset_parameters = 2,
    ZSTD_reset_session_and_parameters = 3,
    ZSTD_ResetDirective_Force32 = $40000000);

  ZSTD_EndDirective = (ZSTD_e_continue = 0, ZSTD_e_flush = 1, ZSTD_e_end = 2,
    ZSTD_EndDirective_Force32 = $40000000);

  PZSTD_inBuffer = ^ZSTD_inBuffer;

  ZSTD_inBuffer = record
    src: Pointer;
    size: size_t;
    pos: size_t;
  end;

  PZSTD_outBuffer = ^ZSTD_outBuffer;

  ZSTD_outBuffer = record
    dst: Pointer;
    size: size_t;
    pos: size_t;
  end;

  PZSTD_CCtx_params = Pointer;

  ZSTD_cParameter = (ZSTD_c_compressionLevel = 100, ZSTD_c_windowLog = 101,
    ZSTD_c_hashLog = 102, ZSTD_c_chainLog = 103, ZSTD_c_searchLog = 104,
    ZSTD_c_minMatch = 105, ZSTD_c_targetLength = 106, ZSTD_c_strategy = 107,
    ZSTD_c_enableLongDistanceMatching = 160, ZSTD_c_ldmHashLog = 161,
    ZSTD_c_ldmMinMatch = 162, ZSTD_c_ldmBucketSizeLog = 163,
    ZSTD_c_ldmHashRateLog = 164, ZSTD_c_contentSizeFlag = 200,
    ZSTD_c_checksumFlag = 201, ZSTD_c_dictIDFlag = 202, ZSTD_c_nbWorkers = 400,
    ZSTD_c_jobSize = 401, ZSTD_c_overlapLog = 402,
    ZSTD_c_experimentalParam1 = 500, ZSTD_c_experimentalParam2 = 10,
    ZSTD_c_experimentalParam3 = 1000, ZSTD_c_experimentalParam4 = 1001,
    ZSTD_c_experimentalParam5 = 1002, ZSTD_c_experimentalParam6 = 1003,
    ZSTD_c_experimentalParam7 = 1004, ZSTD_c_experimentalParam8 = 1005,
    ZSTD_c_experimentalParam9 = 1006, ZSTD_c_experimentalParam10 = 1007,
    ZSTD_c_experimentalParam11 = 1008, ZSTD_c_experimentalParam12 = 1009,
    ZSTD_c_experimentalParam13 = 1010, ZSTD_c_experimentalParam14 = 1011,
    ZSTD_c_experimentalParam15 = 1012, ZSTD_cParameter_Force32 = $40000000);

  ZSTD_compressionParameters = record
    windowLog: Cardinal;
    chainLog: Cardinal;
    hashLog: Cardinal;
    searchLog: Cardinal;
    minMatch: Cardinal;
    targetLength: Cardinal;
    strategy: ZSTD_strategy;
  end;

  ZSTD_frameParameters = record
    contentSizeFlag: Integer;
    checksumFlag: Integer;
    noDictIDFlag: Integer;
  end;

  ZSTD_parameters = record
    cParams: ZSTD_compressionParameters;
    fParams: ZSTD_frameParameters;
  end;

var
  ZSTD_compress: function(dst: Pointer; dstCapacity: size_t; const src: Pointer;
    srcSize: size_t; compressionLevel: Integer): size_t cdecl;
  ZSTD_compress2: function(cctx: Pointer; dst: Pointer; dstCapacity: size_t;
    const src: Pointer; srcSize: size_t): size_t cdecl;
  ZSTD_compress_generic: function(cctx: Pointer; output: PZSTD_outBuffer;
    input: PZSTD_inBuffer; endOp: ZSTD_EndDirective): size_t cdecl;
  // Mismo prototipo que ZSTD_compress_generic, que era su nombre experimental:
  // zstd lo renombro y las versiones actuales YA NO EXPORTAN el viejo.
  // Verificado con nm sobre libzstd 1.5.7 -- ZSTD_compress_generic no aparece,
  // ZSTD_compressStream2 si. Quien use el viejo se queda con un puntero nil.
  ZSTD_compressStream2: function(cctx: Pointer; output: PZSTD_outBuffer;
    input: PZSTD_inBuffer; endOp: ZSTD_EndDirective): size_t cdecl;
  ZSTD_decompress: function(dst: Pointer; dstCapacity: size_t;
    const src: Pointer; srcSize: size_t): SSIZE_T cdecl;
  ZSTD_findFrameCompressedSize: function(const src: Pointer; srcSize: size_t)
    : int64 cdecl;
  ZSTD_findDecompressedSize: function(const src: Pointer; srcSize: size_t)
    : int64 cdecl;
  ZSTD_createCCtx: function: Pointer cdecl;
  ZSTD_freeCCtx: function(cctx: Pointer): size_t cdecl;
  ZSTD_CCtx_reset: function(cctx: Pointer; reset: ZSTD_ResetDirective)
    : size_t cdecl;
  ZSTD_CCtx_setParameter: function(cctx: Pointer; param: ZSTD_cParameter;
    value: Integer): size_t cdecl;
  ZSTD_CCtx_refPrefix: function(cctx: Pointer; const prefix: Pointer;
    prefixSize: size_t): size_t cdecl;
  ZSTD_compressCCtx: function(cctx: Pointer; dst: Pointer; dstCapacity: size_t;
    src: Pointer; srcSize: size_t; compressionLevel: Integer): size_t cdecl;
  ZSTD_createDCtx: function: Pointer cdecl;
  ZSTD_freeDCtx: function(dctx: Pointer): size_t cdecl;
  ZSTD_decompressDCtx: function(dctx: Pointer; dst: Pointer;
    dstCapacity: size_t; src: Pointer; srcSize: size_t): size_t cdecl;
  ZSTD_createCDict: function(const dict: Pointer; dictSize: size_t;
    compressionLevel: Integer): Pointer cdecl;
  ZSTD_freeCDict: function(ddict: Pointer): size_t cdecl;
  ZSTD_createDDict: function(const dict: Pointer; dictSize: size_t)
    : Pointer cdecl;
  ZSTD_freeDDict: function(ddict: Pointer): size_t cdecl;
  ZSTD_compress_usingCDict: function(cctx: Pointer; dst: Pointer;
    dstCapacity: size_t; const src: Pointer; srcSize: size_t;
    const cdict: Pointer): size_t cdecl;
  ZSTD_decompress_usingDDict: function(dctx: Pointer; dst: Pointer;
    dstCapacity: size_t; const src: Pointer; srcSize: size_t;
    const ddict: Pointer): size_t cdecl;
  ZSTD_initCStream: function(zcs: Pointer; compressionLevel: Integer)
    : size_t cdecl;
  // Necesario para reproducir lo que escribe el CLI de zstd: sin declarar el
  // tamaño de origen, el frame sale distinto. Medido con libzstd 1.5.7 sobre
  // 450KB: chunked con pledged size y sin flush por chunk da el mismo hash que
  // el CLI en niveles 3, 9 y 15; con flush por chunk difiere en los tres.
  ZSTD_CCtx_setPledgedSrcSize: function(cctx: Pointer; pledgedSrcSize: UInt64)
    : size_t cdecl;
  ZSTD_compressStream: function(zcs: Pointer; output: PZSTD_outBuffer;
    input: PZSTD_inBuffer): size_t cdecl;
  ZSTD_flushStream: function(zcs: Pointer; output: PZSTD_outBuffer)
    : size_t cdecl;
  ZSTD_endStream: function(zcs: Pointer; output: PZSTD_outBuffer): size_t cdecl;

  ZSTD_getCParams: function(compressionLevel: Integer; estimatedSrcSize: UInt64;
    dictSize: size_t): ZSTD_compressionParameters;

  DLLLoaded: Boolean = False;

function ZSTD_compress_dict(cctx: Pointer; dst: Pointer; dstCapacity: size_t;
  const src: Pointer; srcSize: size_t; const cdict: Pointer): size_t;
function ZSTD_decompress_dict(dctx: Pointer; dst: Pointer; dstCapacity: size_t;
  const src: Pointer; srcSize: size_t; const ddict: Pointer): size_t;

implementation

function ZSTD_compress_dict(cctx: Pointer; dst: Pointer; dstCapacity: size_t;
  const src: Pointer; srcSize: size_t; const cdict: Pointer): size_t;
begin
  cctx := ZSTD_createDCtx;
  Result := ZSTD_compress_usingCDict(cctx, dst, dstCapacity, src,
    srcSize, cdict);
  ZSTD_freeDCtx(cctx);
end;

function ZSTD_decompress_dict(dctx: Pointer; dst: Pointer; dstCapacity: size_t;
  const src: Pointer; srcSize: size_t; const ddict: Pointer): size_t;
begin
  dctx := ZSTD_createDCtx;
  Result := ZSTD_decompress_usingDDict(dctx, dst, dstCapacity, src,
    srcSize, ddict);
  ZSTD_freeDCtx(dctx);
end;

var
  Lib: TLibImport;

procedure Init(Filename: String; Raw: Boolean = False);
begin
  Lib := TLibImport.Create;
  // Raw=True carga el nombre tal cual, para un soname del sistema: ExpandPath
  // le antepone el directorio del ejecutable a toda ruta sin separador
  // inicial, lo que es correcto para un archivo nuestro y fatal para un
  // soname, que tiene que resolver el loader.
  if Raw then
    Lib.LoadLib(Filename)
  else
    Lib.LoadLib(ExpandPath(Filename, True));
{$IFDEF UNIX}
{$ENDIF}
  if Lib.Loaded then
  begin
    @ZSTD_compress := Lib.GetProcAddr('ZSTD_compress');
    @ZSTD_compress2 := Lib.GetProcAddr('ZSTD_compress2');
    @ZSTD_compress_generic := Lib.GetProcAddr('ZSTD_compress_generic');
    @ZSTD_compressStream2 := Lib.GetProcAddr('ZSTD_compressStream2');
    @ZSTD_decompress := Lib.GetProcAddr('ZSTD_decompress');
    @ZSTD_findFrameCompressedSize :=
      Lib.GetProcAddr('ZSTD_findFrameCompressedSize');
    @ZSTD_findDecompressedSize := Lib.GetProcAddr('ZSTD_findDecompressedSize');
    @ZSTD_createCCtx := Lib.GetProcAddr('ZSTD_createCCtx');
    @ZSTD_freeCCtx := Lib.GetProcAddr('ZSTD_freeCCtx');
    @ZSTD_CCtx_reset := Lib.GetProcAddr('ZSTD_CCtx_reset');
    @ZSTD_CCtx_setParameter := Lib.GetProcAddr('ZSTD_CCtx_setParameter');
    @ZSTD_CCtx_refPrefix  := Lib.GetProcAddr('ZSTD_CCtx_refPrefix');
    @ZSTD_createDCtx := Lib.GetProcAddr('ZSTD_createDCtx');
    @ZSTD_freeDCtx := Lib.GetProcAddr('ZSTD_freeDCtx');
    @ZSTD_createCDict := Lib.GetProcAddr('ZSTD_createCDict');
    @ZSTD_freeCDict := Lib.GetProcAddr('ZSTD_freeCDict');
    @ZSTD_compressCCtx := Lib.GetProcAddr('ZSTD_compressCCtx');
    @ZSTD_createDDict := Lib.GetProcAddr('ZSTD_createDDict');
    @ZSTD_freeDDict := Lib.GetProcAddr('ZSTD_freeDDict');
    @ZSTD_decompressDCtx := Lib.GetProcAddr('ZSTD_decompressDCtx');
    @ZSTD_compress_usingCDict := Lib.GetProcAddr('ZSTD_compress_usingCDict');
    @ZSTD_decompress_usingDDict :=
      Lib.GetProcAddr('ZSTD_decompress_usingDDict');
    @ZSTD_initCStream := Lib.GetProcAddr('ZSTD_initCStream');
    @ZSTD_CCtx_setPledgedSrcSize :=
      Lib.GetProcAddr('ZSTD_CCtx_setPledgedSrcSize');
    @ZSTD_compressStream := Lib.GetProcAddr('ZSTD_compressStream');
    @ZSTD_flushStream := Lib.GetProcAddr('ZSTD_flushStream');
    @ZSTD_endStream := Lib.GetProcAddr('ZSTD_endStream');
    @ZSTD_getCParams := Lib.GetProcAddr('ZSTD_getCParams');
    DLLLoaded := Assigned(ZSTD_compress) and Assigned(ZSTD_decompress);
  end;
end;

procedure Deinit;
begin
  Lib.Free;
end;

const
  DLLParam = '-zstd';

var
  I: Integer;
  Candidates: TArray<String>;

initialization

// -zstd se puede repetir: cada uno agrega un candidato y se prueban EN ORDEN
// hasta que uno cargue. Antes se tomaba solo el primero. Sigue a xtool 0.9.9,
// que hizo repetibles -lz4, -zstd y -oodle# (-oodle ya funcionaba asi aca, ver
// OodleDLL).
//
// El soname del sistema va al final y por fuera de la lista, con Raw=True: los
// candidatos pasan por ExpandPath, que a una ruta sin separador inicial le
// antepone el directorio del ejecutable. Correcto para un archivo nuestro,
// fatal para un soname. Ademas antes vivia dentro de Init, y ahi un candidato
// que no cargaba caia igual al del sistema y dejaba DLLLoaded en true: el
// primero siempre "tenia exito" y los demas no se probaban nunca.
SetLength(Candidates, 0);
for I := 1 to ParamCount do
  if ParamStr(I).StartsWith(DLLParam) then
    Insert(ParamStr(I).Substring(DLLParam.Length), Candidates,
      Length(Candidates));
{$IFDEF UNIX}
Insert(PluginsPath + 'libzstd.so', Candidates, Length(Candidates));
{$ELSE}
Insert(PluginsPath + 'libzstd.dll', Candidates, Length(Candidates));
{$ENDIF}
for I := Low(Candidates) to High(Candidates) do
begin
  Init(Candidates[I]);
  if DLLLoaded then
    break;
  FreeAndNil(Lib);
end;
{$IFDEF UNIX}
if not DLLLoaded then
begin
  FreeAndNil(Lib);
  Init('libzstd.so.1', True);
end;
{$ENDIF}

finalization

Deinit;

end.
