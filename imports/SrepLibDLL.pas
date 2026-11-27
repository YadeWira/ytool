unit SrepLibDLL;

// libsrep: srep (Bulat Ziganshin, "All rights reserved"; not shipped with
// ytool) as a library, built by github.com/YadeWira/srep-builds 3.97 or later
// (libsrep.so / srep.dll). When it sits next to ytool it is used instead of the
// srep program, even if that is there too: TProcessStream runs srep_run in
// this process through the same three pipes, so every caller of srep (encode,
// decode, files and pipes) works unchanged, with srep's own messages and exit
// codes. Without the library, the program is used as before.

interface

uses
  InitCode,
  Utils, LibImport, StrUtils,
{$IFDEF UNIX}
  BaseUnix,
{$ENDIF}
  SysUtils;

var
  srep_run: function(argc: Integer; argv: PPAnsiChar; in_handle, out_handle,
    err_handle: PtrInt): Integer cdecl;
  srep_version: function: PAnsiChar cdecl;

  DLLLoaded: Boolean = False;

// "SREP 3.97 (3.93a + ytool fixes)", or '' without the library
function SrepLibVersion: String;

implementation

var
  Lib: TLibImport;
  RunCount: Integer = 0;

function SrepLibVersion: String;
begin
  if DLLLoaded then
    Result := String(srep_version())
  else
    Result := '';
end;

function HasArg(const Args: TArray<String>; const Prefix: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(Args) to High(Args) do
    if Args[I].StartsWith(Prefix) then
      exit(True);
end;

function Run(const CommandLine, WorkDir: String;
  const Environment: TStringArray; InH, OutH, ErrH: THandle): Integer;
var
  Args: TArray<String>;
  Ansi: TArray<AnsiString>;
  Argv: TArray<PAnsiChar>;
  Dir, S: String;
  I, N: Integer;
begin
  Args := ['srep'];
  // the seed came in the environment for the program; the library takes it
  // as --seed= (the process environment is ytool's, shared by every thread)
  for I := Low(Environment) to High(Environment) do
    if Environment[I].StartsWith('SREP_SEED_HEX=') then
      Insert('--seed=' + Environment[I].Substring(14), Args, Length(Args));
  for I := 0 to GetCmdCount(CommandLine) - 1 do
  begin
    S := GetCmdStr(CommandLine, I);
    if S <> '' then
      Insert(S, Args, Length(Args));
  end;
  // The program ran in WorkDir, where srep's default scratch files went; the
  // library runs in ytool's directory, so they are named in WorkDir here.
  if WorkDir <> '' then
  begin
    Dir := IncludeTrailingPathDelimiter(WorkDir);
    N := InterLockedIncrement(RunCount);
    if not HasArg(Args, '-vmfile=') then
      Insert('-vmfile=' + Dir + 'srep-lib-vm' + N.ToString + '.tmp', Args, 1);
    if (IndexStr('-d', Args) >= 0) and not HasArg(Args, '-temp=') then
      Insert('-temp=' + Dir + 'srep-lib-data' + N.ToString + '.tmp', Args, 1);
  end;
  SetLength(Ansi, Length(Args));
  SetLength(Argv, Length(Args) + 1);
  for I := Low(Args) to High(Args) do
  begin
    Ansi[I] := AnsiString(Args[I]);
    Argv[I] := PAnsiChar(Ansi[I]);
  end;
  Argv[Length(Args)] := nil;
  Result := srep_run(Length(Args), @Argv[0], PtrInt(InH), PtrInt(OutH),
    PtrInt(ErrH));
end;

procedure Init(const Filename: String);
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(Filename, True));
  if not Lib.Loaded then
    exit;
  @srep_run := Lib.GetProcAddr('srep_run');
  @srep_version := Lib.GetProcAddr('srep_version');
  DLLLoaded := Assigned(srep_run) and Assigned(srep_version);
  if DLLLoaded then
  begin
    RegisterInProcess(['srep', 'srep64', 'srep.exe', 'srep64.exe'], @Run);
{$IFDEF UNIX}
    // srep now writes into ytool's own pipes: a reader that goes away must
    // be a write error, not a signal that ends ytool
    FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
{$ENDIF}
  end;
end;

initialization

{$IFDEF UNIX}
Init(PluginsPath + 'libsrep.so');
{$ELSE}
Init(PluginsPath + 'srep.dll');
{$ENDIF}

finalization

Lib.Free;

end.
