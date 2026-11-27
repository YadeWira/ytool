unit PrecompAnalyze;

// ytool analyze: which -m to use on a file, measured.
//
// Each codec is tried in a precomp subprocess of its own (the precomp
// pipeline assumes one run per process: a second Encode() in the same process
// ended in an access violation), several at once. What is compared is what a
// user keeps: the size after the final compressor (-l#, fast-lzma2), against
// the same file with no codec. Until 0.9.9b analyze compared the size of the
// .ytp itself, which GROWS when a codec works (it holds the unpacked
// streams): on a file of 200 deflate streams it said "No codec improved this
// file".

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Utils, CliUI, PrecompHelp,
  SysUtils, Classes, Process, Math, StrUtils;

procedure PrintHelp;
procedure RunAnalyze(const InputPath: String; const Flags: TArray<String>);

implementation

const
  // Above this, the trials run on samples spread over the file instead of
  // the whole of it (-full: the whole file).
  SampleLimit: Int64 = 64 * 1024 * 1024;
  SampleSlices = 8;
  DefaultLevel = 3;

type
  TTrial = record
    Name: String;              // what the report calls it
    Method: String;            // -m value, '' for none
    Extra: TArray<String>;     // more precomp options (-dd)
    OutPath: String;
    Proc: TProcess;
    Log: AnsiString;
    Started, Done, Ok: Boolean;
    StartTime: TDateTime;
    Seconds: Double;
    OutSize: Int64;
    Processed, Found: Integer;
  end;

  TTrials = TArray<TTrial>;

var
  SelfExe, WorkDir, InputFile, LevelArg, ThreadsArg: String;

