param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [string]$TaskName = "OANDA_MT5_LAB_DAILY_USER",
    [string]$StartTime = "03:30",
    [string]$FocusGroup = "FX",
    [int]$LookbackDays = 180,
    [int]$HorizonMinutes = 60,
    [int]$TimeoutSec = 1800,
    [int]$SnapshotRetentionDays = 14
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

$runner = Join-Path $Root "TOOLS\run_lab_scheduler.ps1"
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Runner not found: $runner"
}

$argList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$runner`"",
    "-Root", "`"$Root`"",
    "-LabDataRoot", "`"$LabDataRoot`"",
    "-FocusGroup", $FocusGroup,
    "-LookbackDays", [string]$LookbackDays,
    "-HorizonMinutes", [string]$HorizonMinutes,
    "-TimeoutSec", [string]$TimeoutSec,
    "-SnapshotRetentionDays", [string]$SnapshotRetentionDays
)
$arguments = $argList -join " "

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $Root
$trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
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
    -Description "OANDA MT5 LAB daily scheduler (user-level)" `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host "LAB_TASK_REGISTERED_USER"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "LastRunTime: $($info.LastRunTime)"
