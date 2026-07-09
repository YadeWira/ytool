unit PackMP3DLL;

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Math, SysUtils, Classes;

const
  pmplib_file = 0;
  pmplib_memory = 1;
  pmplib_handle = 2;

var
  pmplib_convert_stream2stream: function(msg: PAnsiChar): Boolean cdecl;
  pmplib_convert_file2file: function(ain, aout, msg: PAnsiChar): Boolean cdecl;
  pmplib_convert_stream2mem: function(out_file: PPAnsiChar; out_size: PCardinal;
    msg: PAnsiChar): Boolean cdecl;
  pmplib_init_streams: procedure(in_src: Pointer; in_type: Integer;
    in_size: Integer; out_dest: Pointer; out_type: Integer)cdecl;
  pmplib_version_info: function: PAnsiChar cdecl;
  pmplib_short_name: function: PAnsiChar cdecl;

  DLLLoaded: Boolean = False;

implementation

var
  Lib: TLibImport;

procedure Init;
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(PluginsPath + 'packmp3_dll.dll', True));
{$IFDEF UNIX}
  if not Lib.Loaded then
    Lib.LoadLib(ExpandPath(PluginsPath + 'libpackmp3.so', True));
{$ENDIF}
  if Lib.Loaded then
  begin
    @pmplib_convert_stream2stream :=
      Lib.GetProcAddr('pmplib_convert_stream2stream');
    @pmplib_convert_file2file := Lib.GetProcAddr('pmplib_convert_file2file');
    @pmplib_convert_stream2mem := Lib.GetProcAddr('pmplib_convert_stream2mem');
    @pmplib_init_streams := Lib.GetProcAddr('pmplib_init_streams');
    @pmplib_version_info := Lib.GetProcAddr('pmplib_version_info');
    @pmplib_short_name := Lib.GetProcAddr('pmplib_short_name');
    DLLLoaded := Assigned(pmplib_init_streams) and
      Assigned(pmplib_convert_stream2stream) and
      Assigned(pmplib_convert_stream2mem);
    // FPC unmasks FPU exceptions by default; packMP3 does floating point
    // (IMDCT) assuming C's IEEE-masked mode -> without this, a normal FP
    // operation inside the lib triggers SIGFPE and aborts the conversion.
    if DLLLoaded then
      SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
        exUnderflow, exPrecision]);
  end;
end;

procedure Deinit;
begin
  Lib.Free;
end;

initialization

Init;

finalization

Deinit;

end.
