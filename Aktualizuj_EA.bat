@echo off
setlocal EnableExtensions EnableDelayedExpansion

if /I not "%~1"=="__quiet_inner" (
  set "DEPLOY_STDOUT=%TEMP%\oanda_mt5_deploy_%RANDOM%_%RANDOM%.out"
  set "DEPLOY_STDERR=%TEMP%\oanda_mt5_deploy_%RANDOM%_%RANDOM%.err"
  call "%~f0" __quiet_inner %* > "!DEPLOY_STDOUT!" 2> "!DEPLOY_STDERR!"
  set "INNER_RC=%ERRORLEVEL%"
  if exist "!DEPLOY_STDOUT!" type "!DEPLOY_STDOUT!"
  if exist "!DEPLOY_STDERR!" (
    findstr /V /C:"ERROR: Input redirection is not supported, exiting the process immediately." "!DEPLOY_STDERR!"
  )
  if exist "!DEPLOY_STDOUT!" del /q "!DEPLOY_STDOUT!" >nul 2>&1
  if exist "!DEPLOY_STDERR!" del /q "!DEPLOY_STDERR!" >nul 2>&1
  exit /b !INNER_RC!
)
shift

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
set "PYTHON_MT5_EXE="
set "PYTHON_MT5_ARGS="

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
  if not errorlevel 1 (
    py -3.12 -c "import sys; print(sys.version_info[0])" >nul 2>&1
    if not errorlevel 1 (
      set "PYTHON_EXE=py"
      set "PYTHON_ARGS=-3.12"
      set "PY312_AVAILABLE=1"
    )
  )
)
if not defined PYTHON_EXE (
  where python >nul 2>&1
  if not errorlevel 1 (
    set "PYTHON_EXE=python"
  )
)
if defined PYTHON_EXE (
  set "PYTHON_MT5_EXE=%PYTHON_EXE%"
  set "PYTHON_MT5_ARGS=%PYTHON_ARGS%"
)
call :resolve_mt5_python

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
if not exist "%SOURCE_DIR%\Include\KernelTypes_v1.mqh" (
  echo [ERROR] Missing source include: %SOURCE_DIR%\Include\KernelTypes_v1.mqh
  exit /b 8
)
if not exist "%SOURCE_DIR%\Include\StateCache_v1.mqh" (
  echo [ERROR] Missing source include: %SOURCE_DIR%\Include\StateCache_v1.mqh
  exit /b 9
)
if not exist "%SOURCE_DIR%\Include\InstrumentProfileCache_v2.mqh" (
  echo [ERROR] Missing source include: %SOURCE_DIR%\Include\InstrumentProfileCache_v2.mqh
  exit /b 10
)
if not exist "%SOURCE_DIR%\Include\LiveConfigLoader_v2.mqh" (
  echo [ERROR] Missing source include: %SOURCE_DIR%\Include\LiveConfigLoader_v2.mqh
  exit /b 11
)
if not exist "%SOURCE_DIR%\Include\CircuitBreaker_v2.mqh" (
  echo [ERROR] Missing source include: %SOURCE_DIR%\Include\CircuitBreaker_v2.mqh
  exit /b 12
)
if not exist "%SOURCE_DIR%\Include\DecisionKernel_v1.mqh" (
  echo [ERROR] Missing source include: %SOURCE_DIR%\Include\DecisionKernel_v1.mqh
  exit /b 13
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
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$server='%SERVER_NAME%';" ^
  "function Get-IniValue { param([string[]]$Lines,[string]$Section,[string]$Key) $sec='['+$Section+']'; $inSection=$false; foreach($line in $Lines){ $t=$line.Trim(); if($t -match '^\[.*\]$'){ $inSection=($t -ieq $sec); continue }; if(-not $inSection){ continue }; if($t -match ('^' + [regex]::Escape($Key) + '\s*=(.*)$')){ return $matches[1].Trim() } }; return '' };" ^
  "$base = Join-Path $env:APPDATA 'MetaQuotes\Terminal';" ^
  "if(-not (Test-Path $base)){ exit 0 };" ^
  "$best=$null; $bestScore=-1;" ^
  "Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {" ^
  "  $ini = Join-Path $_.FullName 'config\common.ini';" ^
  "  if(-not (Test-Path $ini)){ return };" ^
  "  $lines = Get-Content $ini -Encoding UTF8;" ^
  "  $srv = Get-IniValue -Lines $lines -Section 'Common' -Key 'Server';" ^
  "  $score = 1;" ^
  "  if($srv -ieq $server){ $score += 1000 };" ^
  "  try { $score += [int]((Get-Item $ini).LastWriteTimeUtc.ToFileTimeUtc() / 10000000) } catch {};" ^
  "  if($score -gt $bestScore){ $bestScore=$score; $best=$_.FullName }" ^
  "};" ^
  "if($best){ Write-Output $best }"`) do set "TERMINAL_DATA_DIR=%%I"

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
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$names=@('terminal64','metaeditor64'); Get-Process -Name $names -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue"
timeout /t 2 /nobreak >nul

echo [STEP] Copy HybridAgent source files
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Experts\HybridAgent.mq5" -Destination "%TARGET_DIR%\Experts\HybridAgent.mq5" || exit /b 20
echo [OK] HybridAgent.mq5
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Include\zeromq_bridge.mqh" -Destination "%TARGET_DIR%\Include\zeromq_bridge.mqh" || exit /b 21
echo [OK] zeromq_bridge.mqh
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Include\Json\Json.mqh" -Destination "%TARGET_DIR%\Include\Json\Json.mqh" || exit /b 22
echo [OK] Json.mqh
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Include\KernelTypes_v1.mqh" -Destination "%TARGET_DIR%\Include\KernelTypes_v1.mqh" || exit /b 25
echo [OK] KernelTypes_v1.mqh
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Include\StateCache_v1.mqh" -Destination "%TARGET_DIR%\Include\StateCache_v1.mqh" || exit /b 26
echo [OK] StateCache_v1.mqh
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Include\InstrumentProfileCache_v2.mqh" -Destination "%TARGET_DIR%\Include\InstrumentProfileCache_v2.mqh" || exit /b 27
echo [OK] InstrumentProfileCache_v2.mqh
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Include\LiveConfigLoader_v2.mqh" -Destination "%TARGET_DIR%\Include\LiveConfigLoader_v2.mqh" || exit /b 28
echo [OK] LiveConfigLoader_v2.mqh
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Include\CircuitBreaker_v2.mqh" -Destination "%TARGET_DIR%\Include\CircuitBreaker_v2.mqh" || exit /b 29
echo [OK] CircuitBreaker_v2.mqh
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Include\DecisionKernel_v1.mqh" -Destination "%TARGET_DIR%\Include\DecisionKernel_v1.mqh" || exit /b 30
echo [OK] DecisionKernel_v1.mqh

echo [STEP] Copy runtime libraries
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Libraries\libzmq.dll" -Destination "%TARGET_DIR%\Libraries\libzmq.dll"
if errorlevel 1 (
  if exist "%TARGET_DIR%\Libraries\libzmq.dll" (
    echo [WARN] Runtime library locked, keeping existing file: libzmq.dll
  ) else (
    exit /b 23
  )
) else (
  echo [OK] libzmq.dll
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\TOOLS\copy_if_needed.ps1" -Source "%SOURCE_DIR%\Libraries\libsodium.dll" -Destination "%TARGET_DIR%\Libraries\libsodium.dll"
if errorlevel 1 (
  if exist "%TARGET_DIR%\Libraries\libsodium.dll" (
    echo [WARN] Runtime library locked, keeping existing file: libsodium.dll
  ) else (
    exit /b 24
  )
) else (
  echo [OK] libsodium.dll
)

set "COMPILE_LOG=%LOG_DIR%\MT5_COMPILE_HybridAgent.log"
set "COMPILE_OK=0"
call :compile_hybrid_agent

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
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process -FilePath '%TERMINAL_EXE%' -ArgumentList '/profile:%PROFILE_LAST%' -WindowStyle Minimized"
  timeout /t 3 /nobreak >nul
) else (
  echo [WARN] terminal64.exe not found - restart skipped.
)

set "DIAG_RC=0"
if exist "%DIAG_BAT%" (
  echo [STEP] Running full MT5 diagnostic
  set "DIAG_VERDICT="
  for /L %%N in (1,1,3) do (
    call "%DIAG_BAT%"
    set "DIAG_RC=!ERRORLEVEL!"
    set "DIAG_VERDICT="
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$dir=Join-Path '%ROOT%' 'RUN\\DIAG_REPORTS';" ^
      "if(Test-Path $dir){" ^
      "  $latest=Get-ChildItem $dir -Filter 'MT5_FULL_DIAG_*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1;" ^
      "  if($latest){" ^
      "    $hit=Select-String -Path $latest.FullName -Pattern '^verdict=(.+)$' | Select-Object -First 1;" ^
      "    if($hit){ Write-Output $hit.Matches[0].Groups[1].Value.Trim() }" ^
      "  }" ^
      "}"`) do set "DIAG_VERDICT=%%I"
    if /I "!DIAG_VERDICT!"=="PASS" set "DIAG_RC=0"
    if "!DIAG_RC!"=="0" goto :diag_ok
    if %%N LSS 3 (
      echo [WARN] Diagnostic not ready yet ^(attempt %%N/3, verdict=!DIAG_VERDICT!^). Retrying...
      timeout /t 5 /nobreak >nul
    )
  )
  :diag_ok
  if not "!DIAG_RC!"=="0" (
    echo [WARN] Diagnostic returned rc=!DIAG_RC!
  )
) else (
  echo [WARN] Diagnostic script not found: %DIAG_BAT%
)

