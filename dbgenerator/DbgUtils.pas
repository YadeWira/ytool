unit DbgUtils;

interface

uses
  SysUtils, Classes, StrUtils, Types, Math,
  Generics.Defaults, Generics.Collections;

resourcestring
  SPrecompSep1 = '+';
  SPrecompSep2 = ':';
  SPrecompSep3 = ',';
  SPrecompSep4 = '/';
  SPrecompSep5 = '/';
  XTOOL_MAPSUF1 = '-tmp';
  XTOOL_MAPSUF2 = '_mapped.io';
  XTOOL_MAPSUF3 = '.tmp';

const
  XTOOL_DB = $31445458;

type
  PEntryStruct = ^TEntryStruct;

  TEntryStruct = packed record
    Position: Int64;
    OldSize, NewSize, DepthSize: Integer;
  end;

  TEntryStructComparer = class(TComparer<TEntryStruct>)
  public
    function Compare(constref Left, Right: TEntryStruct): Integer; override;
  end;

var
  EntryStructCmp: TEntryStructComparer;

implementation

function TEntryStructComparer.Compare(constref Left, Right: TEntryStruct): Integer;
begin
  Result := Integer(CompareValue(Left.Position, Right.Position));
end;

initialization

EntryStructCmp := TEntryStructComparer.Create;

end.
