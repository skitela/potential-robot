param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$UsbRoot = "C:\GLOBALNY HANDEL VER1\OANDAKEY",
    [switch]$SkipCompile,
    [switch]$SkipPackage,
    [switch]$SkipTokenSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $started = (Get-Date).ToUniversalTime().ToString("o")
    & $Action
    return [pscustomobject]@{
        step = $Name
        started_utc = $started
        finished_utc = (Get-Date).ToUniversalTime().ToString("o")
        status = "OK"
    }
}

$steps = @()

if (-not $SkipTokenSync) {
    $steps += Invoke-Step -Name "sync_tokens" -Action {
        & (Join-Path $ProjectRoot "TOOLS\SYNC_ALL_OANDAKEY_TOKENS.ps1") -ProjectRoot $ProjectRoot -UsbRoot $UsbRoot | Out-Null
    }
}

if (-not $SkipCompile) {
    $steps += Invoke-Step -Name "compile_all_microbots" -Action {
        & (Join-Path $ProjectRoot "TOOLS\COMPILE_ALL_MICROBOTS.ps1") | Out-Null
    }
}

$steps += Invoke-Step -Name "validate_project_layout" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_PROJECT_LAYOUT.ps1") | Out-Null
}

$steps += Invoke-Step -Name "validate_symbol_policy_consistency" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1") | Out-Null
}

$steps += Invoke-Step -Name "generate_family_policy_registry" -Action {
    & (Join-Path $ProjectRoot "TOOLS\GENERATE_FAMILY_POLICY_REGISTRY.ps1") | Out-Null
}

$steps += Invoke-Step -Name "validate_family_policy_bounds" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_FAMILY_POLICY_BOUNDS.ps1") | Out-Null
}

$steps += Invoke-Step -Name "generate_family_reference_registry" -Action {
    & (Join-Path $ProjectRoot "TOOLS\GENERATE_FAMILY_REFERENCE_REGISTRY.ps1") | Out-Null
}

$steps += Invoke-Step -Name "generate_active_live_presets" -Action {
    & (Join-Path $ProjectRoot "TOOLS\GENERATE_ACTIVE_LIVE_PRESETS.ps1") | Out-Null
}

$steps += Invoke-Step -Name "validate_family_reference_registry" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_FAMILY_REFERENCE_REGISTRY.ps1") | Out-Null
}

$steps += Invoke-Step -Name "validate_preset_safety" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_PRESET_SAFETY.ps1") | Out-Null
}

$steps += Invoke-Step -Name "validate_deployment_readiness" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_DEPLOYMENT_READINESS.ps1") | Out-Null
}

$steps += Invoke-Step -Name "run_contract_tests" -Action {
    & (Join-Path $ProjectRoot "TESTS\RUN_CONTRACT_TESTS.ps1") | Out-Null
}

$steps += Invoke-Step -Name "validate_prelive_gonogo" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_PRELIVE_GONOGO.ps1") | Out-Null
}

$steps += Invoke-Step -Name "run_resilience_drills" -Action {
    & (Join-Path $ProjectRoot "TOOLS\RUN_RESILIENCE_DRILLS.ps1") | Out-Null
}

$steps += Invoke-Step -Name "generate_family_operator_report" -Action {
    & (Join-Path $ProjectRoot "TOOLS\GENERATE_FAMILY_OPERATOR_REPORT.ps1") | Out-Null
}

$steps += Invoke-Step -Name "apply_paper_live_runtime" -Action {
    & (Join-Path $ProjectRoot "TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1") -RuntimeProfile PAPER_LIVE | Out-Null
}

$steps += Invoke-Step -Name "generate_runtime_control_summary" -Action {
    & (Join-Path $ProjectRoot "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1") | Out-Null
}

$steps += Invoke-Step -Name "run_runtime_watchdog" -Action {
    & (Join-Path $ProjectRoot "TOOLS\RUN_RUNTIME_WATCHDOG_PL.ps1") -ProjectRoot $ProjectRoot -NoRepair | Out-Null
}

$steps += Invoke-Step -Name "generate_daily_system_reports" -Action {
    & (Join-Path $ProjectRoot "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1") | Out-Null
}

$steps += Invoke-Step -Name "generate_evening_owner_report" -Action {
    & (Join-Path $ProjectRoot "TOOLS\GENERATE_EVENING_OWNER_REPORT.ps1") | Out-Null
}

$steps += Invoke-Step -Name "generate_chart_plan" -Action {
    & (Join-Path $ProjectRoot "TOOLS\GENERATE_MT5_CHART_PLAN.ps1") | Out-Null
}

$steps += Invoke-Step -Name "export_server_profile" -Action {
    & (Join-Path $ProjectRoot "TOOLS\EXPORT_MT5_SERVER_PROFILE.ps1") | Out-Null
}

$steps += Invoke-Step -Name "simulate_mt5_server_install" -Action {
    & (Join-Path $ProjectRoot "TOOLS\SIMULATE_MT5_SERVER_INSTALL.ps1") | Out-Null
}

$steps += Invoke-Step -Name "export_operator_handoff" -Action {
    & (Join-Path $ProjectRoot "TOOLS\EXPORT_OPERATOR_HANDOFF.ps1") | Out-Null
}

$steps += Invoke-Step -Name "validate_transfer_package" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_TRANSFER_PACKAGE.ps1") | Out-Null
}

if (-not $SkipPackage) {
    $steps += Invoke-Step -Name "pack_project_zip" -Action {
        & (Join-Path $ProjectRoot "TOOLS\PACK_PROJECT_ZIP.ps1") | Out-Null
    }

    $steps += Invoke-Step -Name "pack_handoff_zip" -Action {
        & (Join-Path $ProjectRoot "TOOLS\PACK_HANDOFF_ZIP.ps1") | Out-Null
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    usb_root = $UsbRoot
    ok = $true
    steps = $steps
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\prepare_mt5_rollout_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\prepare_mt5_rollout_report.txt"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$txt = @()
$txt += "PREPARE MT5 ROLLOUT REPORT"
$txt += ("OK={0}" -f $report.ok)
$txt += ""
foreach ($step in $steps) {
    $txt += ("{0} | {1} -> {2} | {3}" -f $step.step,$step.started_utc,$step.finished_utc,$step.status)
}
$txt | Set-Content -LiteralPath $txtPath -Encoding ASCII

$report | ConvertTo-Json -Depth 6
