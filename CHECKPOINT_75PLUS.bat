@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\\RUN\\CHECKPOINT_75PLUS.ps1" -Root "%ROOT%"
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" (
    echo CHECKPOINT_75PLUS_OK
) else (
    echo CHECKPOINT_75PLUS_WARN rc=%RC%
)

endlocal & exit /b %RC%
