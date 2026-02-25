@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

py -3.12 -B "%ROOT%\TOOLS\run_tmp_janitor.py" --root "%ROOT%" --apply --min-age-sec 1800 --keep-per-prefix 6 --max-delete 50000 --evidence "EVIDENCE\housekeeping\run_tmp_janitor_72h_start.json"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\RUN\START_HARDMODE_NIGHT.ps1" ^
  -Root "%ROOT%" ^
  -DurationHours 72 ^
  -MonitorIntervalSec 5 ^
  -PulseEverySec 30 ^
  -StallAlertSec 900 ^
  -TradeGuardPollSec 15 ^
  -TradeGuardNoTradeSec 900 ^
  -TradeGuardRestartCooldownSec 1200 ^
  -WatchdogIntervalSec 60 ^
  -WatchdogMinAlive 3 ^
  -WatchdogUnhealthyStrike 3 ^
  -WatchdogSmokeEveryMin 30

set "RC=%ERRORLEVEL%"
if "%RC%"=="0" (
    echo START_LONG_SUPERVISOR_72H_OK
) else (
    echo START_LONG_SUPERVISOR_72H_FAIL rc=%RC%
)
endlocal & exit /b %RC%
