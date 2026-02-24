@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\mt5_full_diagnostic.ps1" %*
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo MT5_FULL_DIAGNOSTIC_OK
) else (
    echo MT5_FULL_DIAGNOSTIC_FAIL rc=%RC%
)

endlocal & exit /b %RC%
