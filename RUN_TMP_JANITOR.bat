@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

py -3.12 -B "%ROOT%\TOOLS\run_tmp_janitor.py" --root "%ROOT%" --apply --min-age-sec 1200 --keep-per-prefix 6 --max-delete 50000 --evidence "EVIDENCE\housekeeping\run_tmp_janitor_manual.json"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" (
  echo RUN_TMP_JANITOR_OK
) else (
  echo RUN_TMP_JANITOR_FAIL rc=%RC%
)

endlocal & exit /b %RC%
