{ Shim de compatibilidad para System.TimeSpan de Delphi (no existe en FPC).
  Solo implementa la superficie usada por xtool: Days/Hours/Minutes/Seconds. }
unit TimeSpan;

interface

type
  TTimeSpan = record
    Days, Hours, Minutes, Seconds, Milliseconds: Integer;
    TotalMilliseconds: Double;
    class function FromMilliseconds(const AValue: Double): TTimeSpan; static;
  end;

implementation

class function TTimeSpan.FromMilliseconds(const AValue: Double): TTimeSpan;
var
  T: Int64;
begin
  Result.TotalMilliseconds := AValue;
  T := Trunc(AValue);
  Result.Milliseconds := T mod 1000;
  T := T div 1000;
  Result.Seconds := T mod 60;
  T := T div 60;
  Result.Minutes := T mod 60;
  T := T div 60;
  Result.Hours := T mod 24;
  T := T div 24;
  Result.Days := T;
end;

end.
