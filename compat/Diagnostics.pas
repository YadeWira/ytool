{ Shim de compatibilidad para System.Diagnostics de Delphi (no existe en FPC).
  Implementa TStopwatch sobre GetTickCount64 (multiplataforma en FPC).
  Superficie usada por xtool: Create/Start/Stop/IsRunning/Elapsed. }
unit Diagnostics;

interface

uses
  TimeSpan;

type
  TStopwatch = record
  private
    FStartTick: QWord;
    FElapsedMs: QWord;
    FRunning: Boolean;
    function GetElapsed: TTimeSpan;
    function GetIsRunning: Boolean;
  public
    class function Create: TStopwatch; static;
    procedure Start;
    procedure Stop;
    property Elapsed: TTimeSpan read GetElapsed;
    property IsRunning: Boolean read GetIsRunning;
  end;

implementation

uses
  SysUtils;

class function TStopwatch.Create: TStopwatch;
begin
  Result.FStartTick := 0;
  Result.FElapsedMs := 0;
  Result.FRunning := False;
end;

procedure TStopwatch.Start;
begin
  if not FRunning then
  begin
    FStartTick := GetTickCount64;
    FRunning := True;
  end;
end;

procedure TStopwatch.Stop;
begin
  if FRunning then
  begin
    Inc(FElapsedMs, GetTickCount64 - FStartTick);
    FRunning := False;
  end;
end;

function TStopwatch.GetElapsed: TTimeSpan;
var
  Ms: QWord;
begin
  Ms := FElapsedMs;
  if FRunning then
    Inc(Ms, GetTickCount64 - FStartTick);
  Result := TTimeSpan.FromMilliseconds(Ms);
end;

function TStopwatch.GetIsRunning: Boolean;
begin
  Result := FRunning;
end;

end.
