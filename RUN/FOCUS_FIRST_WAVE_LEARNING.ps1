param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$DurationMinutes = 180,
    [switch]$StopNonFirstWaveTesters = $true,
    [switch]$RefreshAudits = $true,
    [switch]$UseActivePresets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$terminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856"
$mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"
$preferredPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
$diagnosticScript = Join-Path $projectPath "RUN\SET_FIRST_WAVE_TRUTH_DIAGNOSTIC_MODE.ps1"
$applyRuntimeScript = Join-Path $projectPath "RUN\APPLY_FIRST_WAVE_BROKER_PARITY_RUNTIME.ps1"
$runtimeAuditScript = Join-Path $projectPath "RUN\BUILD_MT5_FIRST_WAVE_RUNTIME_ACTIVITY_AUDIT.ps1"
$paperLiveGapAuditScript = Join-Path $projectPath "RUN\BUILD_PAPER_LIVE_ACTION_GAP_AUDIT.ps1"
$parityAuditScript = Join-Path $projectPath "RUN\BUILD_MT5_FIRST_WAVE_SERVER_PARITY_AUDIT.ps1"
$closureAuditScript = Join-Path $projectPath "RUN\BUILD_FIRST_WAVE_LESSON_CLOSURE_AUDIT.ps1"
$tradeTransitionAuditScript = Join-Path $projectPath "RUN\BUILD_TRADE_TRANSITION_AUDIT.ps1"
$profileScript = Join-Path $projectPath "TOOLS\setup_mt5_microbots_profile.py"
$chartPlanScript = Join-Path $projectPath "TOOLS\GENERATE_MT5_SYMBOL_GROUP_CHART_PLAN.ps1"
$generateActivePresetsScript = Join-Path $projectPath "TOOLS\GENERATE_ACTIVE_LIVE_PRESETS.ps1"
$guardScript = Join-Path $projectPath "TOOLS\mt5_risk_popup_guard.ps1"
$controlSnapshotScript = Join-Path $projectPath "CONTROL\build_system_snapshot.py"
$controlHealthScript = Join-Path $projectPath "CONTROL\build_symbol_health_matrix.py"
$controlActionScript = Join-Path $projectPath "CONTROL\build_action_plan.py"
$controlWorkbenchScript = Join-Path $projectPath "CONTROL\export_codex_workbench.py"
$allowedSymbols = @("US500","EURJPY","AUDUSD","USDCAD")
$chartPlanJson = Join-Path $projectPath "EVIDENCE\OPS\first_wave_chart_plan_latest.json"
$chartPlanTxt = Join-Path $projectPath "EVIDENCE\OPS\first_wave_chart_plan_latest.txt"
$stopped = New-Object System.Collections.Generic.List[object]

function Resolve-PythonExecutable {
    param([string]$PreferredPath)

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path -LiteralPath $PreferredPath)) {
        return $PreferredPath
    }

    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    return $null
}

function Invoke-OptionalPythonHelper {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return [pscustomobject]@{
            script = $ScriptPath
            executed = $false
            status = "SCRIPT_MISSING"
        }
    }

    $pythonExe = Resolve-PythonExecutable -PreferredPath $preferredPython
    if ([string]::IsNullOrWhiteSpace($pythonExe)) {
        return [pscustomobject]@{
            script = $ScriptPath
            executed = $false
            status = "PYTHON_MISSING"
        }
    }

    try {
        & $pythonExe $ScriptPath @Arguments | Out-Null
        return [pscustomobject]@{
            script = $ScriptPath
            executed = $true
            status = "OK"
        }
    }
    catch {
        return [pscustomobject]@{
            script = $ScriptPath
            executed = $false
            status = ("FAILED: " + $_.Exception.Message)
        }
    }
}

function Stop-ProcessRow {
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    try {
        Stop-Process -Id ([int]$Row.ProcessId) -Force -ErrorAction Stop
        $stopped.Add([pscustomobject]@{
            pid = [int]$Row.ProcessId
            name = [string]$Row.Name
            reason = $Reason
        }) | Out-Null
    }
    catch {
        $stopped.Add([pscustomobject]@{
            pid = [int]$Row.ProcessId
            name = [string]$Row.Name
            reason = "$Reason|STOP_FAILED"
        }) | Out-Null
    }
}