echo [STEP] Ensuring Wave-1 MT5 symbols are selected/visible (AUDJPY/NZDJPY)
if exist "%ROOT%\TOOLS\mt5_symbol_select.py" (
  if defined PYTHON_MT5_EXE (
    call :run_mt5_python "%ROOT%\TOOLS\mt5_symbol_select.py" --mt5-path "%TERMINAL_EXE%" --symbols AUDJPY NZDJPY --out "%ROOT%\RUN\mt5_symbol_select_report.json"
  ) else (
    echo [WARN] Python with MetaTrader5 package not found - symbol select skipped.
  )
  if errorlevel 1 (
    echo [WARN] Symbol select utility returned non-zero rc=!ERRORLEVEL!
  )
) else (
  echo [WARN] Missing symbol-select utility: %ROOT%\TOOLS\mt5_symbol_select.py
)

echo [STEP] Refreshing symbols audit + preflight artifacts
if exist "%ROOT%\TOOLS\audit_symbols_get_mt5.py" (
  if defined PYTHON_MT5_EXE (
    call :run_mt5_python "%ROOT%\TOOLS\audit_symbols_get_mt5.py" --mt5-path "%TERMINAL_EXE%" --out "%ROOT%\EVIDENCE\symbols_get_audit\latest_symbols_get_audit.json"
  ) else (
    echo [WARN] Python with MetaTrader5 package not found - symbols audit skipped.
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

:run_mt5_python
if not defined PYTHON_MT5_EXE (
  exit /b 9009
)
if /I "%PYTHON_MT5_EXE%"=="py" (
  py %PYTHON_MT5_ARGS% %*
) else (
  "%PYTHON_MT5_EXE%" %*
)
exit /b %ERRORLEVEL%

:compile_hybrid_agent
if not defined METAEDITOR_EXE (
  echo [WARN] MetaEditor64.exe not found - compile skipped.
  exit /b 0
)
echo [STEP] Compiling HybridAgent via MetaEditor
start "" /wait "%METAEDITOR_EXE%" /compile:"%TARGET_DIR%\Experts\HybridAgent.mq5" /log:"%COMPILE_LOG%" >nul 2>&1
if not exist "%COMPILE_LOG%" (
  echo [WARN] Compile log missing after MetaEditor run: %COMPILE_LOG%
  exit /b 0
)
set "COMPILE_MATCH="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$log='%COMPILE_LOG%';" ^
  "if(Test-Path $log){" ^
  "  $hit=Select-String -Path $log -Pattern 'Result: 0 errors, 0 warnings','0 error(s), 0 warning(s)' -SimpleMatch | Select-Object -First 1;" ^
  "  if($hit){ Write-Output 'MATCH' }" ^
  "}"`) do set "COMPILE_MATCH=%%I"
if /I "%COMPILE_MATCH%"=="MATCH" (
  set "COMPILE_OK=1"
  echo [SUCCESS] Compile OK ^(0 errors, 0 warnings^)
) else (
  echo [WARN] Compile finished, check log: %COMPILE_LOG%
)
exit /b 0

:resolve_mt5_python
if defined PYTHON_MT5_EXE (
  call :python_can_import_mt5 "%PYTHON_MT5_EXE%" "%PYTHON_MT5_ARGS%"
  if not errorlevel 1 exit /b 0
)

if exist "C:\Users\skite\AppData\Local\Programs\Python\Python312\python.exe" (
  call :python_can_import_mt5 "C:\Users\skite\AppData\Local\Programs\Python\Python312\python.exe" ""
  if not errorlevel 1 (
    set "PYTHON_MT5_EXE=C:\Users\skite\AppData\Local\Programs\Python\Python312\python.exe"
    set "PYTHON_MT5_ARGS="
    exit /b 0
  )
)

where py >nul 2>&1
if not errorlevel 1 (
  call :python_can_import_mt5 "py" "-3.12"
  if not errorlevel 1 (
    set "PYTHON_MT5_EXE=py"
    set "PYTHON_MT5_ARGS=-3.12"
    exit /b 0
  )
)

where python >nul 2>&1
if not errorlevel 1 (
  call :python_can_import_mt5 "python" ""
  if not errorlevel 1 (
    set "PYTHON_MT5_EXE=python"
    set "PYTHON_MT5_ARGS="
    exit /b 0
  )
)

set "PYTHON_MT5_EXE="
set "PYTHON_MT5_ARGS="
exit /b 0

:python_can_import_mt5
set "CHECK_EXE=%~1"
set "CHECK_ARGS=%~2"
if /I "%CHECK_EXE%"=="py" (
  py %CHECK_ARGS% -c "import MetaTrader5" >nul 2>&1
) else (
  "%CHECK_EXE%" -c "import MetaTrader5" >nul 2>&1
)
exit /b %ERRORLEVEL%
