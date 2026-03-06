param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [string]$TaskName = "OANDA_MT5_LAB_DAILY",
    [string]$StartTime = "03:30",
    [string]$FocusGroup = "FX",
    [int]$LookbackDays = 180,
    [int]$HorizonMinutes = 60,
    [int]$TimeoutSec = 1800,
    [int]$SnapshotRetentionDays = 14,
    [int]$RepeatMinutes = 0
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
if ($RepeatMinutes -gt 0) {
    $hm = $StartTime.Trim().Split(":")
    if ($hm.Count -ne 2) {
        throw "Invalid StartTime format. Expected HH:mm, got: $StartTime"
    }
    $hour = [int]$hm[0]
    $minute = [int]$hm[1]
    if ($hour -lt 0 -or $hour -gt 23 -or $minute -lt 0 -or $minute -gt 59) {
        throw "Invalid StartTime values. Expected HH:mm, got: $StartTime"
    }
    $now = Get-Date
    $startBoundary = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $hour -Minute $minute -Second 0
    if ($startBoundary -le $now) {
        $startBoundary = $startBoundary.AddDays(1)
    }
    $repeatInterval = New-TimeSpan -Minutes ([Math]::Max(1, [int]$RepeatMinutes)
    )
    # Long-running repetition window (about 10 years) for practical "always on" behavior.
    $repeatDuration = New-TimeSpan -Days 3650
    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At $startBoundary `
        -RepetitionInterval $repeatInterval `
        -RepetitionDuration $repeatDuration
} else {
    $trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
}
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description $(if ($RepeatMinutes -gt 0) { "OANDA MT5 LAB scheduler (every $RepeatMinutes min, active-window aware)" } else { "OANDA MT5 LAB daily ingest/pipeline scheduler" }) `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host "LAB_TASK_REGISTERED"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "LastRunTime: $($info.LastRunTime)"
