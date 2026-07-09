unit PrecompAnalyze;

interface

uses
  Utils,
  SysUtils, Classes, Process, Math, StrUtils;

procedure PrintHelp;
procedure RunAnalyze(const InputPath: String; const Flags: TArray<String>);

implementation

const
  // Por defecto, archivos mas grandes que esto se analizan por muestra (los
  // primeros SampleSize bytes) en vez de completos -- cada candidato corre
  // una compresion real (ver Candidates mas abajo), asi que el costo escala
  // linealmente con el tamano del archivo Y la cantidad de candidatos; sobre
  // archivos de varios GB, analizar completo puede tardar minutos/horas. El
  // flag -full fuerza el analisis completo si se prefiere exactitud sobre
  // velocidad.
  SampleSize: Int64 = 64 * 1024 * 1024;
  // Candidatos con deteccion propia (Scan1 independiente, no via -r). Se
  // excluyen jojpeg (sin fuente abierta), la familia oodle (lib propietaria
  // no incluida por defecto) y xor/aes/rc4 (PrecompCrypto.Scan1 es un no-op,
  // solo se activan reasignando streams ya detectados por otro codec).
  //
  // Cada prueba corre en un SUBPROCESO propio (ytool precomp -m<codec>), no
  // llamando PrecompMain.Encode() varias veces en el mismo proceso: ese
  // pipeline asume una sola invocacion por proceso (encontrado durante la
  // implementacion de este comando -- EncFreed y varios TMemoryStream/
  // TDataStore globales nunca se resetean/liberan entre llamadas, y la
  // segunda invocacion siempre termina en Access Violation). Hacerlo via
  // subproceso reusa el camino de "precomp" real, ya probado exhaustivamente.
  Candidates: array [0 .. 16] of String = ('zlib', 'reflate', 'preflate',
    'lz4', 'lz4hc', 'lz4f', 'lzo1x', 'lzo2a', 'lzo1c', 'zstd', 'flac',
    'wavpack', 'packjpg', 'brunsli', 'packmp3', 'packpng', 'png');

type
  TTrialResult = record
    Method: String;
    OutSize: Int64;
    Ran: Boolean;
  end;

function RunTrial(const SelfExe, InputPath, Method,
  OutputPath: String): TTrialResult;
const
  BufSize = 65536;
var
  Proc: TProcess;
  Buf: array [0 .. BufSize - 1] of Byte;
begin
  Result.Method := Method;
  Result.Ran := False;
  Result.OutSize := 0;
  if FileExists(OutputPath) then
    DeleteFile(OutputPath);
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := SelfExe;
    Proc.Parameters.Add('precomp');
    Proc.Parameters.Add('-m' + Method);
    Proc.Parameters.Add(InputPath);
    Proc.Parameters.Add(OutputPath);
    Proc.Options := [poUsePipes];
    Proc.Execute;
    // Sin shell intermedio (evita el infierno de quoting de cmd.exe con
    // rutas/comillas anidadas); se drenan los pipes de stdout/stderr del
    // hijo para descartar su salida sin bloquear si llena el buffer.
    while Proc.Running do
    begin
      while Proc.Output.NumBytesAvailable > 0 do
        Proc.Output.Read(Buf, Min(BufSize, Proc.Output.NumBytesAvailable));
      while Proc.Stderr.NumBytesAvailable > 0 do
        Proc.Stderr.Read(Buf, Min(BufSize, Proc.Stderr.NumBytesAvailable));
      Sleep(10);
    end;
    while Proc.Output.NumBytesAvailable > 0 do
      Proc.Output.Read(Buf, Min(BufSize, Proc.Output.NumBytesAvailable));
    while Proc.Stderr.NumBytesAvailable > 0 do
      Proc.Stderr.Read(Buf, Min(BufSize, Proc.Stderr.NumBytesAvailable));
    if FileExists(OutputPath) then
    begin
      Result.OutSize := FileSize(OutputPath);
      Result.Ran := True;
      DeleteFile(OutputPath);
    end;
  finally
    Proc.Free;
  end;
end;

function HasFlag(const Flags: TArray<String>; const Name: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(Flags) to High(Flags) do
    if SameText(Flags[I], Name) then
    begin
      Result := True;
      exit;
    end;
end;

// Copia los primeros Count bytes de Src a un archivo temporal nuevo; devuelve
// la ruta del temporal. El caller es responsable de borrarlo.
function MakeSample(const Src: String; Count: Int64): String;
var
  InF, OutF: TFileStream;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) +
    'ytool_analyze_sample_' + IntToStr(Random($7FFFFFFF)) + '.tmp';
  InF := TFileStream.Create(Src, fmOpenRead or fmShareDenyNone);
  try
    OutF := TFileStream.Create(Result, fmCreate);
    try
      OutF.CopyFrom(InF, Count);
    finally
      OutF.Free;
    end;
  finally
    InF.Free;
  end;
