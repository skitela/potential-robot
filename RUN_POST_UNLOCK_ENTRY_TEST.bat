@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

echo [1/5] FIX_MT5_AUTOTRADE
call "%ROOT%\FIX_MT5_AUTOTRADE.bat"
if errorlevel 1 (
  echo POST_UNLOCK_ENTRY_TEST_FAIL step=FIX_MT5_AUTOTRADE
  endlocal & exit /b 1
)

echo [2/5] START_STACK
call "%ROOT%\start.bat"
if errorlevel 1 (
  echo POST_UNLOCK_ENTRY_TEST_FAIL step=START
  endlocal & exit /b 1
)

echo [3/5] MT5_FULL_DIAGNOSTIC
call "%ROOT%\RUN_MT5_FULL_DIAGNOSTIC.bat"
if errorlevel 1 (
  echo POST_UNLOCK_ENTRY_TEST_FAIL step=DIAG
  echo Hint: odblokuj trade_allowed ^(broker/account^) i uruchom skrypt ponownie.
  endlocal & exit /b 2
)

echo [4/5] ENTRY_TEST_MONITOR (6 min)
python "%ROOT%\TOOLS\post_unlock_entry_test.py" --root "%ROOT%" --minutes 6 --poll-sec 2
set "RC=%ERRORLEVEL%"

echo [5/5] DONE rc=%RC%
if "%RC%"=="0" (
  echo POST_UNLOCK_ENTRY_TEST_OK
) else (
  echo POST_UNLOCK_ENTRY_TEST_WARN_OR_FAIL rc=%RC%
)

endlocal & exit /b %RC%