if($StopNonFirstWaveTesters) {
    $procs = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -in @("terminal64.exe","metatester64.exe","powershell.exe","python.exe")
    }

    foreach($row in $procs) {
        $cmd = [string]$row.CommandLine
        $name = [string]$row.Name

        if($name -eq "terminal64.exe") {
            if($cmd -like "*OANDA TMS MT5 Terminal*") {
                continue
            }

            if($cmd -like "*strategy_tester*" -or $cmd -like "*MT5_NEAR_PROFIT_LAB*") {
                Stop-ProcessRow -Row $row -Reason "NON_FIRST_WAVE_TERMINAL"
                continue
            }
        }

        if($name -eq "metatester64.exe") {
            if($cmd -like "*MetaTrader 5\\metatester64.exe*" -or $cmd -like "*MT5_NEAR_PROFIT_LAB\\metatester64.exe*") {
                Stop-ProcessRow -Row $row -Reason "NON_FIRST_WAVE_METATESTER"
                continue
            }
        }

        if($name -eq "powershell.exe") {
            if($cmd -match "weakest_mt5_batch_wrapper|near_profit_optimization_after_idle_wrapper|mt5_tester_status_watcher_wrapper") {
                Stop-ProcessRow -Row $row -Reason "NON_FIRST_WAVE_WRAPPER"
                continue
            }
        }
    }

    $exporters = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "python.exe" -and [string]$_.CommandLine -like "*EXPORT_MT5_RESEARCH_DATA.py*"
    } | Sort-Object ProcessId -Descending)

    if($exporters.Count -gt 1) {
        $keep = $exporters | Select-Object -First 1
        foreach($row in ($exporters | Select-Object -Skip 1)) {
            Stop-ProcessRow -Row $row -Reason "DUPLICATE_RESEARCH_EXPORT"
        }
    }
}

$pythonExe = Resolve-PythonExecutable -PreferredPath $preferredPython
if ([string]::IsNullOrWhiteSpace($pythonExe)) {
    throw "Python executable not found for first-wave launcher."
}

if (Test-Path -LiteralPath $applyRuntimeScript) {
    & $applyRuntimeScript -ProjectRoot $projectPath | Out-Null
}

if (Test-Path -LiteralPath $chartPlanScript) {
    & $chartPlanScript -ProjectRoot $projectPath -Symbols $allowedSymbols -OutputJsonPath $chartPlanJson -OutputTxtPath $chartPlanTxt | Out-Null
}

$diagnosticResult = & $diagnosticScript -Mode Enable -ProjectRoot $projectPath -DurationMinutes $DurationMinutes | ConvertFrom-Json

$useActivePresetsResolved = $false
$activePresetRoot = Join-Path $projectPath "MQL5\Presets\ActiveLive"
$expectedActivePresets = @(
    "MicroBot_US500_Live_ACTIVE.set",
    "MicroBot_EURJPY_Live_ACTIVE.set",
    "MicroBot_AUDUSD_Live_ACTIVE.set",
    "MicroBot_USDCAD_Live_ACTIVE.set"
)

if($UseActivePresets) {
    try {
        if(Test-Path -LiteralPath $generateActivePresetsScript) {
            & $generateActivePresetsScript -ProjectRoot $projectPath -OutputRoot $activePresetRoot -AllowBlockedAuditGate | Out-Null
        }
    }
    catch {
    }

    if(Test-Path -LiteralPath $activePresetRoot) {
        $useActivePresetsResolved = $true
        foreach($presetName in $expectedActivePresets) {
            if(-not (Test-Path -LiteralPath (Join-Path $activePresetRoot $presetName))) {
                $useActivePresetsResolved = $false
                break
            }
        }
    }
}

$profileArgs = @(
    $profileScript,
    "--terminal-data-dir", $terminalDataDir,
    "--mt5-exe", $mt5Exe,
    "--profile-name", "MAKRO_I_MIKRO_BOT_AUTO",
    "--preset-root", (Join-Path $projectPath "MQL5\Presets"),
    "--chart-plan", $chartPlanJson
)
if($useActivePresetsResolved) {
    $profileArgs += "--use-active-presets"
}
$profileArgs += "--launch"

