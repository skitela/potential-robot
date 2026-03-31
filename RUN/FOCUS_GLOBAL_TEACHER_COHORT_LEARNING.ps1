param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$LaunchWaitSeconds = 45,
    [switch]$StopNonTargetTesters = $true,
    [switch]$RefreshAudits = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$targetSymbols = @("DE30","GOLD","SILVER","USDJPY","USDCHF","COPPER-US","EURAUD","EURUSD","GBPUSD")
$chartPlanJson = Join-Path $projectPath "EVIDENCE\OPS\global_teacher_cohort_chart_plan_latest.json"
$chartPlanTxt = Join-Path $projectPath "EVIDENCE\OPS\global_teacher_cohort_chart_plan_latest.txt"
$chartPlanScript = Join-Path $projectPath "TOOLS\GENERATE_MT5_SYMBOL_GROUP_CHART_PLAN.ps1"
$syncRuntimeScript = Join-Path $projectPath "RUN\SYNC_MT5_ML_RUNTIME_STATE.ps1"
$exportPackageScript = Join-Path $projectPath "RUN\EXPORT_MT5_PAPER_GATE_PACKAGE.ps1"
$healthRegistryScript = Join-Path $projectPath "RUN\BUILD_LEARNING_HEALTH_REGISTRY.ps1"
$trainingReadinessScript = Join-Path $projectPath "RUN\BUILD_INSTRUMENT_TRAINING_READINESS_REPORT.ps1"
$auditScript = Join-Path $projectPath "RUN\BUILD_GLOBAL_TEACHER_COHORT_ACTIVITY_AUDIT.ps1"
$profileScript = Join-Path $projectPath "TOOLS\setup_mt5_microbots_profile.py"
$guardScript = Join-Path $projectPath "TOOLS\mt5_risk_popup_guard.ps1"
$terminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856"
$mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"
$profileName = "MAKRO_I_MIKRO_BOT_GLOBAL_TEACHER_AUTO"

$stopped = New-Object System.Collections.Generic.List[object]

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

[pscustomobject]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    project_root = $projectPath
    profile_name = $profileName
    mt5_exe = $mt5Exe
    chart_plan_json = $chartPlanJson
    target_symbols = $targetSymbols
    stopped_processes = @($stopped.ToArray())
    verdict = if ($null -ne $audit) { [string]$audit.verdict } else { $null }
    teacher_runtime_active_count = if ($null -ne $audit) { [int]$audit.summary.teacher_runtime_active_count } else { 0 }
    fresh_full_lesson_count = if ($null -ne $audit) { [int]$audit.summary.fresh_full_lesson_count } else { 0 }
} | ConvertTo-Json -Depth 8
