@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\START_OPERATOR_PANEL.ps1" -Root "%ROOT%"
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo PANEL_OK
) else (
    echo PANEL_FAIL rc=%RC%
)

endlocal & exit /b %RC%

