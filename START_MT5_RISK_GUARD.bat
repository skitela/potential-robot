@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\mt5_risk_popup_guard.ps1" -Root "%ROOT%"
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo MT5_RISK_GUARD_OK
) else (
    echo MT5_RISK_GUARD_FAIL rc=%RC%
)

endlocal & exit /b %RC%