if (Test-Path -LiteralPath $guardScript) {
    Start-Process powershell -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $guardScript,
        "-Mt5DataDir", $terminalDataDir
    ) | Out-Null
    Start-Sleep -Seconds 1
}

& $pythonExe @profileArgs | Out-Null
Start-Sleep -Seconds 25

$runtimeAudit = $null
$closureAudit = $null
$parityAudit = $null
$tradeTransitionAudit = $null

if($RefreshAudits) {
    & $runtimeAuditScript | Out-Null
    & $closureAuditScript | Out-Null
    if (Test-Path -LiteralPath $paperLiveGapAuditScript) {
        & $paperLiveGapAuditScript | Out-Null
    }
    if (Test-Path -LiteralPath $tradeTransitionAuditScript) {
        & $tradeTransitionAuditScript | Out-Null
    }
    if (Test-Path -LiteralPath $parityAuditScript) {
        & $parityAuditScript | Out-Null
    }
    $runtimeAudit = Get-Content (Join-Path $projectPath "EVIDENCE\OPS\mt5_first_wave_runtime_activity_latest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $closureAudit = Get-Content (Join-Path $projectPath "EVIDENCE\OPS\first_wave_lesson_closure_latest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $parityAuditPath = Join-Path $projectPath "EVIDENCE\OPS\mt5_first_wave_server_parity_latest.json"
    if (Test-Path -LiteralPath $parityAuditPath) {
        $parityAudit = Get-Content $parityAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $tradeTransitionAuditPath = Join-Path $projectPath "EVIDENCE\OPS\first_wave_final_deploy_latest.json"
    if (Test-Path -LiteralPath $tradeTransitionAuditPath) {
        $tradeTransitionAudit = Get-Content $tradeTransitionAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

$controlHelpers = @(
    Invoke-OptionalPythonHelper -ScriptPath $controlSnapshotScript -Arguments @("--project-root", $projectPath)
    Invoke-OptionalPythonHelper -ScriptPath $controlHealthScript -Arguments @("--project-root", $projectPath)
    Invoke-OptionalPythonHelper -ScriptPath $controlActionScript -Arguments @("--project-root", $projectPath)
    Invoke-OptionalPythonHelper -ScriptPath $controlWorkbenchScript -Arguments @("--project-root", $projectPath)
)

[pscustomobject]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    project_root = $projectPath
    duration_minutes = $DurationMinutes
    allowed_symbols = $allowedSymbols
    chart_plan_json = $chartPlanJson
    profile_name = "MAKRO_I_MIKRO_BOT_AUTO"
    mt5_exe = $mt5Exe
    terminal_data_dir = $terminalDataDir
    use_active_presets = $useActivePresetsResolved
    active_presets_requested = [bool]$UseActivePresets
    active_preset_root = $activePresetRoot
    stopped_processes = @($stopped.ToArray())
    diagnostic_mode = $diagnosticResult
    runtime_activity_verdict = if($runtimeAudit) { [string]$runtimeAudit.verdict } else { $null }
    lesson_closure_verdict = if($closureAudit) { [string]$closureAudit.verdict } else { $null }
    fresh_chain_ready_count = if($closureAudit) { [int]$closureAudit.summary.fresh_chain_ready_count } else { $null }
    parity_verdict = if($parityAudit) { [string]$parityAudit.verdict } else { $null }
    runtime_profile_observed = if($parityAudit) { [string]$parityAudit.summary.runtime_profile_observed } else { $null }
    runtime_profile_target = if($parityAudit) { [string]$parityAudit.summary.runtime_profile_target } else { $null }
    runtime_profile_match = if($parityAudit) { [bool]$parityAudit.summary.runtime_profile_match } else { $null }
    final_deploy_verdict = if($tradeTransitionAudit) { [string]$tradeTransitionAudit.verdict } else { $null }
    control_helpers = $controlHelpers
} | ConvertTo-Json -Depth 10
