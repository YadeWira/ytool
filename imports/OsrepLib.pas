unit OsrepLib;

{ OSREP built into ytool (0.9.9f; docs/ROADMAP-1.0.0.md point 3).

  contrib/osrep holds OSREP's own embeddable unit (github.com/YadeWira/
  omega-srep, MIT; contrib/fetch-osrep-unit.sh). Its OsrepRunArgs runs one
  osrep command line in this process: the same options, bytes and exit codes
  as the osrep program, "-" bound to the handles given, messages to the error
  handle, and it never ends the process. Registered here as the in-process
  runner for "osrep", TProcessStream (common/Utils.pas) runs it through the
  same pipes as the program; an osrep program next to ytool is not needed,
  and not used. }

{$IFDEF FPC}
{$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Utils, osrep_cli;

const
  // osrep_cli.OsrepVersionText, e.g. "OSREP 0.0.19 (...)"
  Available = True;

function OsrepVersion: String;

implementation

function OsrepVersion: String;
begin
  Result := osrep_cli.OsrepVersionText;
end;

function Run(const CommandLine, WorkDir: String;
  const Environment: TStringArray; InH, OutH, ErrH: THandle): Integer;
var
  Args: array of String;
  S: String;
  I: Integer;
begin
  Args := nil;
  for I := 0 to GetCmdCount(CommandLine) - 1 do
  begin
    S := GetCmdStr(CommandLine, I);
    if S <> '' then
      Insert(S, Args, Length(Args));
  end;
  // closes the three handles before it returns, as the runner must
  Result := OsrepRunArgs(Args, PtrInt(InH), PtrInt(OutH), PtrInt(ErrH), True);
end;

initialization

RegisterInProcess(['osrep', 'osrep.exe', 'osrep64', 'osrep64.exe'], @Run);

end.
