unit PackJPGDLL;

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Math, SysUtils, Classes;

const
  pjglib_file = 0;
  pjglib_memory = 1;
  pjglib_handle = 2;

var
  pjglib_convert_stream2stream: function(msg: PAnsiChar): Boolean cdecl;
  pjglib_convert_file2file: function(ain, aout, msg: PAnsiChar): Boolean cdecl;
  pjglib_convert_stream2mem: function(out_file: PPAnsiChar; out_size: PCardinal;
    msg: PAnsiChar): Boolean cdecl;
  pjglib_init_streams: procedure(in_src: Pointer; in_type: Integer;
    in_size: Integer; out_dest: Pointer; out_type: Integer)cdecl;
  pjglib_version_info: function: PAnsiChar cdecl;
  pjglib_short_name: function: PAnsiChar cdecl;
  // v4.0e (fork): intra-file thread control. ytool already parallelizes per
  // stream, so we force packjpg to 1 thread (n=1) to avoid its std::thread
  // spawn clashing with ytool's own threading runtime. Optional (may not
  // exist in older DLLs).
  pjglib_set_intra_file_threads: procedure(n: Integer)cdecl;

  DLLLoaded: Boolean = False;

implementation

var
  Lib: TLibImport;

procedure Init;
begin
  Lib := TLibImport.Create;
  Lib.LoadLib(ExpandPath(PluginsPath + 'packjpg_dll.dll', True));
{$IFDEF UNIX}
  if not Lib.Loaded then
    Lib.LoadLib(ExpandPath(PluginsPath + 'libpackjpg.so', True));
{$ENDIF}
  if Lib.Loaded then
  begin
    @pjglib_convert_stream2stream :=
      Lib.GetProcAddr('pjglib_convert_stream2stream');
    @pjglib_convert_file2file := Lib.GetProcAddr('pjglib_convert_file2file');
    @pjglib_convert_stream2mem := Lib.GetProcAddr('pjglib_convert_stream2mem');
    @pjglib_init_streams := Lib.GetProcAddr('pjglib_init_streams');
    @pjglib_version_info := Lib.GetProcAddr('pjglib_version_info');
    @pjglib_short_name := Lib.GetProcAddr('pjglib_short_name');
    DLLLoaded := Assigned(pjglib_init_streams) and
      Assigned(pjglib_convert_stream2stream) and
      Assigned(pjglib_convert_stream2mem);
    @pjglib_set_intra_file_threads :=
      Lib.GetProcAddr('pjglib_set_intra_file_threads');
    if Assigned(pjglib_set_intra_file_threads) then
      pjglib_set_intra_file_threads(1);
    // FPC unmasks FPU exceptions by default; packjpg does a lot of floating
    // point (DCT) assuming C's IEEE-masked mode -> without this, a normal FP
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
