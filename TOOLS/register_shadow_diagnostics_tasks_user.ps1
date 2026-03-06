param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$TaskRuntimeStability = "OANDA_MT5_RUNTIME_STABILITY_CYCLE_USER",
    [string]$TaskLatencyDaily = "OANDA_MT5_LATENCY_AUDIT_DAILY_USER",
    [string]$TaskFxNextWindow = "OANDA_MT5_FX_NEXT_WINDOW_AUDIT_DAILY_USER",
    [int]$RuntimeStabilityIntervalMinutes = 15,
    [string]$LatencyDailyTime = "03:20",
    [string]$FxNextWindowDailyTime = "15:40",
    [int]$IdleThresholdSec = 900,
    [int]$LatencyDurationMin = 20
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

$stabilityScript = Join-Path $Root "TOOLS\runtime_stability_cycle.py"
$latencyScript = Join-Path $Root "TOOLS\run_runtime_latency_audit.ps1"
$fxScript = Join-Path $Root "TOOLS\fx_runtime_audit_next_window.ps1"
foreach ($s in @($stabilityScript, $latencyScript, $fxScript)) {
    if (-not (Test-Path -LiteralPath $s)) {
        throw "Script not found: $s"
    }
}

# 1) Runtime stability cycle (periodic)
$startAt = (Get-Date).AddMinutes(1)
$repeat = New-TimeSpan -Minutes ([Math]::Max(5, [int]$RuntimeStabilityIntervalMinutes))
$duration = New-TimeSpan -Days 3650
$stabilityArgs = @(
    "-WindowStyle", "Hidden",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-Command",
    "`"py -3.12 -B `"$stabilityScript`" --root `"$Root`" --timeout-sec 240`""
) -join " "
$stabilityAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $stabilityArgs -WorkingDirectory $Root
$stabilityTrigger = New-ScheduledTaskTrigger -Once -At $startAt -RepetitionInterval $repeat -RepetitionDuration $duration
$stabilitySettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
$stabilityPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask `
    -TaskName $TaskRuntimeStability `
    -Action $stabilityAction `
    -Trigger $stabilityTrigger `
    -Settings $stabilitySettings `
    -Principal $stabilityPrincipal `
    -Description "OANDA MT5 runtime stability cycle (user-level)" `
    -Force | Out-Null

# 2) Daily latency soak audit (guarded: idle + outside active)
$latencyArgs = @(
    "-WindowStyle", "Hidden",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$latencyScript`"",
    "-Root", "`"$Root`"",
    "-DurationMin", [string]([Math]::Max(5, [int]$LatencyDurationMin)),
    "-Profile", "safety_only",
    "-RequireIdle",
    "-IdleThresholdSec", [string]([Math]::Max(60, [int]$IdleThresholdSec)),
    "-RequireOutsideActive"
) -join " "
$latencyAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $latencyArgs -WorkingDirectory $Root
$latencyTrigger = New-ScheduledTaskTrigger -Daily -At $LatencyDailyTime
$latencySettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes ([Math]::Max(40, [int]$LatencyDurationMin + 20)))
Register-ScheduledTask `
    -TaskName $TaskLatencyDaily `
    -Action $latencyAction `
    -Trigger $latencyTrigger `
    -Settings $latencySettings `
    -Principal $stabilityPrincipal `
    -Description "OANDA MT5 daily runtime latency audit (guarded)" `
    -Force | Out-Null

# 3) Next-window FX readiness audit (daily)
$fxArgs = @(
    "-WindowStyle", "Hidden",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$fxScript`"",
    "-Root", "`"$Root`""
) -join " "
$fxAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $fxArgs -WorkingDirectory $Root
$fxTrigger = New-ScheduledTaskTrigger -Daily -At $FxNextWindowDailyTime
$fxSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 20)
Register-ScheduledTask `
    -TaskName $TaskFxNextWindow `
    -Action $fxAction `
    -Trigger $fxTrigger `
    -Settings $fxSettings `
    -Principal $stabilityPrincipal `
    -Description "OANDA MT5 FX next-window readiness audit (daily)" `
    -Force | Out-Null

foreach ($taskName in @($TaskRuntimeStability, $TaskLatencyDaily, $TaskFxNextWindow)) {
    $task = Get-ScheduledTask -TaskName $taskName
    $info = Get-ScheduledTaskInfo -TaskName $taskName
    Write-Host "TASK_REGISTERED name=$($task.TaskName) state=$($task.State) next=$($info.NextRunTime) last=$($info.LastRunTime)"
}
