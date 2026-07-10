unit Threading;

interface

uses
  SysUtils, Classes, SyncObjs;

type
  TThreadStatus = (tsReady, tsRunning, tsErrored, tsTerminated);

  EThreadException = class(Exception);

  { Punteros a procedimiento. En FPC 3.2.2 no hay metodos anonimos / function
    references (TProc); los trabajos se pasan como procedimientos globales con
    nombre (TTaskProcN) o como metodos (TTaskMethodN). El contexto que antes
    capturaban los closures se obtiene de variables a nivel de unidad. }
  TTaskProc0 = procedure;
  TTaskProc1 = procedure(Arg1: IntPtr);
  TTaskProc2 = procedure(Arg1, Arg2: IntPtr);
  TTaskProc3 = procedure(Arg1, Arg2, Arg3: IntPtr);
  TTaskProc4 = procedure(Arg1, Arg2, Arg3, Arg4: IntPtr);
  TTaskMethod0 = procedure of object;
  TTaskMethod1 = procedure(Arg1: IntPtr) of object;
  TTaskMethod2 = procedure(Arg1, Arg2: IntPtr) of object;
  TTaskMethod3 = procedure(Arg1, Arg2, Arg3: IntPtr) of object;
  TTaskMethod4 = procedure(Arg1, Arg2, Arg3, Arg4: IntPtr) of object;

  TTask = class(TThread)
  private
    FSync: Boolean;
    FErrorMsg: string;
    FStatus: TThreadStatus;
    { FStatus doubles as both the ready/running/errored signal AND the
      implicit memory fence for whatever the worker wrote before the
      transition (buffer contents, InfoStore entries, etc.) -- without a
      real synchronization primitive, the main thread reading FStatus isn't
      guaranteed to see the worker's writes that happened-before it, nor is
      it guaranteed to see FStatus itself promptly. FLock provides both the
      visibility guarantee and mutual exclusion. }
    FLock: TCriticalSection;
    FProc0: TTaskProc0;
    FProc1: TTaskProc1;
    FProc2: TTaskProc2;
    FProc3: TTaskProc3;
    FProc4: TTaskProc4;
    FMth0: TTaskMethod0;
    FMth1: TTaskMethod1;
    FMth2: TTaskMethod2;
    FMth3: TTaskMethod3;
    FMth4: TTaskMethod4;
    FArgs: array [0 .. 3] of IntPtr;
    FStarted: Boolean;
    function GetStatus: TThreadStatus;
    procedure SetStatus(Value: TThreadStatus);
    procedure ClearProcs;
    function HasProc: Boolean;
    procedure RunProc;
  public
    constructor Create(Arg1: IntPtr = 0; Arg2: IntPtr = 0; Arg3: IntPtr = 0;
      Arg4: IntPtr = 0);
    destructor Destroy; override;
    procedure Update(Arg1: IntPtr = 0; Arg2: IntPtr = 0; Arg3: IntPtr = 0;
      Arg4: IntPtr = 0);
    procedure Perform(const Proc: TTaskProc0); overload;
    procedure Perform(const Proc: TTaskProc1); overload;
    procedure Perform(const Proc: TTaskProc2); overload;
    procedure Perform(const Proc: TTaskProc3); overload;
    procedure Perform(const Proc: TTaskProc4); overload;
    procedure Perform(const Proc: TTaskMethod0); overload;
    procedure Perform(const Proc: TTaskMethod1); overload;
    procedure Perform(const Proc: TTaskMethod2); overload;
    procedure Perform(const Proc: TTaskMethod3); overload;
    procedure Perform(const Proc: TTaskMethod4); overload;
    procedure Execute; override;
    procedure Start;
    procedure Wait;
    procedure RaiseLastError;
    property Status: TThreadStatus read GetStatus;
    property Sync: Boolean read FSync write FSync;
  end;

procedure WaitForAll(const Tasks: array of TTask);
function WaitForAny(const Tasks: array of TTask): Integer;
function IsErrored(const Tasks: array of TTask): Boolean;

implementation

constructor TTask.Create(Arg1, Arg2, Arg3, Arg4: IntPtr);
begin
  inherited Create(True);
  FLock := TCriticalSection.Create;
  FSync := False;
  FErrorMsg := '';
  FStatus := tsReady;
  ClearProcs;
  FArgs[0] := Arg1;
  FArgs[1] := Arg2;
  FArgs[2] := Arg3;
  FArgs[3] := Arg4;
  FStarted := False;
end;

destructor TTask.Destroy;
begin
  SetStatus(tsTerminated);
  inherited Destroy;
  FLock.Free;
end;

function TTask.GetStatus: TThreadStatus;
begin
  FLock.Enter;
  try
    Result := FStatus;
  finally
    FLock.Leave;
  end;
end;

