{ MIT License

  Copyright (c) 2016-2023 Razor12911

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE. }

program ytool;

{$APPTYPE CONSOLE}
{$R *.res}
{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}
{$POINTERMATH ON}

uses
{$IFDEF USECMEM}
  cmem, // -dUSECMEM: C's malloc, so valgrind sees heap errors (debugging only)
{$ENDIF}
{$IFDEF UNIX}
  cthreads, // pthread thread driver; must come first (TThread/TTask)
{$ENDIF}
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils,
  StrUtils,
  Classes,
  Types,
  Math,
  IOUtils,
  SyncObjs,
  LibImport in 'common\LibImport.pas',
  Threading in 'common\Threading.pas',
  Utils in 'common\Utils.pas',
  WinLibcShim in 'contrib\WinLibcShim\WinLibcShim.pas',
  lz4lib in 'contrib\LZ4Delphi\lz4lib.pas',
  SynCommons in 'contrib\mORMot\SynCommons.pas',
  SynCrypto in 'contrib\mORMot\SynCrypto.pas',
  SynLZ in 'contrib\mORMot\SynLZ.pas',
  SynTable in 'contrib\mORMot\SynTable.pas',
  oobjects in 'contrib\ParseExpression\oobjects.pas',
  ParseClass in 'contrib\ParseExpression\ParseClass.pas',
  ParseExpr in 'contrib\ParseExpression\ParseExpr.pas',
  xxhashlib in 'contrib\XXHASH4Delphi\xxhashlib.pas',
  ZSTDLib in 'contrib\ZSTD4Delphi\ZSTDLib.pas',
  InitCode in 'InitCode.pas',
  BrunsliDLL in 'imports\BrunsliDLL.pas',
  FLACDLL in 'imports\FLACDLL.pas',
  FLZMA2DLL in 'imports\FLZMA2DLL.pas',
  LZ4DLL in 'imports\LZ4DLL.pas',
  LZODLL in 'imports\LZODLL.pas',
  OodleDLL in 'imports\OodleDLL.pas',
  PJADLL in 'imports\PJADLL.pas',
  WavPackDLL in 'imports\WavPackDLL.pas',
  PreflateDLL in 'imports\PreflateDLL.pas',
  ZLibDLL in 'imports\ZLibDLL.pas',
  ZSTDDLL in 'imports\ZSTDDLL.pas',
  LibDeflateDLL in 'imports\LibDeflateDLL.pas',
  LZlibDLL in 'imports\LZlibDLL.pas',
  SrepLibDLL in 'imports\SrepLibDLL.pas',
  lz4 in 'sources\lz4.pas',
  PrecompMain in 'precompressor\PrecompMain.pas',
  PrecompHelp in 'precompressor\PrecompHelp.pas',
  CliUI in 'common\CliUI.pas',
  PrecompUtils in 'precompressor\PrecompUtils.pas',
  PrecompCrypto in 'precompressor\PrecompCrypto.pas',
  PrecompZLib in 'precompressor\PrecompZLib.pas',
  PrecompLZ4 in 'precompressor\PrecompLZ4.pas',
  PrecompLZO in 'precompressor\PrecompLZO.pas',
  PrecompZSTD in 'precompressor\PrecompZSTD.pas',
  PrecompMedia in 'precompressor\PrecompMedia.pas',
  PrecompReserved in 'precompressor\PrecompReserved.pas',
  PrecompLZMA in 'precompressor\PrecompLZMA.pas',
  PrecompLZIP in 'precompressor\PrecompLZIP.pas',
  PrecompAnalyze in 'precompressor\PrecompAnalyze.pas',
  PrecompOodle in 'precompressor\PrecompOodle.pas',
  PrecompINI in 'precompressor\PrecompINI.pas',
  PrecompINIEx in 'precompressor\PrecompINIEx.pas',
  PrecompSearch in 'precompressor\PrecompSearch.pas',
  PrecompDLL in 'precompressor\PrecompDLL.pas',
  PrecompEXE in 'precompressor\PrecompEXE.pas',
  DbgMain in 'dbgenerator\DbgMain.pas',
  DbgUtils in 'dbgenerator\DbgUtils.pas',
  IOFind in 'io\IOFind.pas',
  IOErase in 'io\IOErase.pas',
  IOReplace in 'io\IOReplace.pas',
  IOExecute in 'io\IOExecute.pas',
  IODecode in 'io\IODecode.pas',
  IOCommon in 'io\IOCommon.pas';

