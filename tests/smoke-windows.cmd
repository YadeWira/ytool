@echo off
rem Windows counterpart of tests/regression.sh's CODEC_EXPECT check: every
rem (file, codec) pair in the list must round-trip byte for byte AND process
rem at least one stream. A codec whose library did not load still round-trips
rem (it stores everything as it is), so the count is the real test.
rem
rem Usage: smoke-windows.cmd <ytool.exe> <corpus folder> <expect file>
rem   expect file: lines "file|-mcodec|n", tests/regression.sh's CODEC_EXPECT
rem   corpus: what tests/gen_corpus.py writes
rem
rem Batch rather than PowerShell: Windows 7 has PowerShell 2.0 only.
rem Exit code: 0 all passed, 1 something failed.
setlocal enabledelayedexpansion
if "%~3"=="" (
  echo usage: smoke-windows.cmd ytool.exe corpus-folder expect-file
  exit /b 2
)
set "Y=%~f1"
set "C=%~f2"
set "W=%TEMP%\ytool-smoke-%RANDOM%"
mkdir "%W%" || exit /b 2
set PASS=0
set FAIL=0
set SKIP=0
for /f "usebackq tokens=1,2,3 delims=|" %%f in ("%~f3") do call :one "%%f" "%%g" "%%h"
rmdir /s /q "%W%"
echo -- smoke: !PASS! OK, !FAIL! FAIL, !SKIP! skipped --
if !FAIL! gtr 0 exit /b 1
exit /b 0

:one
set "F=%C%\%~1"
if not exist "%F%" (
  set /a SKIP+=1
  goto :eof
)
del /q "%W%\o.ytp" "%W%\o.bin" 2>nul
"%Y%" precomp %~2 "%F%" "%W%\o.ytp" > "%W%\p.log" 2>&1
if errorlevel 1 (
  echo FAIL %~1 %~2: precomp exit !errorlevel!
  type "%W%\p.log"
  set /a FAIL+=1
  goto :eof
)
"%Y%" decode "%W%\o.ytp" "%W%\o.bin" > "%W%\d.log" 2>&1
if errorlevel 1 (
  echo FAIL %~1 %~2: decode exit !errorlevel!
  type "%W%\d.log"
  set /a FAIL+=1
  goto :eof
)
fc /b "%F%" "%W%\o.bin" > nul
if errorlevel 1 (
  echo FAIL %~1 %~2: decode differs from the original
  set /a FAIL+=1
  goto :eof
)
rem "Streams: X / Y": X processed, Y found
set N=0
for /f "tokens=2" %%a in ('findstr /c:"Streams:" "%W%\p.log"') do set N=%%a
if !N! lss 1 (
  echo FAIL %~1 %~2: codec processed no stream ^(wanted %~3^)
  set /a FAIL+=1
  goto :eof
)
echo ok   %~1 %~2: !N! streams
set /a PASS+=1
goto :eof
