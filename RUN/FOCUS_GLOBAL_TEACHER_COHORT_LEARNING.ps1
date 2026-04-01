param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$LaunchWaitSeconds = 45,
    [string]$ProfileName = "MAKRO_I_MIKRO_BOT_AUTO",
    [int]$DiagnosticDurationMinutes = 120,
    [switch]$StopNonTargetTesters = $true,
    [switch]$RefreshAudits = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$learningUniverseContractPath = Join-Path $projectPath "CONFIG\learning_universe_contract.json"
$chartPlanJson = Join-Path $projectPath "EVIDENCE\OPS\global_teacher_cohort_chart_plan_latest.json"
$chartPlanTxt = Join-Path $projectPath "EVIDENCE\OPS\global_teacher_cohort_chart_plan_latest.txt"
$chartPlanScript = Join-Path $projectPath "TOOLS\GENERATE_MT5_SYMBOL_GROUP_CHART_PLAN.ps1"
$syncRuntimeScript = Join-Path $projectPath "RUN\SYNC_MT5_ML_RUNTIME_STATE.ps1"
$exportPackageScript = Join-Path $projectPath "RUN\EXPORT_MT5_PAPER_GATE_PACKAGE.ps1"
$healthRegistryScript = Join-Path $projectPath "RUN\BUILD_LEARNING_HEALTH_REGISTRY.ps1"
$trainingReadinessScript = Join-Path $projectPath "RUN\BUILD_INSTRUMENT_TRAINING_READINESS_REPORT.ps1"
$auditScript = Join-Path $projectPath "RUN\BUILD_GLOBAL_TEACHER_COHORT_ACTIVITY_AUDIT.ps1"
$diagnosticScript = Join-Path $projectPath "RUN\SET_GLOBAL_TEACHER_COHORT_DIAGNOSTIC_MODE.ps1"
$profileScript = Join-Path $projectPath "TOOLS\setup_mt5_microbots_profile.py"
$guardScript = Join-Path $projectPath "TOOLS\mt5_risk_popup_guard.ps1"
$controlSnapshotScript = Join-Path $projectPath "CONTROL\build_system_snapshot.py"
$controlHealthScript = Join-Path $projectPath "CONTROL\build_symbol_health_matrix.py"
$controlWorkbenchScript = Join-Path $projectPath "CONTROL\export_codex_workbench.py"
$learningSupervisorMatrixScript = Join-Path $projectPath "CONTROL\build_learning_supervisor_matrix.py"
$learningActionPlanScript = Join-Path $projectPath "CONTROL\build_learning_action_plan.py"
$terminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856"
$mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"
$preferredPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"

$stopped = New-Object System.Collections.Generic.List[object]

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-GlobalTeacherSymbols {
    param([string]$ContractPath)

    $payload = Read-JsonSafe -Path $ContractPath
    if ($null -eq $payload -or $null -eq $payload.symbols) {
        return @("DE30","GOLD","SILVER","USDJPY","USDCHF","COPPER-US","EURAUD","EURUSD","GBPUSD")
    }

    $resolved = New-Object System.Collections.Generic.List[string]
    foreach ($property in $payload.symbols.PSObject.Properties) {
        if ([string]$property.Value.cohort -eq "GLOBAL_TEACHER") {
            $resolved.Add([string]$property.Name) | Out-Null
        }
    }

    if ($resolved.Count -le 0) {
        return @("DE30","GOLD","SILVER","USDJPY","USDCHF","COPPER-US","EURAUD","EURUSD","GBPUSD")
    }

    return @($resolved.ToArray())
}

$targetSymbols = Get-GlobalTeacherSymbols -ContractPath $learningUniverseContractPath

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

if ($StopNonTargetTesters) {
    $procs = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -in @("terminal64.exe","metatester64.exe","powershell.exe","python.exe")
    }

    foreach ($row in $procs) {
        $cmd = [string]$row.CommandLine
        $name = [string]$row.Name

        if ($name -eq "terminal64.exe") {
            if ($cmd -like "*strategy_tester*" -or $cmd -like "*MT5_NEAR_PROFIT_LAB*") {
                Stop-ProcessRow -Row $row -Reason "NON_GLOBAL_TEACHER_TERMINAL"
                continue
            }
        }

        if ($name -eq "metatester64.exe") {
            Stop-ProcessRow -Row $row -Reason "NON_GLOBAL_TEACHER_METATESTER"
            continue
        }

        if ($name -eq "powershell.exe") {
            if ($cmd -match "weakest_mt5_batch_wrapper|near_profit_optimization_after_idle_wrapper|mt5_tester_status_watcher_wrapper") {
                Stop-ProcessRow -Row $row -Reason "NON_GLOBAL_TEACHER_WRAPPER"
                continue
            }
        }
    }
}

& $syncRuntimeScript -ProjectRoot $projectPath | Out-Null
& $exportPackageScript -ProjectRoot $projectPath | Out-Null
& $healthRegistryScript -ProjectRoot $projectPath | Out-Null
& $trainingReadinessScript -ProjectRoot $projectPath | Out-Null
& $chartPlanScript -ProjectRoot $projectPath -Symbols $targetSymbols -OutputJsonPath $chartPlanJson -OutputTxtPath $chartPlanTxt | Out-Null
$diagnosticResult = & $diagnosticScript -Mode Enable -ProjectRoot $projectPath -DurationMinutes $DiagnosticDurationMinutes | ConvertFrom-Json

Start-Process powershell -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $guardScript,
    "-Mt5DataDir", $terminalDataDir
) | Out-Null
Start-Sleep -Seconds 1

& python $profileScript `
    --terminal-data-dir $terminalDataDir `
    --mt5-exe $mt5Exe `
    --profile-name $profileName `
    --preset-root (Join-Path $projectPath "MQL5\Presets") `
    --chart-plan $chartPlanJson `
    --launch | Out-Null

Start-Sleep -Seconds $LaunchWaitSeconds

$audit = $null
if ($RefreshAudits) {
    $audit = & $auditScript -ProjectRoot $projectPath -Symbols $targetSymbols | ConvertFrom-Json
}

$controlHelpers = @(
    Invoke-OptionalPythonHelper -ScriptPath $controlSnapshotScript -Arguments @("--project-root", $projectPath)
    Invoke-OptionalPythonHelper -ScriptPath $controlHealthScript -Arguments @("--project-root", $projectPath)
    Invoke-OptionalPythonHelper -ScriptPath $learningSupervisorMatrixScript -Arguments @("--project-root", $projectPath)
    Invoke-OptionalPythonHelper -ScriptPath $learningActionPlanScript -Arguments @("--project-root", $projectPath)
    Invoke-OptionalPythonHelper -ScriptPath $controlWorkbenchScript -Arguments @("--project-root", $projectPath)
)

[pscustomobject]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    project_root = $projectPath
    profile_name = $profileName
    mt5_exe = $mt5Exe
    chart_plan_json = $chartPlanJson
    target_symbols = $targetSymbols
    stopped_processes = @($stopped.ToArray())
    diagnostic_mode = $diagnosticResult
    verdict = if ($null -ne $audit) { [string]$audit.verdict } else { $null }
    teacher_runtime_active_count = if ($null -ne $audit) { [int]$audit.summary.teacher_runtime_active_count } else { 0 }
    fresh_full_lesson_count = if ($null -ne $audit) { [int]$audit.summary.fresh_full_lesson_count } else { 0 }
    control_helpers = $controlHelpers
} | ConvertTo-Json -Depth 8
