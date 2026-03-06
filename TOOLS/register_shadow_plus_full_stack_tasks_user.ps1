param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [int]$IdleThresholdSec = 900
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$regShadow = Join-Path $Root "TOOLS\register_stage1_shadow_plus_task_user.ps1"
$regDiag = Join-Path $Root "TOOLS\register_shadow_diagnostics_tasks_user.ps1"
foreach ($s in @($regShadow, $regDiag)) {
    if (-not (Test-Path -LiteralPath $s)) {
        throw "Script not found: $s"
    }
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $regShadow `
    -Root $Root `
    -LabDataRoot $LabDataRoot `
    -TaskName "OANDA_MT5_STAGE1_SHADOW_PLUS_HOURLY_USER" `
    -RepeatMinutes 60 `
    -FocusGroup "FX" `
    -CoverageScope "active" `
    -LookbackHours 24 `
    -ShadowLookbackDays 14 `
    -IdleThresholdSec $IdleThresholdSec

& powershell -NoProfile -ExecutionPolicy Bypass -File $regDiag `
    -Root $Root `
    -IdleThresholdSec $IdleThresholdSec `
    -RuntimeStabilityIntervalMinutes 15 `
    -LatencyDailyTime "03:20" `
    -FxNextWindowDailyTime "15:40" `
    -LatencyDurationMin 20

Write-Host "SHADOW_PLUS_FULL_STACK_TASKS_READY root=$Root lab_data_root=$LabDataRoot"
