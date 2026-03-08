@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================================
rem OANDA_MT5_SYSTEM - HybridAgent deploy script (v3.0)
rem - copies EA + include + dll to MT5 data directory
rem - tries to compile HybridAgent via MetaEditor
rem - restarts MT5 on last profile
rem - runs full diagnostic report
rem ============================================================================

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "SOURCE_DIR=%ROOT%\MQL5"
set "LOG_DIR=%ROOT%\LOGS"
set "SERVER_NAME=OANDATMS-MT5"
set "DIAG_BAT=%ROOT%\RUN_MT5_FULL_DIAGNOSTIC.bat"
set "PY312_AVAILABLE=0"
set "PYTHON_EXE="
set "PYTHON_ARGS="

if exist "C:\OANDA_VENV\.venv\Scripts\python.exe" (
  set "PYTHON_EXE=C:\OANDA_VENV\.venv\Scripts\python.exe"
  set "PY312_AVAILABLE=1"
)
if not defined PYTHON_EXE if exist "C:\Program Files\Python312\python.exe" (
  set "PYTHON_EXE=C:\Program Files\Python312\python.exe"
  set "PY312_AVAILABLE=1"
)
if not defined PYTHON_EXE (
  where py >nul 2>&1
  if "%ERRORLEVEL%"=="0" (
    py -3.12 -c "import sys; print(sys.version_info[0])" >nul 2>&1
    if "%ERRORLEVEL%"=="0" (
      set "PYTHON_EXE=py"
      set "PYTHON_ARGS=-3.12"
      set "PY312_AVAILABLE=1"
    )
  )
)
if not defined PYTHON_EXE (
  where python >nul 2>&1
  if "%ERRORLEVEL%"=="0" (
    set "PYTHON_EXE=python"
  )
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

echo [INFO] Hybrid deploy start
echo [INFO] Source: %SOURCE_DIR%

if not exist "%SOURCE_DIR%\Experts\HybridAgent.mq5" (
  echo [ERROR] Missing source file: %SOURCE_DIR%\Experts\HybridAgent.mq5
  exit /b 1
)
if not exist "%SOURCE_DIR%\Include\zeromq_bridge.mqh" (
  echo [ERROR] Missing source include: %SOURCE_DIR%\Include\zeromq_bridge.mqh
  exit /b 2
)
if not exist "%SOURCE_DIR%\Include\Json\Json.mqh" (
  echo [ERROR] Missing source include: %SOURCE_DIR%\Include\Json\Json.mqh
  exit /b 3
)
if not exist "%SOURCE_DIR%\Libraries\libzmq.dll" (
  echo [ERROR] Missing source library: %SOURCE_DIR%\Libraries\libzmq.dll
  exit /b 4
)
if not exist "%SOURCE_DIR%\Libraries\libsodium.dll" (
  echo [ERROR] Missing source library: %SOURCE_DIR%\Libraries\libsodium.dll
  exit /b 5
)

set "TERMINAL_DATA_DIR="
set "MT5_BASE=%APPDATA%\MetaQuotes\Terminal"
if exist "%MT5_BASE%" (
  for /d %%D in ("%MT5_BASE%\*") do (
    if exist "%%~fD\config\common.ini" (
      set "TERMINAL_DATA_DIR=%%~fD"
    )
  )
)

if not defined TERMINAL_DATA_DIR (
  echo [ERROR] Could not detect MT5 data directory in %%APPDATA%%\MetaQuotes\Terminal
  exit /b 6
)

set "TARGET_DIR=%TERMINAL_DATA_DIR%\MQL5"
if not exist "%TARGET_DIR%" (
  echo [ERROR] Target MQL5 directory does not exist: %TARGET_DIR%
  exit /b 7
)

set "PF64=%ProgramW6432%"
if not defined PF64 set "PF64=%ProgramFiles%"
set "PF32=%ProgramFiles(x86)%"
if not defined PF32 set "PF32=%ProgramFiles%"

set "TERMINAL_EXE="
if not defined TERMINAL_EXE if exist "%PF64%\OANDA TMS MT5 Terminal\terminal64.exe" set "TERMINAL_EXE=%PF64%\OANDA TMS MT5 Terminal\terminal64.exe"
if not defined TERMINAL_EXE if exist "%ProgramFiles%\OANDA TMS MT5 Terminal\terminal64.exe" set "TERMINAL_EXE=%ProgramFiles%\OANDA TMS MT5 Terminal\terminal64.exe"
if not defined TERMINAL_EXE if exist "%PF32%\OANDA TMS MT5 Terminal\terminal64.exe" set "TERMINAL_EXE=%PF32%\OANDA TMS MT5 Terminal\terminal64.exe"
if not defined TERMINAL_EXE if exist "%PF64%\MetaTrader 5\terminal64.exe" set "TERMINAL_EXE=%PF64%\MetaTrader 5\terminal64.exe"
if not defined TERMINAL_EXE if exist "%ProgramFiles%\MetaTrader 5\terminal64.exe" set "TERMINAL_EXE=%ProgramFiles%\MetaTrader 5\terminal64.exe"
if not defined TERMINAL_EXE if exist "%PF32%\MetaTrader 5\terminal64.exe" set "TERMINAL_EXE=%PF32%\MetaTrader 5\terminal64.exe"

set "METAEDITOR_EXE="
if not defined METAEDITOR_EXE if exist "%PF64%\OANDA TMS MT5 Terminal\MetaEditor64.exe" set "METAEDITOR_EXE=%PF64%\OANDA TMS MT5 Terminal\MetaEditor64.exe"
if not defined METAEDITOR_EXE if exist "%ProgramFiles%\OANDA TMS MT5 Terminal\MetaEditor64.exe" set "METAEDITOR_EXE=%ProgramFiles%\OANDA TMS MT5 Terminal\MetaEditor64.exe"
if not defined METAEDITOR_EXE if exist "%PF32%\OANDA TMS MT5 Terminal\MetaEditor64.exe" set "METAEDITOR_EXE=%PF32%\OANDA TMS MT5 Terminal\MetaEditor64.exe"
if not defined METAEDITOR_EXE if exist "%PF64%\MetaTrader 5\MetaEditor64.exe" set "METAEDITOR_EXE=%PF64%\MetaTrader 5\MetaEditor64.exe"
if not defined METAEDITOR_EXE if exist "%ProgramFiles%\MetaTrader 5\MetaEditor64.exe" set "METAEDITOR_EXE=%ProgramFiles%\MetaTrader 5\MetaEditor64.exe"
if not defined METAEDITOR_EXE if exist "%PF32%\MetaTrader 5\MetaEditor64.exe" set "METAEDITOR_EXE=%PF32%\MetaTrader 5\MetaEditor64.exe"

echo [INFO] Target data dir: %TERMINAL_DATA_DIR%
echo [INFO] Target MQL5 dir: %TARGET_DIR%
if defined TERMINAL_EXE echo [INFO] terminal64.exe: %TERMINAL_EXE%
if defined METAEDITOR_EXE echo [INFO] MetaEditor64.exe: %METAEDITOR_EXE%

echo [STEP] Enforcing MT5 Algo/DLL settings in common.ini
call "%ROOT%\FIX_MT5_AUTOTRADE.bat" -NoRestart
if errorlevel 1 (
  echo [WARN] FIX_MT5_AUTOTRADE returned non-zero. Continuing with deploy.
)

echo [STEP] Stopping MT5/MetaEditor processes to avoid DLL sharing conflicts
taskkill /IM terminal64.exe /F /T >nul 2>&1
taskkill /IM metaeditor64.exe /F /T >nul 2>&1
timeout /t 2 /nobreak >nul

echo [STEP] Copy HybridAgent source files
call :copy_file "%SOURCE_DIR%\Experts\HybridAgent.mq5" "%TARGET_DIR%\Experts\HybridAgent.mq5" || exit /b 20
call :copy_file "%SOURCE_DIR%\Include\zeromq_bridge.mqh" "%TARGET_DIR%\Include\zeromq_bridge.mqh" || exit /b 21
call :copy_file "%SOURCE_DIR%\Include\Json\Json.mqh" "%TARGET_DIR%\Include\Json\Json.mqh" || exit /b 22

echo [STEP] Copy runtime libraries
call :copy_file "%SOURCE_DIR%\Libraries\libzmq.dll" "%TARGET_DIR%\Libraries\libzmq.dll" || exit /b 23
call :copy_file "%SOURCE_DIR%\Libraries\libsodium.dll" "%TARGET_DIR%\Libraries\libsodium.dll" || exit /b 24

set "COMPILE_LOG=%LOG_DIR%\MT5_COMPILE_HybridAgent.log"
set "COMPILE_OK=0"
if defined METAEDITOR_EXE (
  echo [STEP] Compiling HybridAgent via MetaEditor
  "%METAEDITOR_EXE%" /compile:"%TARGET_DIR%\Experts\HybridAgent.mq5" /log:"%COMPILE_LOG%"
  set "COMPILE_RC=%ERRORLEVEL%"
  if "!COMPILE_RC!"=="0" (
    findstr /I /C:"0 error(s), 0 warning(s)" /C:"0 errors, 0 warnings" "%COMPILE_LOG%" >nul 2>&1
    if "!ERRORLEVEL!"=="0" (
      set "COMPILE_OK=1"
      echo [SUCCESS] Compile OK (0 errors, 0 warnings)
    ) else (
      echo [WARN] Compile finished, check log: %COMPILE_LOG%
    )
  ) else (
    echo [WARN] MetaEditor compile returned code !COMPILE_RC!. Check: %COMPILE_LOG%
  )
) else (
  echo [WARN] MetaEditor64.exe not found - compile skipped.
)

set "PROFILE_LAST=Default"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command ^
  "$ini=Join-Path '%TERMINAL_DATA_DIR%' 'config\common.ini';" ^
  "if(Test-Path $ini){" ^
  "  $sec=''; $val='';" ^
  "  foreach($l in Get-Content $ini -Encoding UTF8){" ^
  "    $t=$l.Trim();" ^
  "    if($t -match '^\[.*\]$'){ $sec=$t; continue };" ^
  "    if($sec -ieq '[Charts]' -and $t -match '^\s*ProfileLast\s*=\s*(.+)\s*$'){ $val=$matches[1].Trim(); break }" ^
  "  };" ^
  "  if([string]::IsNullOrWhiteSpace($val)){$val='Default'};" ^
  "  Write-Output $val" ^
  "}"`) do set "PROFILE_LAST=%%I"

if defined TERMINAL_EXE (
  echo [STEP] Restarting MT5 with profile: %PROFILE_LAST%
  start "" "%TERMINAL_EXE%" /profile:"%PROFILE_LAST%"
  timeout /t 3 /nobreak >nul
) else (
  echo [WARN] terminal64.exe not found - restart skipped.
)

set "DIAG_RC=0"
if exist "%DIAG_BAT%" (
  echo [STEP] Running full MT5 diagnostic
  call "%DIAG_BAT%"
  set "DIAG_RC=%ERRORLEVEL%"
  if not "!DIAG_RC!"=="0" (
    echo [WARN] Diagnostic returned rc=!DIAG_RC!
  )
) else (
  echo [WARN] Diagnostic script not found: %DIAG_BAT%
)

echo [STEP] Ensuring Wave-1 MT5 symbols are selected/visible (AUDJPY/NZDJPY)
if exist "%ROOT%\TOOLS\mt5_symbol_select.py" (
  if defined PYTHON_EXE (
    call :run_python "%ROOT%\TOOLS\mt5_symbol_select.py" --mt5-path "%TERMINAL_EXE%" --symbols AUDJPY NZDJPY --out "%ROOT%\RUN\mt5_symbol_select_report.json"
  ) else (
    echo [WARN] Python executable not found - symbol select skipped.
  )
  if not "%ERRORLEVEL%"=="0" (
    echo [WARN] Symbol select utility returned non-zero rc=%ERRORLEVEL%
  )
) else (
  echo [WARN] Missing symbol-select utility: %ROOT%\TOOLS\mt5_symbol_select.py
)

echo [STEP] Refreshing symbols audit + preflight artifacts
if exist "%ROOT%\TOOLS\audit_symbols_get_mt5.py" (
  if defined PYTHON_EXE (
    call :run_python "%ROOT%\TOOLS\audit_symbols_get_mt5.py" --mt5-path "%TERMINAL_EXE%" --out "%ROOT%\EVIDENCE\symbols_get_audit\latest_symbols_get_audit.json"
  ) else (
    echo [WARN] Python executable not found - symbols audit skipped.
  )
  if exist "%ROOT%\EVIDENCE\symbols_get_audit\latest_symbols_get_audit.json" (
    copy /Y "%ROOT%\EVIDENCE\symbols_get_audit\latest_symbols_get_audit.json" "%ROOT%\RUN\symbols_audit_now.json" >nul
  )
) else (
  echo [WARN] Missing symbols audit tool: %ROOT%\TOOLS\audit_symbols_get_mt5.py
)

if exist "%ROOT%\TOOLS\generate_asia_preflight_evidence.py" (
  if defined PYTHON_EXE (
    call :run_python "%ROOT%\TOOLS\generate_asia_preflight_evidence.py"
  ) else (
    echo [WARN] Python executable not found - asia preflight skipped.
  )
) else (
  echo [WARN] Missing tool: %ROOT%\TOOLS\generate_asia_preflight_evidence.py
)
if exist "%ROOT%\TOOLS\no_live_drift_check.py" (
  if defined PYTHON_EXE (
    call :run_python "%ROOT%\TOOLS\no_live_drift_check.py"
  ) else (
    echo [WARN] Python executable not found - drift check skipped.
  )
) else (
  echo [WARN] Missing tool: %ROOT%\TOOLS\no_live_drift_check.py
)

echo [INFO] Symbols configured in CONFIG\strategy.json:
powershell -NoProfile -Command ^
  "$p=Join-Path '%ROOT%' 'CONFIG\strategy.json';" ^
  "if(Test-Path $p){$j=Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json; if($j.symbols_to_trade){$j.symbols_to_trade | ForEach-Object { Write-Output (' - ' + $_) }}}"

echo.
echo [FINAL] Deploy finished.
echo [FINAL] Data dir : %TERMINAL_DATA_DIR%
echo [FINAL] MQL5 dir : %TARGET_DIR%
echo [FINAL] Compile  : %COMPILE_OK%  (1=ok,0=check log)
echo [FINAL] Diag rc  : %DIAG_RC%
echo.
echo [NEXT] Verify in MT5:
echo [NEXT] 1) Algo Trading is ON (green).
echo [NEXT] 2) On each required chart you see "HybridAgent" in top-right corner.
echo [NEXT] 3) In Experts/Journal there are "loaded successfully" entries and no critical errors.
echo.
exit /b 0

:run_python
if not defined PYTHON_EXE (
  exit /b 9009
)
if /I "%PYTHON_EXE%"=="py" (
  py %PYTHON_ARGS% %*
) else (
  "%PYTHON_EXE%" %*
)
exit /b %ERRORLEVEL%

:copy_file
set "SRC=%~1"
set "DST=%~2"
set "DST_DIR=%~dp2"
if not exist "%DST_DIR%" mkdir "%DST_DIR%" >nul 2>&1
if not exist "%SRC%" (
  echo [ERROR] Missing source: %SRC%
  exit /b 1
)
copy /Y "%SRC%" "%DST%" >nul
if errorlevel 1 (
  echo [ERROR] Copy failed: %SRC% -> %DST%
  exit /b 1
)
echo [OK] %~nx1
exit /b 0