end;

procedure RunAnalyze(const InputPath: String; const Flags: TArray<String>);
var
  InSize, RealSize: Int64;
  I: Integer;
  Trial, Combined, BestSingle: TTrialResult;
  Winners: TStringList;
  CombinedMethod, SelfExe, TmpOut, AnalyzeInput, SamplePath: String;
  Sampled: Boolean;
begin
  if not FileExists(InputPath) then
  begin
    WriteLine(Format('File not found: %s', [InputPath]));
    exit;
  end;
  RealSize := FileSize(InputPath);
  if RealSize = 0 then
  begin
    WriteLine('Empty file, nothing to analyze.');
    exit;
  end;
  SelfExe := ExpandFileName(ParamStr(0));
  TmpOut := IncludeTrailingPathDelimiter(GetTempDir) +
    'ytool_analyze_' + IntToStr(Random($7FFFFFFF)) + '.tmp';
  SamplePath := '';
  Sampled := (RealSize > SampleSize) and not HasFlag(Flags, '-full');
  if Sampled then
  begin
    SamplePath := MakeSample(InputPath, SampleSize);
    AnalyzeInput := SamplePath;
    InSize := SampleSize;
  end
  else
  begin
    AnalyzeInput := InputPath;
    InSize := RealSize;
  end;
  try
    WriteLine(Format('Analyzing %s (%s)', [ExtractFileName(InputPath),
      ConvertKB2TB(RealSize div 1024)]));
    if Sampled then
      WriteLine(Format('File is large (%s) -- sampling the first %s only.' +
        ' Use -full to analyze the whole file (much slower).',
        [ConvertKB2TB(RealSize div 1024), ConvertKB2TB(InSize div 1024)]));
    WriteLine('');
    WriteLine(Format('%-10s %14s %8s', ['Codec', 'Size', 'Ratio']));
    Winners := TStringList.Create;
    BestSingle.Ran := False;
    BestSingle.OutSize := InSize;
    try
      for I := Low(Candidates) to High(Candidates) do
      begin
        Trial := RunTrial(SelfExe, AnalyzeInput, Candidates[I], TmpOut);
        if not Trial.Ran then
        begin
          WriteLine(Format('  (%s failed)', [Candidates[I]]));
          continue;
        end;
        WriteLine(Format('%-10s %14d %7.1f%%', [Trial.Method, Trial.OutSize,
          Trial.OutSize / InSize * 100]));
        if Trial.OutSize < InSize then
        begin
          Winners.Add(Trial.Method);
          if Trial.OutSize < BestSingle.OutSize then
            BestSingle := Trial;
        end;
      end;
      WriteLine('');
      if Winners.Count = 0 then
      begin
        WriteLine('No codec improved this file. Recommended: literal (no -m).');
        exit;
      end;
      CombinedMethod := Winners[0];
      for I := 1 to Winners.Count - 1 do
        CombinedMethod := CombinedMethod + '+' + Winners[I];
      Combined := RunTrial(SelfExe, AnalyzeInput, CombinedMethod, TmpOut);
      // Codecs competing for the same stream type (e.g. packjpg vs brunsli,
      // both JPEG) don't always do better combined than the best individual
      // one alone -- compare and recommend whichever actually wins.
      if Combined.Ran and (Combined.OutSize <= BestSingle.OutSize) then
        WriteLine(Format('Recommended: -m%s  (%d bytes, %.1f%% of the %s)',
          [CombinedMethod, Combined.OutSize, Combined.OutSize / InSize * 100,
          IfThen(Sampled, 'sample', 'original')]))
      else
        WriteLine(Format('Recommended: -m%s  (%d bytes, %.1f%% of the %s)',
          [BestSingle.Method, BestSingle.OutSize,
          BestSingle.OutSize / InSize * 100,
          IfThen(Sampled, 'sample', 'original')]));
    finally
      Winners.Free;
    end;
  finally
    if Sampled and FileExists(SamplePath) then
      DeleteFile(SamplePath);
  end;
end;

procedure PrintHelp;
begin
  WriteLine('ytool - open-source recreation of xtool by Razor12911');
  WriteLine('');
  WriteLine('analyze - tries each precompression codec separately on a file');
  WriteLine('          (real compression, not just detection) and recommends');
  WriteLine('          the -m combination that gives the best result. Produces');
  WriteLine('          no output file, only a console report.');
  WriteLine('          Exclusive to ytool, no equivalent in xtool.');
  WriteLine('');
  WriteLine('          Files larger than 64MB are analyzed by sampling the');
  WriteLine('          first 64MB only (each candidate runs a real compression,');
  WriteLine('          so cost scales with file size) -- pass -full to analyze');
  WriteLine('          the whole file instead (much slower on large files).');
  WriteLine('');
  WriteLine('Usage:');
  WriteLine('  ytool analyze [-full] input');
end;

end.
