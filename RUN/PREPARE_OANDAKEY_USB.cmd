@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "DRIVE=%~1"
set "MODE=%~2"
if "%DRIVE%"=="" (
    set /P DRIVE=Podaj litere pendrive (np. E): 
)

if "%DRIVE%"=="" (
    echo PREPARE_FAIL missing drive letter
    endlocal & exit /b 2
)

set "EXTRA="
if /I "%MODE%"=="bootstrap" set "EXTRA=-BootstrapOnly"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\RUN\PREPARE_OANDAKEY_USB.ps1" -Root "%ROOT%" -DriveLetter "%DRIVE%" %EXTRA%
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo PREPARE_OK
) else (
    echo PREPARE_FAIL rc=%RC%
)

endlocal & exit /b %RC%
