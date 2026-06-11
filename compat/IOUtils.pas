{ Shim de compatibilidad para System.IOUtils de Delphi (no existe en FPC).
  Solo implementa la superficie usada por xtool: TPath.GetFullPath,
  TDirectory.GetFiles (forma de 3 args) y TDirectory.Delete. Las rutas
  devueltas por GetFiles son completas, como en Delphi. }
unit IOUtils;

interface

uses
  SysUtils, Types;

type
  TSearchOption = (soTopDirectoryOnly, soAllDirectories);

  TPath = class
  public
    class function GetFullPath(const APath: string): string; static;
  end;

  TDirectory = class
  public
    class function GetFiles(const APath, ASearchPattern: string;
      const ASearchOption: TSearchOption): TStringDynArray; static;
    class procedure Delete(const APath: string;
      const Recursive: Boolean = False); static;
  end;

implementation

class function TPath.GetFullPath(const APath: string): string;
begin
  Result := ExpandFileName(APath);
end;

class function TDirectory.GetFiles(const APath, ASearchPattern: string;
  const ASearchOption: TSearchOption): TStringDynArray;
var
  SR: TSearchRec;
  Base: string;
  N: Integer;
begin
  SetLength(Result, 0);
  Base := IncludeTrailingPathDelimiter(APath);
  if FindFirst(Base + ASearchPattern, faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then
      begin
        N := Length(Result);
        SetLength(Result, N + 1);
        Result[N] := Base + SR.Name;
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  if ASearchOption = soAllDirectories then
    if FindFirst(Base + '*', faDirectory, SR) = 0 then
    begin
      repeat
        if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.') and
          (SR.Name <> '..') then
          Insert(GetFiles(Base + SR.Name, ASearchPattern, ASearchOption),
            Result, Length(Result));
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
end;

class procedure TDirectory.Delete(const APath: string;
  const Recursive: Boolean);
var
  SR: TSearchRec;
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(APath);
  if Recursive then
    if FindFirst(Base + '*', faAnyFile, SR) = 0 then
    begin
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
          if (SR.Attr and faDirectory) <> 0 then
            Delete(Base + SR.Name, True)
          else
            SysUtils.DeleteFile(Base + SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
  RemoveDir(APath);
end;

end.
