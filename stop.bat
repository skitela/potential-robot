@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\SYSTEM_CONTROL.ps1" -Action stop -Root "%ROOT%"
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo STOP_OK
) else (
    echo STOP_FAIL rc=%RC%
)

endlocal & exit /b %RC%
