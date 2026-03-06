param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [string]$BackupRoot = "C:\OANDA_MT5_SYSTEM\BACKUPS",
    [string]$TaskName = "OANDA_MT5_WEEKLY_BACKUP",
    [string]$StartTime = "03:30",
    [ValidateSet("monday","tuesday","wednesday","thursday","friday","saturday","sunday")]
    [string]$PreferredWeekday = "sunday",
    [int]$MaxDaysWithoutBackup = 7,
    [switch]$IncludeUsbToken,
    [string]$UsbLabel = "OANDAKEY"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

$runner = Join-Path $Root "TOOLS\run_weekly_backup.ps1"
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Runner not found: $runner"
}

$argList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$runner`"",
    "-Root", "`"$Root`"",
    "-LabDataRoot", "`"$LabDataRoot`"",
    "-BackupRoot", "`"$BackupRoot`"",
    "-PreferredWeekday", $PreferredWeekday,
    "-MaxDaysWithoutBackup", [string]$MaxDaysWithoutBackup,
    "-UsbLabel", $UsbLabel
)
if ($IncludeUsbToken) { $argList += "-IncludeUsbToken" }

$arguments = $argList -join " "
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $Root
$trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 6)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "OANDA MT5 weekly full backup with Sunday preference and catch-up policy" `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host "WEEKLY_BACKUP_TASK_REGISTERED_USER"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "LastRunTime: $($info.LastRunTime)"