procedure TTask.SetStatus(Value: TThreadStatus);
begin
  FLock.Enter;
  try
    FStatus := Value;
  finally
    FLock.Leave;
  end;
end;

procedure TTask.Update(Arg1, Arg2, Arg3, Arg4: IntPtr);
begin
  FArgs[0] := Arg1;
  FArgs[1] := Arg2;
  FArgs[2] := Arg3;
  FArgs[3] := Arg4;
end;

procedure TTask.ClearProcs;
begin
  FProc0 := nil;
  FProc1 := nil;
  FProc2 := nil;
  FProc3 := nil;
  FProc4 := nil;
  FMth0 := nil;
  FMth1 := nil;
  FMth2 := nil;
  FMth3 := nil;
  FMth4 := nil;
end;

procedure TTask.Perform(const Proc: TTaskProc0);
begin
  ClearProcs;
  FProc0 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskProc1);
begin
  ClearProcs;
  FProc1 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskProc2);
begin
  ClearProcs;
  FProc2 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskProc3);
begin
  ClearProcs;
  FProc3 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskProc4);
begin
  ClearProcs;
  FProc4 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskMethod0);
begin
  ClearProcs;
  FMth0 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskMethod1);
begin
  ClearProcs;
  FMth1 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskMethod2);
begin
  ClearProcs;
  FMth2 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskMethod3);
begin
  ClearProcs;
  FMth3 := Proc;
end;

procedure TTask.Perform(const Proc: TTaskMethod4);
begin
  ClearProcs;
  FMth4 := Proc;
end;

function TTask.HasProc: Boolean;
begin
  Result := Assigned(FProc0) or Assigned(FProc1) or Assigned(FProc2) or
    Assigned(FProc3) or Assigned(FProc4) or Assigned(FMth0) or Assigned(FMth1)
    or Assigned(FMth2) or Assigned(FMth3) or Assigned(FMth4);
end;

procedure TTask.RunProc;
begin
  if Assigned(FProc0) then
    FProc0
  else if Assigned(FProc1) then
    FProc1(FArgs[0])
  else if Assigned(FProc2) then
    FProc2(FArgs[0], FArgs[1])
  else if Assigned(FProc3) then
    FProc3(FArgs[0], FArgs[1], FArgs[2])
  else if Assigned(FProc4) then
    FProc4(FArgs[0], FArgs[1], FArgs[2], FArgs[3])
  else if Assigned(FMth0) then
    FMth0
  else if Assigned(FMth1) then
    FMth1(FArgs[0])
  else if Assigned(FMth2) then
    FMth2(FArgs[0], FArgs[1])
  else if Assigned(FMth3) then
    FMth3(FArgs[0], FArgs[1], FArgs[2])
  else if Assigned(FMth4) then
    FMth4(FArgs[0], FArgs[1], FArgs[2], FArgs[3]);
end;

procedure TTask.Execute;
label
  Restart;
begin
Restart:
  while GetStatus in [tsReady, tsErrored] do
    Sleep(1);
  try
    if GetStatus = tsRunning then
    begin
      if HasProc then
      begin
        if FSync then
          Self.Synchronize(RunProc)
        else
          RunProc;
      end;
      SetStatus(tsReady);
    end;
  except
    on E: Exception do
    begin
      if E.Message <> '' then
        FErrorMsg := E.Message
      else
        FErrorMsg := 'Unknown error';
      SetStatus(tsErrored);
    end;
  end;
  if GetStatus <> tsTerminated then
    goto Restart;
end;

procedure TTask.Start;
begin
  if not FStarted then
  begin
    FStarted := True;
    inherited Start;
  end;
  SetStatus(tsRunning);
end;

procedure TTask.Wait;
begin
  while GetStatus = tsRunning do
    Sleep(1);
end;

procedure TTask.RaiseLastError;
var
  Msg: string;
begin
  if FErrorMsg <> '' then
  begin
    Msg := FErrorMsg;
    FErrorMsg := '';
    raise EThreadException.Create(Msg);
  end;
end;

procedure WaitForAll(const Tasks: array of TTask);
var
  I: Integer;
begin
  for I := Low(Tasks) to High(Tasks) do
    Tasks[I].Wait;
end;

function WaitForAny(const Tasks: array of TTask): Integer;
var
  I: Integer;
begin
  Result := -1;
  while True do
  begin
    for I := Low(Tasks) to High(Tasks) do
    begin
      if Tasks[I].Status <> tsRunning then
      begin
        Result := I;
        exit;
      end;
    end;
    Sleep(1);
  end;
end;

function IsErrored(const Tasks: array of TTask): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(Tasks) to High(Tasks) do
  begin
    if Tasks[I].Status = TThreadStatus.tsErrored then
    begin
      Result := True;
      exit;
    end;
  end;
end;

end.
