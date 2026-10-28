@echo off
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

rem ---------------------------------------------------------------------------

echo ### Building (%COMPILER%, %PLATFORM%)
call "%ROOT%\build.bat" %COMPILER% %PLATFORM%
call "%ROOT%\test.bat" %COMPILER% %PLATFORM%
exit /b 0

rem ---------------------------------------------------------------------------
:usage
echo Usage: build_and_test.bat [fpc^|delphi] [win32^|win64]     (defaults: fpc if present, win64)
exit /b 2

rem ---------------------------------------------------------------------------
