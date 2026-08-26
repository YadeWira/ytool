unit InitCode;

interface

uses
  Utils,
  SysUtils, StrUtils;

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
// Sin el guard de vacio, IncludeTrailingBackSlash('') devuelve el separador
// suelto y PluginsPath queda en '/', o sea la raiz. Eso pasaba desapercibido
// porque ExpandPath tenia el defecto complementario: no reconocia una ruta que
// empieza con separador como absoluta y le anteponia el directorio del
// ejecutable, deshaciendo el error. Los dos juntos daban la ruta correcta.
// Al arreglar ExpandPath el primero queda a la vista, asi que va aca.
if PluginsPath <> '' then
  PluginsPath := IncludeTrailingBackSlash(ExpandPath(PluginsPath));
if (PluginsPath = '') or not DirectoryExists(ExpandPath(PluginsPath, True)) then
  PluginsPath := ExtractFilePath(Utils.GetModuleName);

end.
