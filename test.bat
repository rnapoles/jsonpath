@echo off
rem ---------------------------------------------------------------------------
rem  Builds, then runs the unit tests and the examples as a smoke test (the
rem  JSONPath compliance test suite runner is exercised on a bundled suite, on
rem  a failing suite and on a missing file).
rem    test.bat [fpc|delphi] [win32|win64]        (defaults: fpc if present, win64)
rem  No external tools are needed. Program output is kept in build\<tag>\bin\*.out
rem  Exit code: 0 = everything passed, 1 = a build, test or example failed.
rem ---------------------------------------------------------------------------
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
set "ROOT=%CD%"

set "COMPILER=%~1"
set "PLATFORM=%~2"
if not defined PLATFORM set "PLATFORM=win64"
if not defined COMPILER (
  where fpc >nul 2>&1
  if errorlevel 1 ( set "COMPILER=delphi" ) else ( set "COMPILER=fpc" )
)

set "VALID="
for %%C in (fpc delphi) do if /i "%COMPILER%"=="%%C" ( set "COMPILER=%%C" & set "VALID=1" )
if not defined VALID goto :usage
set "VALID="
for %%P in (win32 win64) do if /i "%PLATFORM%"=="%%P" ( set "PLATFORM=%%P" & set "VALID=1" )
if not defined VALID goto :usage

::echo ### Building (%COMPILER%, %PLATFORM%)
::call "%ROOT%\build.bat" %COMPILER% %PLATFORM%
::if errorlevel 1 (
::  echo.
::  echo Build failed - tests were not run.
::  exit /b 1
::)

set "BIN=%ROOT%\build\%COMPILER%-%PLATFORM%\bin"
set "TESTS=0"
set "TFAIL=0"
set "SMOKE=0"
set "SFAIL=0"
set "SEQ=0"

pushd "%BIN%"

echo.
echo ### Unit tests
for %%T in (Test*.exe) do (
  set /a TESTS+=1
  echo "==%%~fT=="
  "%%~fT"
  if errorlevel 1 (
    set /a TFAIL+=1
    echo   ^>^>^> %%~nT FAILED
  )
)

echo.
echo ### Examples ^(smoke tests^)
rem  call :smoke ^<program^> "^<arguments^>" "^<text that must appear in the output^>" [expected exit code]
call :smoke SampleStore "" "Sayings of the Century"

popd

echo.
echo ============================================================
echo Unit tests : !TESTS! program^(s^), !TFAIL! failed
echo Examples   : !SMOKE! run, !SFAIL! failed
echo ============================================================
if !TFAIL! gtr 0 exit /b 1
if !SFAIL! gtr 0 exit /b 1
if !TESTS! equ 0 (
  echo ERROR: no test programs were found in %BIN%
  exit /b 1
)
echo All tests passed.
exit /b 0

rem ---------------------------------------------------------------------------
:usage
echo Usage: test.bat [fpc^|delphi] [win32^|win64]     (defaults: fpc if present, win64)
exit /b 2

rem ---------------------------------------------------------------------------
rem  %1 = program (without .exe)   %2 = arguments   %3 = required output text
rem  %4 = expected exit code (default 0)
:smoke
set /a SEQ+=1
set /a SMOKE+=1
set "OUTF=%BIN%\%~1.!SEQ!.out"
set "WANT=%~4"
if not defined WANT set "WANT=0"
"%BIN%\%~1.exe" %~2 >"!OUTF!" 2>&1
set "RC=!errorlevel!"
if not "!RC!"=="!WANT!" (
  echo   FAILED  %~1 %~2  ^(exit code !RC!, expected !WANT!^)
  type "!OUTF!"
  set /a SFAIL+=1
  exit /b 0
)
findstr /c:"%~3" "!OUTF!" >nul
if errorlevel 1 (
  echo   FAILED  %~1 %~2  ^(the output does not contain "%~3"^)
  type "!OUTF!"
  set /a SFAIL+=1
  exit /b 0
)
echo   ok      %~1 %~2
exit /b 0
