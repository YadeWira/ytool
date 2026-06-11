unit LibImport;

interface

uses
  dynlibs,
{$IFDEF MSWINDOWS}
  Windows, Character,
{$ENDIF}
  SysUtils, Classes;

type
  TLibImport = class
  private
    FIsMemoryLib: Boolean;
    FDLLLoaded: Boolean;
    FImageFileName: String;
    FTempFile: String;
    FDLLStream: TMemoryStream;
    FDLLHandle: TLibHandle;
    FImagePtr: Pointer;
    FImageSize: NativeInt;
    procedure LoadFromTemp;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadLib(ALibrary: String); overload;
    procedure LoadLib(AMemory: Pointer; ASize: NativeInt); overload;
    procedure LoadLib(AStream: TStream; ASize: NativeInt); overload;
    procedure UnloadLib;
    function GetProcAddr(AProcName: PAnsiChar): Pointer;
    property Loaded: Boolean read FDLLLoaded;
    property IsMemory: Boolean read FIsMemoryLib;
    property ImageFileName: String read FImageFileName;
    property ImagePtr: Pointer read FImagePtr;
    property ImageSize: NativeInt read FImageSize;
  end;

procedure InjectLib(Source, Dest: String);

implementation

constructor TLibImport.Create;
begin
  inherited Create;
  FIsMemoryLib := False;
  FDLLLoaded := False;
  FDLLHandle := NilHandle;
  FDLLStream := nil;
  FImageFileName := '';
  FTempFile := '';
  FImagePtr := nil;
  FImageSize := 0;
end;

destructor TLibImport.Destroy;
begin
  UnloadLib;
  inherited Destroy;
end;

{ Carga una libreria nativa desde disco. dynlibs resuelve .dll en Windows y
  .so en Linux/Unix de forma transparente. }
procedure TLibImport.LoadLib(ALibrary: String);
begin
  UnloadLib;
  FIsMemoryLib := False;
  FDLLHandle := LoadLibrary(ALibrary);
  FDLLLoaded := FDLLHandle <> NilHandle;
  FImageFileName := ALibrary;
  FImagePtr := nil;
  FImageSize := 0;
end;

{ Carga desde memoria: escribe la imagen a un archivo temporal y la carga desde
  ahi (multiplataforma, en lugar del antiguo MemoryModule de Windows). }
procedure TLibImport.LoadFromTemp;
begin
  FTempFile := GetTempFileName('', 'ytl');
  FDLLStream.SaveToFile(FTempFile);
  FDLLHandle := LoadLibrary(FTempFile);
  FDLLLoaded := FDLLHandle <> NilHandle;
  FImagePtr := FDLLStream.Memory;
  FImageSize := FDLLStream.Size;
end;

procedure TLibImport.LoadLib(AMemory: Pointer; ASize: NativeInt);
begin
  UnloadLib;
  FIsMemoryLib := True;
  FDLLStream := TMemoryStream.Create;
  FDLLStream.WriteBuffer(AMemory^, ASize);
  FImageFileName := '';
  LoadFromTemp;
end;

procedure TLibImport.LoadLib(AStream: TStream; ASize: NativeInt);
begin
  UnloadLib;
  FIsMemoryLib := True;
  FDLLStream := TMemoryStream.Create;
  FDLLStream.CopyFrom(AStream, ASize);
  FImageFileName := '';
  LoadFromTemp;
end;

procedure TLibImport.UnloadLib;
begin
  if FDLLLoaded then
    UnloadLibrary(FDLLHandle);
  FDLLLoaded := False;
  FDLLHandle := NilHandle;
  if Assigned(FDLLStream) then
    FreeAndNil(FDLLStream);
  if FTempFile <> '' then
  begin
    DeleteFile(FTempFile);
    FTempFile := '';
  end;
  FImagePtr := nil;
  FImageSize := 0;
end;

function TLibImport.GetProcAddr(AProcName: PAnsiChar): Pointer;
begin
  if not FDLLLoaded then
    Result := nil
  else
    Result := GetProcedureAddress(FDLLHandle, String(AProcName));
end;

{$IFDEF MSWINDOWS}
function FileToResourceName(FileName: String): String;
var
  I: Integer;
begin
  Result := ExtractFileName(FileName).ToUpper;
  for I := 1 to Result.Length do
    if not Result[I].IsLetterOrDigit then
      Result[I] := '_';
end;

procedure UpdateFileResource(Source, Dest, ResName: string);
var
  Stream: TFileStream;
  hDestRes: THandle;
  lpData: Pointer;
  cbData: DWORD;
begin
  Stream := TFileStream.Create(Source, fmOpenRead or fmShareDenyNone);
  try
    Stream.Seek(0, soFromBeginning);
    cbData := Stream.Size;
    if cbData > 0 then
    begin
      GetMem(lpData, cbData);
      try
        Stream.ReadBuffer(lpData^, cbData);
        hDestRes := BeginUpdateResource(PChar(Dest), False);
        if hDestRes <> 0 then
          if UpdateResource(hDestRes, RT_RCDATA, PWideChar(ResName), 0, lpData,
            cbData) then
          begin
            if not EndUpdateResource(hDestRes, False) then
              RaiseLastOSError;
          end
          else
            RaiseLastOSError
        else
          RaiseLastOSError;
      finally
        FreeMem(lpData);
      end;
    end;
  finally
    Stream.Free;
  end;
end;

procedure InjectLib(Source, Dest: String);
var
  LResName: String;
begin
  if not FileExists(Source) then
    raise Exception.Create('Specified file not found');
  LResName := FileToResourceName(Source);
  UpdateFileResource(Source, Dest, LResName);
end;
{$ELSE}
procedure InjectLib(Source, Dest: String);
begin
  raise Exception.Create('InjectLib: resource embedding not supported on this platform');
end;
{$ENDIF}

end.