{$IFDEF MSWINDOWS}
// FPC: the {$SETPEFLAGS} evaluator does not resolve unit constants; we use the
// numeric value = LARGE_ADDRESS_AWARE($20) or RELOCS_STRIPPED($01) or DEBUG_STRIPPED($200).
{$SETPEFLAGS $221}
{$ENDIF}

const
  CommandPrecomp = 'precomp';
  CommandGenerate = 'generate';
  CommandFind = 'find';
  CommandErase = 'erase';
  CommandReplace = 'replace';
  CommandExtract = 'extract';
  CommandExecute = 'execute';
  CommandDecode = 'decode';
  CommandAnalyze = 'analyze';
  YTOOL_VERSION = '0.9.9f';

// 0.9.9d: a mistyped command ("analyce") printed the banner and exited 0
// with nothing done. Known commands match by prefix, as before.
function KnownCommand(const S: String): Boolean;
begin
  Result := S.StartsWith(CommandPrecomp, True) or
    S.StartsWith(CommandGenerate, True) or S.StartsWith(CommandFind, True) or
    S.StartsWith(CommandErase, True) or S.StartsWith(CommandReplace, True) or
    S.StartsWith(CommandExtract, True) or S.StartsWith(CommandExecute, True) or
    S.StartsWith(CommandDecode, True) or S.StartsWith(CommandAnalyze, True);
end;

function EditDistance(const A, B: String): Integer;
var
  D: array of array of Integer;
  I, J: Integer;
begin
  SetLength(D, Length(A) + 1, Length(B) + 1);
  for I := 0 to Length(A) do
    D[I, 0] := I;
  for J := 0 to Length(B) do
    D[0, J] := J;
  for I := 1 to Length(A) do
    for J := 1 to Length(B) do
      D[I, J] := Min(Min(D[I - 1, J] + 1, D[I, J - 1] + 1),
        D[I - 1, J - 1] + Ord(LowerCase(A[I]) <> LowerCase(B[J])));
  Result := D[Length(A), Length(B)];
end;

// 0.9.9e: options are read by prefix and an unknown one was ignored without a
// word ("decode -zzz", "analyze -q"). A warning, not an error: by the first
// letter after the dash, as the parser itself matches them.
procedure WarnUnknownOptions(const Opts: TArray<String>);
var
  Cmd, Known, O: String;
begin
  Cmd := ParamStr(1);
  if Cmd.StartsWith(CommandPrecomp, True) then
    Known := 'bcdeflmoprstTvxX'
  else if Cmd.StartsWith(CommandDecode, True) then
    Known := 'bdemopstTv'
  else if Cmd.StartsWith(CommandAnalyze, True) then
    Known := 'flmtv'
  else if Cmd.StartsWith(CommandGenerate, True) then
    Known := 'cmt'
  else if Cmd.StartsWith(CommandExtract, True) then
    Known := ''
  else
    Known := 'ct';
  for O in Opts do
    if (Length(O) < 2) or (Pos(O[2], Known) = 0) then
      WriteLine('warning: ' + O + ' is not an option of ' + LowerCase(Cmd) +
        ': ignored');
end;

// the closest command within 2 edits, or ''
function ClosestCommand(const S: String): String;
const
  Names: array [0 .. 8] of String = (CommandPrecomp, CommandDecode,
    CommandAnalyze, CommandGenerate, CommandFind, CommandErase, CommandReplace,
    CommandExtract, CommandExecute);
var
  I, D, Best: Integer;
begin
  Result := '';
  Best := 3;
  for I := Low(Names) to High(Names) do
  begin
    D := EditDistance(S, Names[I]);
    if D < Best then
    begin
      Best := D;
      Result := Names[I];
    end;
  end;
end;

