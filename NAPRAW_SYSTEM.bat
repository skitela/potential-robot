@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\CODEX_REPAIR_RUNBOOK.ps1" -Root "%ROOT%"
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo REPAIR_OK
) else (
    echo REPAIR_FAIL rc=%RC%
)

endlocal & exit /b %RC%

