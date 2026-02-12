@echo off
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\CREATE_START_STOP_SHORTCUTS.ps1" -Root "%ROOT%" -Force
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo SHORTCUTS_OK
) else (
    echo SHORTCUTS_FAIL rc=%RC%
)

endlocal & exit /b %RC%