procedure ProgramInfo;
begin
  WriteLine(UIBold('ytool ' + YTOOL_VERSION) +
    ' - open-source recreation of xtool, by YadeWira');
  WriteLine('');
end;

procedure ListCommands;

  procedure Cmd(const Name, Text: string);
  begin
    WriteLine('  ' + UIPad(UICyan(Name), 10) + ' ' + Text);
  end;

begin
  WriteLine('Usage: ytool <command> [options] <files>');
  HelpSection('Commands');
  Cmd(CommandPrecomp, 'find compressed streams and unpack them into a .ytp file');
  Cmd(CommandDecode, 'rebuild the original from a .ytp file, byte for byte');
  Cmd(CommandAnalyze, 'try each codec on a file and recommend a -m combination');
  Cmd(CommandGenerate, 'build a database of known streams, a codec for precomp');
  Cmd(CommandFind, 'find where some files sit inside a bigger one');
  Cmd(CommandExtract, 'copy out the files a map from find points to');
  Cmd(CommandErase, 'blank out those files inside the bigger one');
  Cmd(CommandReplace, 'swap those files for new versions');
  Cmd(CommandExecute, 'run a program on chunks of a file, in parallel');
  HelpSection('Examples');
  WriteLine('  ytool precomp -mzlib+zstd+pja game.pak game.ytp');
  WriteLine('  ytool decode game.ytp game.pak');
  WriteLine('');
  WriteLine('''ytool help <command>'' or ''ytool <command> -h'' shows its options;');
  WriteLine('''ytool --version'' prints the version.');
  WriteLine('');
end;

function IsHelpFlag(const S: string): Boolean;
begin
  Result := (S = '-h') or (S = '--help') or (S = '-help') or (S = '/?');
end;

// Help of one command, matched by prefix like the commands themselves.
// False when Name is no command.
function CommandHelp(const Name: string): Boolean;
begin
  Result := True;
  if Name.StartsWith(CommandPrecomp, True) then
    PrecompMain.PrintHelp
  else if Name.StartsWith(CommandDecode, True) then
    PrecompHelp.DecodePrintHelp
  else if Name.StartsWith(CommandAnalyze, True) then
    PrecompAnalyze.PrintHelp
  else if Name.StartsWith(CommandGenerate, True) then
    DbgMain.PrintHelp
  else if Name.StartsWith(CommandFind, True) then
    IOFind.PrintHelp
  else if Name.StartsWith(CommandErase, True) then
    IOErase.PrintHelp
  else if Name.StartsWith(CommandReplace, True) then
    IOReplace.PrintHelp
  else if Name.StartsWith(CommandExtract, True) then
    IODecode.PrintHelpExtract
  else if Name.StartsWith(CommandExecute, True) then
    IOExecute.PrintHelp
  else
    Result := False;
end;

// A precomp or decode that failed leaves no output behind: a half-written
// .ytp (or restored file) looks like a result to whoever does not check the
// exit code. Only a file it created: never stdout ("-") or a directory.
procedure DropOutput(const Path: string);
begin
  if (Path <> '') and (Path <> '-') and FileExists(Path) and
    not DirectoryExists(Path) then
    DeleteFile(Path);
end;

// Size of the input file and the stream to read its position from, for the
// progress line. Nothing for stdin, a URL or a directory.
procedure SetProgressInput(Stream: TStream);
begin
  PrecompMain.UIInputTotal := 0;
  PrecompMain.UIInputStream := nil;
  if (Stream is TBufferedStream) and
    (TBufferedStream(Stream).Instance is TFileStream) then
  begin
    PrecompMain.UIInputStream := TBufferedStream(Stream).Instance;
    try
      PrecompMain.UIInputTotal := PrecompMain.UIInputStream.Size;
    except
      PrecompMain.UIInputTotal := 0;
    end;
  end;
end;

function GetInStream(Input: string): TStream;
begin
  if (Input = '-') or (Input = '') then
    Result := THandleStream.Create({$IFDEF MSWINDOWS}GetStdHandle(STD_INPUT_HANDLE){$ELSE}StdInputHandle{$ENDIF})
  else if Pos('://', Input) > 0 then
    Result := TDownloadStream.Create(Input)
  else if FileExists(Input) then
    Result := TFileStream.Create(Input, fmShareDenyNone)
  else if DirectoryExists(Input) or (Pos('*', Input) > 0) or
    (Pos('?', Input) > 0) then
    Result := TDirInputStream.Create(Input)
  else
    // 0.9.9e: a missing file was opened as an empty folder listing
    raise EFOpenError.CreateFmt('input not found: %s', [Input]);
end;

function GetOutStream(Output: string): TStream;
begin
  if (Output = '') then
  begin
    // 0.9.9e: said nothing; "precomp in" looked like it had written something
    WriteLine('note: no output file given: the result is discarded (a test ' +
      'run; "-" writes to stdout)');
    Result := TNullStream.Create;
  end
  else if DirectoryExists(Output) then
    Result := TDirOutputStream.Create(Output)
  else if (Output = '-') then
    Result := THandleStream.Create({$IFDEF MSWINDOWS}GetStdHandle(STD_OUTPUT_HANDLE){$ELSE}StdOutputHandle{$ENDIF})
  else
    Result := TFileStream.Create(Output, fmCreate);
end;

{$IFDEF MSWINDOWS}
function CheckInstance(const InstanceName: string): boolean;
var
  Sem: THandle;
begin
  Result := False;
  Sem := CreateSemaphore(nil, 0, 1, PChar(InstanceName));
  if ((Sem <> 0) and (GetLastError = ERROR_ALREADY_EXISTS)) then
  begin
    CloseHandle(Sem);
    exit(True);
  end;
end;
{$ENDIF}

const
  BufferSize = 4194034;

var
  I, J: Integer;
  ParamArg: array [0 .. 1] of TArray<String>;
  StrArray: TArray<String>;
  IsParam: boolean;
  T: String;
  Input, Output: TStream;
  PrecompEnc: PrecompMain.TEncodeOptions;
  PrecompDec: PrecompMain.TDecodeOptions;
  GenerateEnc: DbgMain.TEncodeOptions;
  FindEnc: IOFind.TEncodeOptions;
  EraseEnc: IOErase.TEncodeOptions;
  ReplaceEnc: IOReplace.TEncodeOptions;
  ExecuteEnc: IOExecute.TEncodeOptions;
  ExecuteDec: IOExecute.TDecodeOptions;
  IODec: IODecode.TDecodeOptions;
  IOExt: IODecode.TExtractOptions;

function ParamArgSafe(I, J: Integer): String;
begin
  Result := '';
  if InRange(I, 0, Pred(Length(ParamArg))) then
    if InRange(J, 0, Pred(Length(ParamArg[I]))) then
      Result := ParamArg[I, J];
end;

function PrecompEncodePatch2(Instance: Integer; OldBuff: Pointer;
  OldSize: Integer; NewBuff: Pointer; NewSize: Integer;
  Output: _PrecompOutput): Integer;

  function highbit64(V: UInt64): Cardinal;
  var
    Count: Cardinal;
  begin
    Count := 0;
    Assert(V <> 0);
    V := V shr 1;
    while V <> 0 do
    begin
      V := V shr 1;
      Inc(Count);
    end;
    Result := Count;
  end;

var
  Buffer: Pointer;
  BufferSize: Integer;
  Ctx: ZSTD_CCtx;
  Inp: ZSTDLib.ZSTD_inBuffer;
  Oup: ZSTDLib.ZSTD_outBuffer;
  Res: NativeInt;

  procedure DoWrite;
  begin
    Output(Instance, Buffer, Oup.Pos);
    Inc(Result, Oup.Pos);
    Oup.dst := Buffer;
    Oup.Size := BufferSize;
    Oup.Pos := 0;
  end;

begin
  Result := 0;
  BufferSize := ZSTDLib.ZSTD_CStreamOutSize;
  GetMem(Buffer, BufferSize);
  Ctx := ZSTDLib.ZSTD_createCCtx;
  try
    Oup.dst := Buffer;
    Oup.Size := BufferSize;
    Oup.Pos := 0;
    Inp.src := OldBuff;
    Inp.Size := OldSize;
    Inp.Pos := 0;
    ZSTDLib.ZSTD_initCStream(Ctx, 1);
    ZSTDLib.ZSTD_CCtx_setParameter(Ctx,
      ZSTDLib.ZSTD_cParameter.ZSTD_c_windowLog, highbit64(NewSize) + 1);
    ZSTDLib.ZSTD_CCtx_setParameter(Ctx,
      ZSTDLib.ZSTD_cParameter.ZSTD_c_enableLongDistanceMatching, 1);
    ZSTDLib.ZSTD_CCtx_refPrefix(Ctx, NewBuff, NewSize);
    while Inp.Pos < Inp.Size do
    begin
      Res := ZSTDLib.ZSTD_compressStream(Ctx, Oup, Inp);
      if Res < 0 then
        exit(0)
      else if Res > 0 then
        DoWrite
      else
        break;
    end;
    ZSTDLib.ZSTD_flushStream(Ctx, Oup);
    DoWrite;
    ZSTDLib.ZSTD_endStream(Ctx, Oup);
    DoWrite;
  finally
    ZSTDLib.ZSTD_freeCCtx(Ctx);
  end;
end;

function PrecompDecodePatch2(Instance: Integer; PatchBuff: Pointer;
  PatchSize: Integer; OldBuff: Pointer; OldSize: Integer;
  Output: _PrecompOutput): Integer;

  function highbit64(V: UInt64): Cardinal;
  var
    Count: Cardinal;
  begin
    Count := 0;
    Assert(V <> 0);
    V := V shr 1;
    while V <> 0 do
    begin
      V := V shr 1;
      Inc(Count);
    end;
    Result := Count;
  end;

var
  Buffer: Pointer;
  BufferSize: Integer;
  Ctx: ZSTD_DCtx;
  Inp: ZSTDLib.ZSTD_inBuffer;
  Oup: ZSTDLib.ZSTD_outBuffer;
  Res: NativeInt;

  procedure DoWrite;
  begin
    Output(Instance, Buffer, Oup.Pos);
    Inc(Result, Oup.Pos);
    Oup.dst := Buffer;
    Oup.Size := BufferSize;
    Oup.Pos := 0;
  end;

begin
  Result := 0;
  BufferSize := ZSTDLib.ZSTD_DStreamOutSize;
  GetMem(Buffer, BufferSize);
  Ctx := ZSTDLib.ZSTD_createDCtx;
  try
    Oup.dst := Buffer;
    Oup.Size := BufferSize;
    Oup.Pos := 0;
    Inp.src := PatchBuff;
    Inp.Size := PatchSize;
    Inp.Pos := 0;
    ZSTDLib.ZSTD_initDStream(Ctx);
    ZSTDLib.ZSTD_DCtx_setParameter(Ctx,
      ZSTDLib.ZSTD_dParameter.ZSTD_d_windowLogMax, highbit64(OldSize) + 1);
    ZSTDLib.ZSTD_DCtx_refPrefix(Ctx, OldBuff, OldSize);
    while Inp.Pos < Inp.Size do
    begin
      Res := ZSTDLib.ZSTD_decompressStream(Ctx, Oup, Inp);
      if Res < 0 then
        exit(0)
      else if Res > 0 then
        DoWrite
      else
        break;
    end;
  finally
    ZSTDLib.ZSTD_freeDCtx(Ctx);
  end;
end;

var
  MS1, MS2, MS3, MS4: TMemoryStream;

procedure ExecOutput1(Instance: Integer; const Buffer: Pointer;
  Size: Integer)cdecl;
begin
  MS3.WriteBuffer(Buffer^, Size);
end;

procedure ExecOutput2(Instance: Integer; const Buffer: Pointer;
  Size: Integer)cdecl;
begin
  MS4.WriteBuffer(Buffer^, Size);
end;

begin
  { try
    MS1 := TMemoryStream.Create;
    MS2 := TMemoryStream.Create;
    MS3 := TMemoryStream.Create;
    MS4 := TMemoryStream.Create;
    MS1.LoadFromFile('UI.sb');
    MS2.LoadFromFile('UI.sb.out');
    MS4.Size := MS1.Size;
    MS3.Size := PrecompEncodePatch2(0, MS1.Memory, MS1.Size, MS2.Memory,
    MS2.Size, ExecOutput1);
    MS3.SaveToFile('UI.sb.diff');
    MS4.Size := PrecompDecodePatch2(0, MS3.Memory, MS3.Size, MS2.Memory,
    MS2.Size, ExecOutput2);
    MS4.SaveToFile('UI.sb.res');
    except
    on E: Exception do
    ShowMessage(E.Message);
    end;
    ShowMessage('');
    exit; }
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';
  FormatSettings.ThousandSeparator := ',';
  if (ParamCount = 1) and MatchStr(ParamStr(1), ['--version', '-version',
    '-V', '-v', 'version'])
  then
  begin
    // Deliberately System.Output (stdout), not WriteLine (stderr, by design --
    // see WriteLine's own comment): unlike every other status message, a
    // version flag's whole point is to be captured by scripts/tooling, e.g.
    // `x=$(ytool --version)`, which expects stdout by convention.
    WriteLn(System.Output, YTOOL_VERSION);
    exit;
  end;
  ProgramInfo;
  try
    if (ParamCount = 0) or (IsHelpFlag(ParamStr(1)) and (ParamCount = 1)) then
    begin
      ListCommands;
      exit;
    end;
    // ytool help <command>, ytool -h <command>, ytool <command> -h
    if SameText(ParamStr(1), 'help') or IsHelpFlag(ParamStr(1)) then
    begin
      if (ParamCount < 2) or not CommandHelp(ParamStr(2)) then
      begin
        if ParamCount >= 2 then
          WriteLine(UIRed('Unknown command: ') + ParamStr(2) + sLineBreak);
        ListCommands;
      end;
      exit;
    end;
    for I := 2 to ParamCount do
      if IsHelpFlag(ParamStr(I)) and CommandHelp(ParamStr(1)) then
        exit;
    if not KnownCommand(ParamStr(1)) then
    begin
      T := ClosestCommand(ParamStr(1));
      if T <> '' then
        T := ' (did you mean ' + T + '?)';
      WriteLine(UIRed('Unknown command: ') + ParamStr(1) + T + sLineBreak);
      ListCommands;
      ExitCode := 1;
      exit;
    end;
    IsParam := True;
    for I := 2 to ParamCount do
    begin
      // 0.9.9e: an option starts with '-'. A file name that did not exist
      // ("nofile.bin") was taken for an option: precomp read stdin and wrote
      // nothing with exit 0, decode said "Stream read error".
      // options after the file names were taken for file names and ignored
      // ("precomp in out -mzlib" found nothing). Anywhere now, except for
      // decode and execute, whose trailing arguments can be a program's own
      // command line.
      // "-r zstd": the value goes attached ("-rzstd"); detached it was
      // dropped without a word (0.9.9e: say so instead of guessing)
      if (I > 2) and not ParamStr(I).StartsWith('-') and
        MatchStr(ParamStr(I - 1), ['-m', '-c', '-t', '-T', '-d', '-l', '-p',
        '-x', '-X', '-e', '-r']) and (FileExists(ParamStr(I)) = False) and
        (DirectoryExists(ParamStr(I)) = False) and
        (Pos('*', ParamStr(I)) = 0) and (Pos('://', ParamStr(I)) = 0) then
        raise Exception.CreateFmt('%s takes its value attached: %s%s',
          [ParamStr(I - 1), ParamStr(I - 1), ParamStr(I)]);
      if ((IsParam = True) or not (ParamStr(1).StartsWith(CommandDecode, True)
        or ParamStr(1).StartsWith(CommandExecute, True))) and
        ParamStr(I).StartsWith('-') and
        (FileExists(ParamStr(I)) = False) and
        (DirectoryExists(ParamStr(I)) = False) and (Pos('://', ParamStr(I)) = 0)
        and (Pos('*', ParamStr(I)) = 0) and (ParamStr(I) <> '-') then
        J := 0
      else
      begin
        J := 1;
        IsParam := False;
      end;
      Insert(ParamStr(I), ParamArg[J], Length(ParamArg[J]));
    end;
    WarnUnknownOptions(ParamArg[0]);
    if ParamStr(1).StartsWith(CommandPrecomp, True) then
      if (Length(ParamArg[0]) = 0) and (Length(ParamArg[1]) = 0) then
        PrecompMain.PrintHelp
      else
      begin
        Input := TBufferedStream.Create(GetInStream(ParamArgSafe(1, 0)), True,
          BufferSize);
        SetProgressInput(Input);
        // -scan (detect-only, no output) is checked here, raw, before
        // GetOutStream: that call's fmCreate truncates whatever real path
        // the caller passed immediately on open, before Encode ever runs --
        // opening a real file at all (even one that ends up unwritten)
        // would already have destroyed its previous contents.
        if MatchStr('-scan', ParamArg[0]) then
          Output := TBufferedStream.Create(TNullStream.Create, False,
            BufferSize)
        else
          Output := TBufferedStream.Create(GetOutStream(ParamArgSafe(1, 1)),
            False, BufferSize);
        // as xtool 0.9.9 does, before the stats
        WriteLine('Processing input: ' + ParamArgSafe(1, 0));
        WriteLine('');
        try
          try
            PrecompMain.Parse(ParamArg[0], PrecompEnc);
            PrecompMain.Encode(Input, Output, PrecompEnc);
          finally
            Input.Free;
            Output.Free;
          end;
        except
          if not MatchStr('-scan', ParamArg[0]) then
            DropOutput(ParamArgSafe(1, 1));
          raise;
        end;
      end;
    if ParamStr(1).StartsWith(CommandAnalyze, True) then
      if Length(ParamArg[1]) < 1 then
        PrecompAnalyze.PrintHelp
      else
        PrecompAnalyze.RunAnalyze(ParamArg[1, 0], ParamArg[0]);
    if ParamStr(1).StartsWith(CommandGenerate, True) then
      if Length(ParamArg[1]) < 3 then
        DbgMain.PrintHelp
      else
      begin
        DbgMain.Parse(ParamArg[0], GenerateEnc);
        DbgMain.Encode(ParamArg[1, 0], ParamArg[1, 1], ParamArg[1, 2],
          GenerateEnc);
      end;
    if ParamStr(1).StartsWith(CommandFind, True) then
      if Length(ParamArg[1]) < 2 then
        IOFind.PrintHelp
      else
      begin
        IOFind.Parse(ParamArg[0], FindEnc);
        IOFind.Encode(ParamArg[1, 0], ParamArg[1, 1],
          ParamArgSafe(1, 2), FindEnc);
      end;
    if ParamStr(1).StartsWith(CommandErase, True) then
      if Length(ParamArg[1]) < 2 then
        IOErase.PrintHelp
      else
      begin
        IOErase.Parse(ParamArg[0], EraseEnc);
        IOErase.Encode(ParamArg[1, 0], ParamArg[1, 1], ParamArgSafe(1, 2),
          EraseEnc);
      end;
    if ParamStr(1).StartsWith(CommandReplace, True) then
      if Length(ParamArg[1]) < 3 then
        IOReplace.PrintHelp
      else
      begin
        IOReplace.Parse(ParamArg[0], ReplaceEnc);
        IOReplace.Encode(ParamArg[1, 0], ParamArg[1, 1], ParamArg[1, 2],
          ParamArgSafe(1, 3), ReplaceEnc);
      end;
    if ParamStr(1).StartsWith(CommandExtract, True) then
      if (Length(ParamArg[0]) = 0) and (Length(ParamArg[1]) = 0) then
        IODecode.PrintHelpExtract
      else
      begin
        Input := TBufferedStream.Create(GetInStream(ParamArgSafe(1, 0)), True,
          BufferSize);
        try
          Input.ReadBuffer(I, I.Size);
          case I of
            YTOOL_IODEC:
              begin
                IODecode.ParseExtract(ParamArg[0], IOExt);
                IODecode.Extract(Input, ParamArgSafe(1, 1),
                  ParamArgSafe(1, 2), IOExt);
              end;
          end;
        finally
          Input.Free;
        end;
      end;
    if ParamStr(1).StartsWith(CommandExecute, True) then
      if (Length(ParamArg[0]) = 0) and (Length(ParamArg[1]) = 0) then
        IOExecute.PrintHelp
      else
      begin
        SetLength(StrArray, 0);
        for I := 2 to High(ParamArg[1]) do
          Insert(ParamArg[1, I], StrArray, Length(StrArray));
        Input := TBufferedStream.Create(GetInStream(ParamArg[1, 0]), True,
          BufferSize);
        Output := TBufferedStream.Create(GetOutStream(ParamArg[1, 1]), False,
          BufferSize);
        try
          IOExecute.Parse(ParamArg[0], ExecuteEnc);
          IOExecute.Encode(Input, Output, StrArray, ExecuteEnc);
        finally
          Input.Free;
          Output.Free;
        end;
      end;
    if ParamStr(1).StartsWith(CommandDecode, True) then
      if (Length(ParamArg[0]) = 0) and (Length(ParamArg[1]) = 0) then
        PrecompHelp.DecodePrintHelp
      else
      begin
        Input := TBufferedStream.Create(GetInStream(ParamArgSafe(1, 0)), True,
          BufferSize);
        SetProgressInput(Input);
        try
          Input.ReadBuffer(I, I.Size);
          case I of
            YTOOL_PRECOMP, YTOOL_PRECOMP2:
              begin
                // XTP2 blocks carry a hash of their literal data; XTP1 do not
                PrecompMain.LITHASH := I = YTOOL_PRECOMP2;
                for J := 2 to High(ParamArg[1]) do
                  WriteLine('warning: ' + ParamArg[1, J] + ' ignored: decode' +
                    ' takes input and output, options go before them');
                Output := TBufferedStream.Create(GetOutStream(ParamArgSafe(1, 1)
                  ), False, BufferSize);
                PrecompMain.UIOutputStream := Output;
                WriteLine('Processing input: ' + ParamArgSafe(1, 0));
                WriteLine('');
                try
                  try
                    PrecompMain.Parse(ParamArg[0], PrecompDec);
                    PrecompMain.Decode(Input, Output, PrecompDec);
                  finally
                    Output.Free;
                  end;
                except
                  DropOutput(ParamArgSafe(1, 1));
                  raise;
                end;
              end;
            YTOOL_IODEC:
              begin
                IODecode.ParseDecode(ParamArg[0], IODec);
                IODecode.Decode(Input, ParamArg[1, 1], ParamArg[1, 2], IODec);
              end;
            YTOOL_EXEC:
              begin
                SetLength(StrArray, 0);
                for I := 2 to High(ParamArg[1]) do
                  Insert(ParamArg[1, I], StrArray, Length(StrArray));
                Output := TBufferedStream.Create(GetOutStream(ParamArgSafe(1, 1)
                  ), False, BufferSize);
                try
                  IOExecute.Parse(ParamArg[0], ExecuteDec);
                  IOExecute.Decode(Input, Output, StrArray, ExecuteDec);
                finally
                  Output.Free;
                end;
              end;
          else
            raise Exception.CreateFmt(
              'Unrecognized .ytp format (bad magic: $%.8x)', [I]);
          end;
        finally
          Input.Free;
        end;
      end;
  except
    on E: Exception do
    begin
      WriteLine(E.ClassName + ': ' + E.Message);
      // A decode through srep that stops early shows up here as a read
      // error; srep's own line says why.
      if Assigned(PrecompMain.SrepDecodeErr) and
        (Pos(' failed while ', E.Message) = 0) then
      begin
        I := Pos('ERROR!', PrecompMain.SrepDecodeErr.DataString);
        if I = 0 then
          I := Pos('OSREP:', PrecompMain.SrepDecodeErr.DataString);
        if I > 0 then
          WriteLine('dedup: ' + Trim(Copy(PrecompMain.SrepDecodeErr.DataString,
            I, 300)));
      end;
      if DEBUG then
        ShowMessage(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;

end.
