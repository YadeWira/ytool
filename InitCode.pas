unit InitCode;

interface

uses
  Utils,
  System.SysUtils, System.StrUtils;

const
  PluginsParam = '-bd';

var
  DEBUG: Boolean = False;
  PluginsPath: String = '';

implementation

var
  I: Integer;

initialization

if not IsLibrary then
begin
  for I := 1 to ParamCount do
  begin
    if (ParamStr(I) = '--debug') then
    begin
      DEBUG := True;
      break;
    end;
  end;
  for I := 1 to ParamCount do
  begin
    if ParamStr(I).StartsWith(PluginsParam) then
    begin
      PluginsPath := ParamStr(I).Substring(PluginsParam.Length);
      break;
    end;
  end;
end;
PluginsPath := IncludeTrailingBackSlash(ExpandPath(PluginsPath));
if not DirectoryExists(ExpandPath(PluginsPath, True)) then
  PluginsPath := ExtractFilePath(Utils.GetModuleName);

end.