function HasFlag(const Flags: TArray<String>; const Name: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(Flags) to High(Flags) do
    if SameText(Flags[I], Name) then
      exit(True);
end;

// The first flag starting with Prefix, or ''.
function FlagValue(const Flags: TArray<String>; const Prefix: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := Low(Flags) to High(Flags) do
    if Flags[I].StartsWith(Prefix, False) then
      exit(Flags[I]);
end;

// SampleSlices pieces spread over the file, start and end included, written
// one after another: streams anywhere in it get a chance, where the first
// 64 MB alone (0.9.9b) only showed the start of an archive.
function MakeSample(const Src: String; Total: Int64): String;
var
  InF, OutF: TFileStream;
  Size, Slice, Pos: Int64;
  I: Integer;
begin
  Result := WorkDir + 'sample.bin';
  InF := TFileStream.Create(Src, fmOpenRead or fmShareDenyNone);
  try
    OutF := TFileStream.Create(Result, fmCreate);
    try
      Size := InF.Size;
      Slice := Total div SampleSlices;
      for I := 0 to SampleSlices - 1 do
      begin
        Pos := (Size - Slice) * I div (SampleSlices - 1);
        InF.Position := Pos;
        OutF.CopyFrom(InF, Slice);
      end;
    finally
      OutF.Free;
    end;
  finally
    InF.Free;
  end;
end;

function SameContent(const A, B: String): Boolean;
const
  N = 1 shl 20;
var
  FA, FB: TFileStream;
  BA, BB: TBytes;
  RA, RB: Integer;
begin
  Result := False;
  if not(FileExists(A) and FileExists(B)) then
    exit;
  FA := TFileStream.Create(A, fmOpenRead or fmShareDenyNone);
  FB := TFileStream.Create(B, fmOpenRead or fmShareDenyNone);
  try
    if FA.Size <> FB.Size then
      exit;
    SetLength(BA, N);
    SetLength(BB, N);
    repeat
      RA := FA.Read(BA[0], N);
      RB := FB.Read(BB[0], N);
      if (RA <> RB) or not CompareMem(@BA[0], @BB[0], RA) then
        exit;
    until RA = 0;
    Result := True;
  finally
    FA.Free;
    FB.Free;
  end;
end;

// The trials' files, then the folder (it holds no subfolders).
procedure RemoveWorkDir;
var
  SR: TSearchRec;
begin
  if FindFirst(WorkDir + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then
        DeleteFile(WorkDir + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  RemoveDir(ExcludeTrailingPathDelimiter(WorkDir));
end;

function NewTrial(const Name, Method: String; const Extra: TArray<String>)
  : TTrial;
begin
  Result := Default(TTrial);
  Result.Name := Name;
  Result.Method := Method;
  Result.Extra := Extra;
end;

procedure Drain(var T: TTrial);
var
  Buf: array [0 .. 65535] of AnsiChar;
  Chunk: AnsiString;
  N: Integer;
begin
  while T.Proc.Output.NumBytesAvailable > 0 do
  begin
    N := T.Proc.Output.Read(Buf, Min(SizeOf(Buf),
      T.Proc.Output.NumBytesAvailable));
    if N <= 0 then
      break;
    SetString(Chunk, PAnsiChar(@Buf[0]), N);
    T.Log := T.Log + Chunk;
  end;
end;

procedure StartTrial(var T: TTrial; Index: Integer);
var
  I: Integer;
begin
  T.OutPath := WorkDir + 'trial' + Index.ToString + '.ytp';
  T.Proc := TProcess.Create(nil);
  T.Proc.Executable := SelfExe;
  T.Proc.Parameters.Add('precomp');
  if T.Method <> '' then
    T.Proc.Parameters.Add('-m' + T.Method);
  for I := Low(T.Extra) to High(T.Extra) do
    T.Proc.Parameters.Add(T.Extra[I]);
  T.Proc.Parameters.Add(LevelArg);
  T.Proc.Parameters.Add(ThreadsArg);
  T.Proc.Parameters.Add(InputFile);
  T.Proc.Parameters.Add(T.OutPath);
  // One pipe for both: precomp's summary goes to whichever it likes.
  T.Proc.Options := [poUsePipes, poStderrToOutPut];
  T.StartTime := Now;
  {$IFDEF UNIX}StartProcess(T.Proc){$ELSE}T.Proc.Execute{$ENDIF};
  T.Started := True;
end;

procedure FinishTrial(var T: TTrial);
var
  P: Integer;
  S: String;
begin
  Drain(T);
  T.Seconds := (Now - T.StartTime) * 86400;
  T.Ok := (T.Proc.ExitStatus = 0) and FileExists(T.OutPath);
  // "Streams: 200 / 200 (32.95%)": processed / found
  P := Pos('Streams: ', T.Log);
  if P > 0 then
  begin
    S := Copy(T.Log, P + 9, 40);
    T.Processed := StrToIntDef(Trim(Copy(S, 1, Pos('/', S) - 1)), 0);
    S := Copy(S, Pos('/', S) + 1, 40);
    T.Found := StrToIntDef(Trim(Copy(S, 1, Pos('(', S) - 1)), 0);
  end;
  if T.Ok then
    T.OutSize := FileSize(T.OutPath);
  T.Proc.Free;
  T.Proc := nil;
  T.Done := True;
end;

// Runs every trial, Jobs at a time.
procedure RunTrials(var T: TTrials; Jobs: Integer; const What: String);
var
  I, Running, DoneCount: Integer;
  Busy: Boolean;
begin
  DoneCount := 0;
  for I := Low(T) to High(T) do
    if T[I].Done then
      Inc(DoneCount);
  while DoneCount < Length(T) do
  begin
    Busy := False;
    Running := 0;
    for I := Low(T) to High(T) do
      if T[I].Started and not T[I].Done then
        Inc(Running);
    for I := Low(T) to High(T) do
      if (Running < Jobs) and not T[I].Started then
      begin
        StartTrial(T[I], I);
        Inc(Running);
        Busy := True;
      end;
    for I := Low(T) to High(T) do
      if T[I].Started and not T[I].Done then
      begin
        Drain(T[I]);
        if not T[I].Proc.Running then
        begin
          FinishTrial(T[I]);
          Inc(DoneCount);
          Busy := True;
        end;
      end;
    if UIIsTTY then
      UIStatus(Format('%s: %d of %d', [What, DoneCount, Length(T)]));
    if not Busy then
      Sleep(10);
  end;
  if UIIsTTY then
    UIStatusClear;
end;

function Pct(Size, Base: Int64): String;
begin
  if Base <= 0 then
    exit('');
  // FPC's Format has no '+' flag; a change under 0.05% is 0.0%, unsigned
  Result := Format('%.1f%%', [Abs(Size - Base) / Base * 100]);
  if Result = '0.0%' then
    exit;
  if Size > Base then
    Result := '+' + Result
  else
    Result := '-' + Result;
  if Size < Base then
    Result := UIGreen(Result)
  else if Size > Base then
    Result := UIRed(Result);
end;

procedure Row(const Name, Streams, Size, Change, Time: String);
begin
  WriteLine('  ' + UIPad(Name, 22) + UIPad(Streams, 14) + UIPad(Size, 12) +
    UIPad(Change, 10) + Time);
end;

procedure RunAnalyze(const InputPath: String; const Flags: TArray<String>);
var
  Codecs: TArray<TCodecInfo>;
  Only: TStringList;
  Trials, Final: TTrials;
  Base: TTrial;
  Groups, Hints, Skipped, Silent: TStringList;
  RealSize, InSize, BestSize: Int64;
  I, J, Jobs, Threads, Best, Level: Integer;
  Sampled, Verbose: Boolean;
  S, Combo, Restored: String;
  BestIdx: array of Integer;
begin
  if not FileExists(InputPath) then
    raise Exception.CreateFmt('file not found: %s', [InputPath]);
  RealSize := FileSize(InputPath);
  if RealSize = 0 then
  begin
    WriteLine('Empty file, nothing to analyze.');
    exit;
  end;
  SelfExe := ExpandFileName(ParamStr(0));
  Verbose := HasFlag(Flags, '-v');
  S := FlagValue(Flags, '-l');
  Level := DefaultLevel;
  if S <> '' then
    Level := EnsureRange(StrToIntDef(Copy(S, 3, 2), DefaultLevel), 1, 10);
  LevelArg := '-l' + Level.ToString;
  // Trials run side by side, each with its share of the CPUs.
  Jobs := EnsureRange(CPUCores div 4, 1, 8);
  ThreadsArg := FlagValue(Flags, '-t');
  Threads := Max(1, CPUCores div Jobs);
  if ThreadsArg = '' then
    ThreadsArg := '-t' + Threads.ToString;

  Only := TStringList.Create;
  Groups := TStringList.Create;
  Hints := TStringList.Create;
  Skipped := TStringList.Create;
  Silent := TStringList.Create;
  WorkDir := IncludeTrailingPathDelimiter(GetTempDir) + 'ytool-analyze-' +
    GetProcessID.ToString + PathDelim;
  ForceDirectories(WorkDir);
  try
    S := FlagValue(Flags, '-m');
    if S <> '' then
      Only.Text := StringReplace(Copy(S, 3, MaxInt), '+', sLineBreak,
        [rfReplaceAll]);
    // 0.9.9e: -mzzz tried nothing and still recommended "(no codec)"
    Codecs := CodecTable;
    for I := 0 to Only.Count - 1 do
    begin
      J := High(Codecs);
      while (J >= 0) and not SameText(Codecs[J].Name, Only[I]) do
        Dec(J);
      if J < 0 then
        raise Exception.CreateFmt('analyze: unknown codec ''%s'' (ytool help ' +
          'precomp lists them)', [Only[I]]);
    end;

    Sampled := (RealSize > SampleLimit) and not HasFlag(Flags, '-full');
    if Sampled then
    begin
      InputFile := MakeSample(InputPath, SampleLimit);
      InSize := SampleLimit;
    end
    else
    begin
      InputFile := ExpandFileName(InputPath);
      InSize := RealSize;
    end;

    WriteLine(UIBold('analyze') + ' ' + ExtractFileName(InputPath) + ' (' +
      UISize(RealSize) + ')');
    if Sampled then
      WriteLine(UIDim(Format('  %d pieces of %s from all over the file ' +
        '(-full: the whole file, slower)', [SampleSlices,
        UISize(SampleLimit div SampleSlices)])));
    WriteLine(UIDim(Format('  each codec alone, then compressed with %s; ' +
      'compared with no codec at all', [LevelArg])));
    WriteLine('');

    Codecs := CodecTable;
    Trials := nil;
    Insert(NewTrial('(no codec)', '', nil), Trials, 0);
    for I := Low(Codecs) to High(Codecs) do
    begin
      if (Only.Count > 0) and (Only.IndexOf(Codecs[I].Name) < 0) then
        continue;
      if not Codecs[I].Available then
      begin
        Skipped.Add(Codecs[I].Name);
        continue;
      end;
      Insert(NewTrial(Codecs[I].Name, Codecs[I].Name, nil), Trials,
        Length(Trials));
    end;
    RunTrials(Trials, Jobs, 'Trying codecs');

    Base := Trials[0];
    if not Base.Ok then
      raise Exception.Create('precomp failed on this file:' + sLineBreak +
        Trim(String(Base.Log)));
    Row(UIBold('codec'), UIBold('streams'), UIBold('size'), UIBold('vs none'),
      UIBold('time'));
    Row('(no codec)', '', UISize(Base.OutSize), '', Format('%.1f s',
      [Base.Seconds]));

    // Best codec of each group: the one that leaves the smallest file.
    SetLength(BestIdx, 0);
    for I := 1 to High(Trials) do
      with Trials[I] do
      begin
        if not Ok then
        begin
          Row(Name, UIRed('failed'), '', '', '');
          continue;
        end;
        if Found = 0 then
        begin
          Silent.Add(Name);
          if not Verbose then
            continue;
        end;
        Row(Name, Format('%d / %d', [Processed, Found]), UISize(OutSize),
          Pct(OutSize, Base.OutSize), Format('%.1f s', [Seconds]));
        for J := Low(Codecs) to High(Codecs) do
          if Codecs[J].Name = Method then
            S := Codecs[J].Group;
        // Found but not reproduced: brute force may find the settings.
        if (Found > Processed) and MatchStr(Method, ['zstd', 'lz4', 'lz4hc',
          'lz4f']) then
          Hints.Add(Format('%d of %d %s streams could not be rebuilt with ' +
            'the usual settings: -b searches for theirs (ytool precomp -m%s -b ...)',
            [Found - Processed, Found, Method, Method]));
        if (Processed > 0) and (OutSize < Base.OutSize) then
        begin
          J := Groups.IndexOf(S);
          if J < 0 then
          begin
            Groups.Add(S);
            SetLength(BestIdx, Groups.Count);
            BestIdx[Groups.Count - 1] := I;
          end
          else if OutSize < Trials[BestIdx[J]].OutSize then
            BestIdx[J] := I;
        end;
      end;
    if (Silent.Count > 0) and not Verbose then
      WriteLine(UIDim('  no streams for: ' + StringReplace(Trim(Silent.Text),
        sLineBreak, ' ', [rfReplaceAll])));
    if Skipped.Count > 0 then
      WriteLine(UIDim('  not tried, library not found next to ytool: ' +
        StringReplace(Trim(Skipped.Text), sLineBreak, ' ', [rfReplaceAll])));
    WriteLine('');

    if Groups.Count = 0 then
    begin
      WriteLine('No codec makes this file smaller after ' + LevelArg +
        ': precomp would only add work.');
      for I := 0 to Hints.Count - 1 do
        WriteLine(UIYellow('  hint: ') + Hints[I]);
      exit;
    end;

    // The winners together, and with -dd.
    Combo := '';
    for I := 0 to Groups.Count - 1 do
      Combo := Combo + IfThen(Combo <> '', '+', '') +
        Trials[BestIdx[I]].Method;
    Final := nil;
    if Groups.Count > 1 then
      Insert(NewTrial(Combo, Combo, nil), Final, Length(Final));
    Insert(NewTrial(Combo + ' -dd', Combo, ['-dd']), Final, Length(Final));
    RunTrials(Final, Jobs, 'Trying the combination');
    for I := Low(Final) to High(Final) do
      with Final[I] do
        if Ok then
          Row(Name, Format('%d / %d', [Processed, Found]), UISize(OutSize),
            Pct(OutSize, Base.OutSize), Format('%.1f s', [Seconds]))
        else
          Row(Name, UIRed('failed'), '', '', '');

    // The smallest of: the best single codec, the combination, with -dd.
    Best := -1;
    BestSize := Base.OutSize;
    S := '';
    for I := 0 to Groups.Count - 1 do
      if Trials[BestIdx[I]].OutSize < BestSize then
      begin
        BestSize := Trials[BestIdx[I]].OutSize;
        S := Trials[BestIdx[I]].Method;
      end;
    for I := Low(Final) to High(Final) do
      if Final[I].Ok and (Final[I].OutSize < BestSize) then
      begin
        BestSize := Final[I].OutSize;
        Best := I;
      end;
    if Best >= 0 then
      S := Final[Best].Name;

    // Checked before it is recommended: the trial's .ytp decodes to the
    // input, byte for byte.
    Restored := WorkDir + 'restored.bin';
    if Best >= 0 then
      Combo := Final[Best].OutPath
    else
      for I := 1 to High(Trials) do
        if Trials[I].Method = S then
          Combo := Trials[I].OutPath;
    with TProcess.Create(nil) do
      try
        Executable := SelfExe;
        Parameters.Add('decode');
        Parameters.Add(ThreadsArg);
        Parameters.Add(Combo);
        Parameters.Add(Restored);
        Options := [poWaitOnExit, poNoConsole];
        Execute;
      finally
        Free;
      end;
    WriteLine('');
    WriteLine(UIBold('Recommended: ') + UICyan('ytool precomp -m' + S + ' ' +
      LevelArg + ' input output'));
    WriteLine(Format('  %s instead of %s with no codec (%s)%s',
      [UISize(BestSize), UISize(Base.OutSize), Pct(BestSize, Base.OutSize),
      IfThen(Sampled, ', on the samples', '')]));
    if SameContent(InputFile, Restored) then
      WriteLine(UIGreen('  checked: it decodes back byte for byte'))
    else
      WriteLine(UIRed('  its .ytp did not decode back to the input: ' +
        'please report this file'));
    for I := 0 to Hints.Count - 1 do
      WriteLine(UIYellow('  hint: ') + Hints[I]);
  finally
    for I := Low(Trials) to High(Trials) do
      if Assigned(Trials[I].Proc) then
        Trials[I].Proc.Free;
    for I := Low(Final) to High(Final) do
      if Assigned(Final[I].Proc) then
        Final[I].Proc.Free;
    RemoveWorkDir;
    Only.Free;
    Groups.Free;
    Hints.Free;
    Skipped.Free;
    Silent.Free;
  end;
end;

procedure PrintHelp;
begin
  WriteLine(UIBold('analyze') + ' - which -m to use on a file, measured');
  WriteLine('');
  WriteLine('Usage: ytool analyze [options] input');
  WriteLine('');
  WriteLine('  Tries each codec on input, several at once, and compares what you');
  WriteLine('  keep: the size after the final compressor (-l#) against no codec.');
  WriteLine('  Then the best codec of each kind together, with and without -dd,');
  WriteLine('  and recommends the smallest, after checking that it decodes back.');
  WriteLine('  Writes nothing. Files over 64 MB: 8 pieces from all over the file.');
  HelpSection('Examples');
  WriteLine('  ytool analyze game.pak');
  WriteLine('  ytool analyze -mzlib+preflate+zstd -l9 -full game.pak');
  HelpSection('Options');
  HelpOption('-m<codecs>', 'only these codecs, joined with +');
  HelpOption('-l#', 'final compressor level to compare with, 1-10',
    DefaultLevel.ToString);
  HelpOption('-full', 'the whole file, not samples');
  HelpOption('-t#', 'threads for each trial', 'a share of the CPUs');
  HelpOption('-v', 'also list the codecs that found no streams');
  WriteLine('');
end;

end.
