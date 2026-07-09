unit PrecompAnalyze;

interface

uses
  Utils,
  SysUtils, Classes, Process;

procedure PrintHelp;
procedure RunAnalyze(const InputPath: String);

implementation

const
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
var
  Proc: TProcess;
  Cmd: String;
begin
  Result.Method := Method;
  Result.Ran := False;
  Result.OutSize := 0;
  if FileExists(OutputPath) then
    DeleteFile(OutputPath);
  Proc := TProcess.Create(nil);
  try
{$IFDEF MSWINDOWS}
    Proc.Executable := 'cmd.exe';
    Proc.Parameters.Add('/c');
    Cmd := '"' + SelfExe + '" precomp -m' + Method + ' "' + InputPath +
      '" "' + OutputPath + '" > NUL 2>&1';
{$ELSE}
    Proc.Executable := '/bin/sh';
    Proc.Parameters.Add('-c');
    Cmd := '"' + SelfExe + '" precomp -m' + Method + ' "' + InputPath +
      '" "' + OutputPath + '" > /dev/null 2>&1';
{$ENDIF}
    Proc.Parameters.Add(Cmd);
    Proc.Options := [poWaitOnExit];
    Proc.Execute;
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

procedure RunAnalyze(const InputPath: String);
var
  InSize: Int64;
  I: Integer;
  Trial, Combined, BestSingle: TTrialResult;
  Winners: TStringList;
  CombinedMethod, SelfExe, TmpOut: String;
begin
  if not FileExists(InputPath) then
  begin
    WriteLine(Format('No existe el archivo: %s', [InputPath]));
    exit;
  end;
  InSize := FileSize(InputPath);
  if InSize = 0 then
  begin
    WriteLine('Archivo vacio, nada que analizar.');
    exit;
  end;
  SelfExe := ExpandFileName(ParamStr(0));
  TmpOut := IncludeTrailingPathDelimiter(GetTempDir) +
    'ytool_analyze_' + IntToStr(Random($7FFFFFFF)) + '.tmp';
  WriteLine(Format('Analizando %s (%s)', [ExtractFileName(InputPath),
    ConvertKB2TB(InSize div 1024)]));
  WriteLine('');
  WriteLine(Format('%-10s %14s %8s', ['Codec', 'Tamano', 'Ratio']));
  Winners := TStringList.Create;
  BestSingle.Ran := False;
  BestSingle.OutSize := InSize;
  try
    for I := Low(Candidates) to High(Candidates) do
    begin
      Trial := RunTrial(SelfExe, InputPath, Candidates[I], TmpOut);
      if not Trial.Ran then
      begin
        WriteLine(Format('  (%s fallo)', [Candidates[I]]));
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
      WriteLine('Ningun codec mejoro este archivo. Recomendado: literal (sin -m).');
      exit;
    end;
    CombinedMethod := Winners[0];
    for I := 1 to Winners.Count - 1 do
      CombinedMethod := CombinedMethod + '+' + Winners[I];
    Combined := RunTrial(SelfExe, InputPath, CombinedMethod, TmpOut);
    // Codecs que compiten por el mismo tipo de stream (ej. packjpg vs brunsli,
    // ambos JPEG) no siempre dan mejor resultado combinados que el mejor
    // individual solo -- se compara y se recomienda el que realmente gane.
    if Combined.Ran and (Combined.OutSize <= BestSingle.OutSize) then
      WriteLine(Format('Recomendado: -m%s  (%d bytes, %.1f%% del original)',
        [CombinedMethod, Combined.OutSize, Combined.OutSize / InSize * 100]))
    else
      WriteLine(Format('Recomendado: -m%s  (%d bytes, %.1f%% del original)',
        [BestSingle.Method, BestSingle.OutSize,
        BestSingle.OutSize / InSize * 100]));
  finally
    Winners.Free;
  end;
end;

procedure PrintHelp;
begin
  WriteLine('ytool - open-source recreation of xtool by Razor12911');
  WriteLine('');
  WriteLine('analyze - prueba cada codec de precompresion por separado sobre un');
  WriteLine('          archivo (compresion real, no solo deteccion) y recomienda');
  WriteLine('          la combinacion de -m que mejor resultado da. No genera');
  WriteLine('          ningun archivo de salida, solo un reporte por consola.');
  WriteLine('          Exclusivo de ytool, sin equivalente en xtool.');
  WriteLine('');
  WriteLine('Usage:');
  WriteLine('  ytool analyze input');
end;

end.
