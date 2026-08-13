unit PackJPGDLL;

interface

uses
  InitCode,
  Utils, LibImport,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Math, SyncObjs, SysUtils, Classes;

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

  // Serializes each pjglib_init_streams + pjglib_convert_* pair.
  //
  // NOT because packJPG's API requires it: str_in/str_out and the error state
  // are `static thread_local` there (87 such variables), so each thread gets
  // its own copy and concurrent init+convert is safe through the library --
  // packJPG's maintainer corrected an earlier version of this comment that
  // claimed otherwise, and a pure-C host driving 4 unsynchronized threads
  // through the same DLL confirms it. The lock is here for ytool's own sake:
  // it keeps the pair atomic with respect to the Buffer/Res locals and the
  // Output() callback around it, and it matches what upstream packMP3 does
  // with its own pjg_mutex.
  //
  // What this lock does NOT fix, tested, so nobody re-tries it: a
  // posix-thread-model build of the DLL still deadlocks ytool (on Windows 10
  // 19044; not reproduced on Windows 7) with every call serialized here.
  // Cause still unidentified: ytool loads this DLL at unit initialization,
  // before its TTask workers exist, so it is NOT the pre-existing-thread
  // defect documented in the build script -- see
  // contrib/build-plugins-windows.sh's packjpg comment for the static-TLS
  // ordering problem and why the win32-model build is not made redundant
  // by this lock.

  PJGLock: TCriticalSection;

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

PJGLock := TCriticalSection.Create;
Init;

finalization

Deinit;
PJGLock.Free;

end.
