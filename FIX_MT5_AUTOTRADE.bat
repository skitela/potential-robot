@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\mt5_fix_autotrade_settings.ps1" %*
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo MT5_AUTOTRADE_FIX_DONE
) else (
    echo MT5_AUTOTRADE_FIX_FAIL rc=%RC%
)

endlocal & exit /b %RC%
