@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

if not exist "%ROOT%\RUN" mkdir "%ROOT%\RUN" >nul 2>nul

echo [1/4] Snapshot status...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\SYSTEM_CONTROL.ps1" -Action status -Profile full -Root "%ROOT%" > "%ROOT%\RUN\last_shutdown_status.txt" 2>&1

echo [2/4] Graceful stop runtime...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\SYSTEM_CONTROL.ps1" -Action stop -Profile full -Root "%ROOT%"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo STOP_FAIL rc=%RC%
    echo Runtime stop failed. No system shutdown executed.
    endlocal & exit /b %RC%
)

echo [3/4] Runtime stopped successfully.
echo [4/4] Windows shutdown in 20 seconds. Run "shutdown /a" to abort.
shutdown /s /t 20 /c "OANDA_MT5_SYSTEM safe shutdown"

endlocal & exit /b 0
