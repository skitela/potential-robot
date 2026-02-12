@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "DRY="
if /I "%~1"=="--dry-run" set "DRY=-DryRun"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\SYSTEM_CONTROL.ps1" -Action start -Root "%ROOT%" %DRY%
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo START_OK
) else (
    echo START_FAIL rc=%RC%
)

endlocal & exit /b %RC%
