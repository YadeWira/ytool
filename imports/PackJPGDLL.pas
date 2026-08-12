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

  // Every pjglib_init_streams + pjglib_convert_* pair must be held under this
  // lock. Two reasons, one of them measured the hard way:
  //
  // 1. The pair is stateful: init_streams arms the buffers that the following
  //    convert consumes, so the two calls have to be atomic with respect to
  //    each other or a second thread's init can land between them.
  // 2. Upstream packMP3 serializes every pjglib_* call behind its own mutex
  //    for the same reason, noting packJPG's thread-safety for concurrent
  //    calls is unverified. Matching that is cheap insurance.
  //
  // What this lock does NOT fix, tested and stated so nobody re-tries it:
  // a posix-thread-model build of the DLL still deadlocks ytool even with
  // every call serialized here (~0% CPU, unkillable, keeps the .dll file
  // locked until the machine restarts). So the win32-model build in
  // contrib/build-plugins-windows.sh is not made redundant by this lock.
  // That deadlock was narrowed with packJPG's own maintainer across Windows
  // 10 and Windows 7: pure-C hosts drive the very same DLL from four
  // concurrent raw CreateThread workers without hanging, and `ytool -t1` is
  // fine, so the trigger is specifically FP RTL threads -- but serializing
  // the codec entry points is evidently not where it lives.
  //
  // Cost is bounded: ytool parallelizes across streams, so this only
  // serializes the packjpg codec itself, not the surrounding pipeline.
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
