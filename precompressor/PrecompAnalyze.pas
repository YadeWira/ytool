unit PrecompAnalyze;

interface

uses
  Utils,
  SysUtils, Classes, Process, Math, StrUtils;

procedure PrintHelp;
procedure RunAnalyze(const InputPath: String; const Flags: TArray<String>);

implementation

const
  // By default, files larger than this are analyzed by sample (the
  // first SampleSize bytes) instead of in full -- each candidate runs
  // a real compression (see Candidates below), so cost scales
  // linearly with file size AND the number of candidates; on
  // multi-GB files, analyzing in full can take minutes/hours. The
  // -full flag forces full analysis if accuracy is preferred over
  // speed.
  SampleSize: Int64 = 64 * 1024 * 1024;
  // Candidates with their own detection (standalone Scan1, not via -r).
  // Excluded: jojpeg (no open source), the oodle family (proprietary lib
  // not included by default), and xor/aes/rc4 (PrecompCrypto.Scan1 is a
  // no-op, only activated by reassigning streams already detected by another codec).
  //
  // Each trial runs in its own SUBPROCESS (ytool precomp -m<codec>), not
  // by calling PrecompMain.Encode() multiple times in the same process: that
  // pipeline assumes a single invocation per process (found while
  // implementing this command -- EncFreed and several global TMemoryStream/
  // TDataStore instances are never reset/freed between calls, and the
  // second invocation always ends in an Access Violation). Doing it via a
  // subprocess reuses the real "precomp" path, already tested exhaustively.
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
  OutputPath, ThreadsArg: String): TTrialResult;
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
    if ThreadsArg <> '' then
      Proc.Parameters.Add(ThreadsArg);
    Proc.Parameters.Add(InputPath);
    Proc.Parameters.Add(OutputPath);
    Proc.Options := [poUsePipes];
    Proc.Execute;
    // No intermediate shell (avoids cmd.exe quoting hell with
    // nested paths/quotes); the child's stdout/stderr pipes are drained
    // to discard its output without blocking if the buffer fills up.
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

// Returns the raw token (e.g. "-t4p") if the user passed a flag with this
// prefix to `analyze`, so it can be forwarded as-is to each trial's `precomp`
// subprocess -- the same ArgParser there parses it identically. Used for
// `-t#` (thread count), which `analyze`'s subprocess trials previously always
// ran with precomp's own default instead of what the user actually asked for.
function GetFlagValue(const Flags: TArray<String>; const Prefix: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := Low(Flags) to High(Flags) do
    if Flags[I].StartsWith(Prefix, False) then
    begin
      Result := Flags[I];
      exit;
    end;
end;

// Copies the first Count bytes of Src to a new temp file; returns
// the temp file's path. The caller is responsible for deleting it.
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
  CombinedMethod, SelfExe, TmpOut, AnalyzeInput, SamplePath, ThreadsArg: String;
  Sampled: Boolean;
begin
  ThreadsArg := GetFlagValue(Flags, '-t');
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
        Trial := RunTrial(SelfExe, AnalyzeInput, Candidates[I], TmpOut, ThreadsArg);
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
      Combined := RunTrial(SelfExe, AnalyzeInput, CombinedMethod, TmpOut, ThreadsArg);
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
  WriteLine('          -t# forwards a thread-count override (same syntax as');
  WriteLine('          precomp''s own -t#) to every trial subprocess.');
  WriteLine('');
  WriteLine('Usage:');
  WriteLine('  ytool analyze [-full] [-t#] input');
end;

end.
