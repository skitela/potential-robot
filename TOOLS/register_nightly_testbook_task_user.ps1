param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_LAB_DATA",
    [string]$TaskName = "OANDA_MT5_NIGHTLY_TESTBOOK_USER",
    [string]$DailyTime = "03:50",
    [int]$IdleThresholdSec = 900,
    [int]$LatencyDurationMin = 20
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

$runner = Join-Path $Root "TOOLS\run_nightly_testbook.ps1"
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Runner not found: $runner"
}

$arguments = @(
    "-WindowStyle", "Hidden",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$runner`"",
    "-Action", "run-tests",
    "-Root", "`"$Root`"",
    "-LabDataRoot", "`"$LabDataRoot`"",
    "-LatencyDurationMin", [string]([Math]::Max(1, [int]$LatencyDurationMin)),
    "-RequireIdle",
    "-IdleThresholdSec", [string]([Math]::Max(60, [int]$IdleThresholdSec)),
    "-RequireOutsideActive"
) -join " "

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $Root
$trigger = New-ScheduledTaskTrigger -Daily -At $DailyTime
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "OANDA MT5 nightly testbook (guarded, non-blocking for active trading window)" `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host "NIGHTLY_TESTBOOK_TASK_REGISTERED"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "LastRunTime: $($info.LastRunTime)"
Write-Host "DailyTime: $DailyTime"
Write-Host "Guards: RequireIdle=1 IdleThresholdSec=$IdleThresholdSec RequireOutsideActive=1"
