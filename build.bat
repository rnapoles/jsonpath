@echo off
rem ---------------------------------------------------------------------------
rem  Builds the examples and test runners.
rem    build.bat [fpc|delphi|all] [win32|win64]        (defaults: all, win64)
rem  Delphi : needs RAD Studio 12+ (uses %BDS%, or the default 23.0 install dir)
rem  FPC    : needs fpc.exe on PATH (3.2.2+)
rem  Output : build\fpc-^<platform^>\bin   and   build\delphi-^<platform^>\bin
rem  Built  : tests\Test*.pas, schema\tests\Test*.pas, cts\tests\Test*.pas,
rem           samples\Sample*.pas, schema\samples\Sample*.pas
rem  Compiler logs: build\<tag>\logs\<program>.log
rem  "all" skips a toolchain that is not installed; naming one explicitly makes
rem  a missing toolchain an error. Exit code: 0 = everything built, 1 = failure.
rem ---------------------------------------------------------------------------
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
set "ROOT=%CD%"

set "COMPILER=%~1"
set "PLATFORM=%~2"
if not defined COMPILER set "COMPILER=all"
if not defined PLATFORM set "PLATFORM=win64"

set "VALID="
for %%C in (fpc delphi all) do if /i "%COMPILER%"=="%%C" ( set "COMPILER=%%C" & set "VALID=1" )
if not defined VALID goto :usage
set "VALID="
for %%P in (win32 win64) do if /i "%PLATFORM%"=="%%P" ( set "PLATFORM=%%P" & set "VALID=1" )
if not defined VALID goto :usage

set "FAILED=0"
set "BUILT=0"
set "STRICT="
if /i not "%COMPILER%"=="all" set "STRICT=1"

if /i "%COMPILER%"=="fpc"    call :build_fpc
if /i "%COMPILER%"=="delphi" call :build_delphi
if /i "%COMPILER%"=="all" (
  call :build_fpc
  call :build_delphi
)

echo.
echo Built !BUILT! program^(s^), !FAILED! failed.
if !FAILED! gtr 0 exit /b 1
if !BUILT! equ 0 (
  echo ERROR: no toolchain was available - nothing was built.
  exit /b 1
)
exit /b 0

rem ---------------------------------------------------------------------------
:usage
echo Usage: build.bat [fpc^|delphi^|all] [win32^|win64]     (defaults: all, win64)
exit /b 2

rem ---------------------------------------------------------------------------
:build_fpc
where fpc >nul 2>&1
if errorlevel 1 (
  if defined STRICT (
    echo ERROR: fpc.exe was not found on PATH.
    set /a FAILED+=1
  ) else (
    echo Skipping Free Pascal: fpc.exe was not found on PATH.
  )
  exit /b 0
)
if /i "%PLATFORM%"=="win64" ( set "FPC_TARGET=-Px86_64 -Twin64" ) else ( set "FPC_TARGET=-Pi386 -Twin32" )
set "TAG=fpc-%PLATFORM%"
set "OUT=%ROOT%\build\%TAG%"
echo.
echo === Free Pascal, %PLATFORM% =^> build\%TAG%\bin ===
call :prepare
call :each_source :fpc_one
exit /b 0

rem ---------------------------------------------------------------------------
:build_delphi
set "RSVARS="
if defined BDS (
  if exist "%BDS%\bin\rsvars.bat" set "RSVARS=%BDS%\bin\rsvars.bat"
)
if not defined RSVARS (
  set "_FB=%ProgramFiles(x86)%\Embarcadero\Studio\37.0\bin\rsvars.bat"
  if exist "!_FB!" set "RSVARS=!_FB!"
)
if not defined RSVARS (
  if defined STRICT (
    echo ERROR: RAD Studio not found ^(set BDS^)
    set /a FAILED+=1
  ) else (
    echo Skipping Delphi: RAD Studio not found
  )
  exit /b 0
)
set "_SAVE_PLATFORM=%PLATFORM%"
call "%RSVARS%" >nul
set "PLATFORM=%_SAVE_PLATFORM%"

set "DCC=%BDS%\bin\dcc32.exe"
if /i "%PLATFORM%"=="win64" set "DCC=%BDS%\bin\dcc64.exe"
if not exist "!DCC!" (
  if defined STRICT (
    echo ERROR: the Delphi compiler was not found: !DCC!
    echo        Set BDS to the RAD Studio install directory.
    set /a FAILED+=1
  ) else (
    echo Skipping Delphi: the compiler was not found.
  )
  exit /b 0
)
set "TAG=delphi-%PLATFORM%"
set "OUT=%ROOT%\build\%TAG%"
echo.
echo === Delphi, %PLATFORM% =^> build\%TAG%\bin ===
call :prepare
call :each_source :delphi_one
exit /b 0

rem ---------------------------------------------------------------------------
:prepare
for %%D in (bin obj dcu logs) do if not exist "%OUT%\%%D" mkdir "%OUT%\%%D"
exit /b 0

rem  %1 = label that compiles one source file
:each_source
for %%F in (tests\Test*.pas schema\tests\Test*.pas cts\tests\Test*.pas examples\Sample*.pas schema\samples\Sample*.pas) do (
  if /i not "%%~nF"=="TestSupport" call %1 "%%F"
)
exit /b 0

:fpc_one
set "SRC=%~1"
set "NAME=%~n1"
fpc -Mdelphi -Sh -O1 %FPC_TARGET% -Fusrc -Fuschema -Fucts -Futests -Fuschema\tests -FU"%OUT%\obj" -FE"%OUT%\bin" -o"%OUT%\bin\%NAME%.exe" "%SRC%" >"%OUT%\logs\%NAME%.log" 2>&1
if errorlevel 1 (
  echo   FAILED  %NAME%  ^(see build\%TAG%\logs\%NAME%.log^)
  set /a FAILED+=1
) else (
  echo   ok      %NAME%
  set /a BUILT+=1
)
exit /b 0

:delphi_one
set "SRC=%~1"
set "NAME=%~n1"
"%DCC%" -Q "-$O+" "-U%ROOT%\src;%ROOT%\schema;%ROOT%\cts;%ROOT%\tests;%ROOT%\schema\tests" "-NSSystem;System.Win;Winapi" "-E%OUT%\bin" "-N0%OUT%\dcu" "%SRC%" >"%OUT%\logs\%NAME%.log" 2>&1
if errorlevel 1 (
  echo   FAILED  %NAME%  ^(see build\%TAG%\logs\%NAME%.log^)
  set /a FAILED+=1
) else (
  echo   ok      %NAME%
  set /a BUILT+=1
)
exit /b 0


