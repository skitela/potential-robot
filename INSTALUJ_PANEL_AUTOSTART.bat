@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\INSTALL_OPERATOR_PANEL_AUTOSTART.ps1" -Root "%ROOT%" -Force
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo AUTOSTART_OK
) else (
    echo AUTOSTART_FAIL rc=%RC%
)

endlocal & exit /b %RC%

