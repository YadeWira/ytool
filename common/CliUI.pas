unit CliUI;

// Presentation helpers for the command line: whether stderr is a terminal,
// colours, the terminal's width, and a one-line status that redraws itself.
//
// Everything here writes to stderr, like WriteLine: stdout carries the
// payload when input or output is "-". When stderr is not a terminal (a log
// file, a pipe, a test script) there is no colour and no live line, so what a
// script reads is plain text with no escape codes.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
{$IFDEF UNIX}
  BaseUnix, termio,
{$ENDIF}
  SysUtils, Math;

// stderr is an interactive terminal.
function UIIsTTY: Boolean;
// Colours allowed: a terminal, NO_COLOR unset, TERM not "dumb", and on
// Windows a console that takes escape sequences (Windows 10 and later).
function UIColor: Boolean;
// Columns of the terminal stderr goes to; 80 when unknown.
function UIWidth: Integer;

function UIBold(const S: string): string;
function UIDim(const S: string): string;
function UICyan(const S: string): string;
function UIGreen(const S: string): string;
function UIYellow(const S: string): string;
function UIRed(const S: string): string;

// Length of S as shown, without escape sequences.
function UIVisibleLength(const S: string): Integer;
// S followed by spaces up to Width visible characters.
function UIPad(const S: string; Width: Integer): string;

// Rewrites the status line in place (carriage return, no newline). Cut to the
// terminal's width so it never wraps, since a wrapped line cannot be redrawn.
procedure UIStatus(const S: string);
// Erases the status line, leaving the cursor at its start.
procedure UIStatusClear;

// "[=========>          ]" for Frac in 0..1.
function UIBar(Frac: Double; Width: Integer): string;
// 0:07, 12:34, 1:02:03.
function UIDuration(Seconds: Int64): string;
// 512 B, 1.5 KB, 12.3 MB, 4.56 GB.
function UISize(Bytes: Int64): string;

implementation

var
  FChecked: Boolean = False;
  FIsTTY: Boolean = False;
  FColor: Boolean = False;
  FStatusLen: Integer = 0;

procedure Check;
var
  S: string;
{$IFDEF MSWINDOWS}
  H: THandle;
  Mode: DWORD;
{$ENDIF}
begin
  if FChecked then
    exit;
  FChecked := True;
{$IFDEF MSWINDOWS}
  H := GetStdHandle(STD_ERROR_HANDLE);
  FIsTTY := (H <> INVALID_HANDLE_VALUE) and GetConsoleMode(H, Mode);
  // ENABLE_VIRTUAL_TERMINAL_PROCESSING. Refused before Windows 10: then no
  // colours, and the status line still works with a plain carriage return.
  FColor := FIsTTY and ((Mode and $0004 <> 0) or SetConsoleMode(H,
    Mode or $0004));
{$ELSE}
  FIsTTY := IsATTY(2) = 1;
  FColor := FIsTTY;
{$ENDIF}
  if FColor then
  begin
    if GetEnvironmentVariable('NO_COLOR') <> '' then
      FColor := False;
    S := GetEnvironmentVariable('TERM');
    if SameText(S, 'dumb') then
      FColor := False;
  end;
end;

function UIIsTTY: Boolean;
begin
  Check;
  Result := FIsTTY;
end;

function UIColor: Boolean;
begin
  Check;
  Result := FColor;
end;

function UIWidth: Integer;
{$IFDEF MSWINDOWS}
var
  Info: TConsoleScreenBufferInfo;
{$ELSE}
var
  WS: TWinSize;
{$ENDIF}
begin
  Result := 80;
  if not UIIsTTY then
    exit;
{$IFDEF MSWINDOWS}
  if GetConsoleScreenBufferInfo(GetStdHandle(STD_ERROR_HANDLE), Info) then
    Result := Info.srWindow.Right - Info.srWindow.Left + 1;
{$ELSE}
  FillChar(WS, SizeOf(WS), 0);
  if (FpIoctl(2, TIOCGWINSZ, @WS) = 0) and (WS.ws_col > 0) then
    Result := WS.ws_col;
{$ENDIF}
  if Result < 20 then
    Result := 80;
end;

function Wrap(const Code, S: string): string;
begin
  if UIColor and (S <> '') then
    Result := #27'[' + Code + 'm' + S + #27'[0m'
  else
    Result := S;
end;

function UIBold(const S: string): string;
begin
  Result := Wrap('1', S);
end;

function UIDim(const S: string): string;
begin
  Result := Wrap('2', S);
end;

function UICyan(const S: string): string;
begin
  Result := Wrap('36', S);
end;

function UIGreen(const S: string): string;
begin
  Result := Wrap('32', S);
end;

function UIYellow(const S: string): string;
begin
  Result := Wrap('33', S);
end;

function UIRed(const S: string): string;
begin
  Result := Wrap('31', S);
end;

function UIVisibleLength(const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = #27 then
    begin
      // CSI: ESC [ parameters final-letter
      Inc(I);
      if (I <= Length(S)) and (S[I] = '[') then
      begin
        Inc(I);
        while (I <= Length(S)) and not(S[I] in ['@' .. '~']) do
          Inc(I);
      end;
      Inc(I);
      continue;
    end;
    // count UTF-8 lead bytes only
    if (Ord(S[I]) and $C0) <> $80 then
      Inc(Result);
    Inc(I);
  end;
end;

function UIPad(const S: string; Width: Integer): string;
begin
  Result := S + StringOfChar(' ', Max(0, Width - UIVisibleLength(S)));
end;

procedure UIStatus(const S: string);
var
  T: string;
  W: Integer;
begin
  // plain text only: the cut below counts bytes
  W := UIWidth - 1;
  T := S;
  if Length(T) > W then
    T := Copy(T, 1, W);
  Write(ErrOutput, #13 + T + StringOfChar(' ', Max(0, FStatusLen - Length(T)))
    + StringOfChar(#8, Max(0, FStatusLen - Length(T))));
  Flush(ErrOutput);
  FStatusLen := Length(T);
end;

procedure UIStatusClear;
begin
  if FStatusLen = 0 then
    exit;
  Write(ErrOutput, #13 + StringOfChar(' ', FStatusLen) + #13);
  Flush(ErrOutput);
  FStatusLen := 0;
end;

function UIBar(Frac: Double; Width: Integer): string;
var
  N: Integer;
begin
  Frac := EnsureRange(Frac, 0, 1);
  N := Round(Frac * Width);
  if N >= Width then
    Result := '[' + StringOfChar('=', Width) + ']'
  else if N = 0 then
    Result := '[' + StringOfChar(' ', Width) + ']'
  else
    Result := '[' + StringOfChar('=', N - 1) + '>' +
      StringOfChar(' ', Width - N) + ']';
end;

function UIDuration(Seconds: Int64): string;
begin
  if Seconds < 0 then
    Seconds := 0;
  if Seconds >= 3600 then
    Result := Format('%d:%.2d:%.2d', [Seconds div 3600, Seconds mod 3600 div 60,
      Seconds mod 60])
  else
    Result := Format('%d:%.2d', [Seconds div 60, Seconds mod 60]);
end;

function UISize(Bytes: Int64): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if Bytes < 1024 then
    Result := Format('%d B', [Bytes])
  else if Bytes < 1024 * 1024 then
    Result := Format('%.1f KB', [Bytes / 1024], FS)
  else if Bytes < Int64(1024) * 1024 * 1024 then
    Result := Format('%.1f MB', [Bytes / (1024 * 1024)], FS)
  else
    Result := Format('%.2f GB', [Bytes / (1024.0 * 1024 * 1024)], FS);
end;

end.
