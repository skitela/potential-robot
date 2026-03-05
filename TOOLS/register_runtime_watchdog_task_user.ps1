param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$TaskName = "OANDA_MT5_RUNTIME_WATCHDOG_USER",
    [int]$IntervalMinutes = 1,
    [int]$RestartCooldownSec = 180,
    [string]$Profile = "full"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

$runner = Join-Path $Root "TOOLS\runtime_watchdog_tick.ps1"
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Runner not found: $runner"
}

$interval = [Math]::Max(1, [int]$IntervalMinutes)
$startAt = (Get-Date).AddMinutes(1)
$repeat = New-TimeSpan -Minutes $interval
$duration = New-TimeSpan -Days 3650

$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$runner`"",
    "-Root", "`"$Root`"",
    "-Profile", $Profile,
    "-RestartCooldownSec", [string]$RestartCooldownSec
) -join " "

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $Root
$trigger = New-ScheduledTaskTrigger -Once -At $startAt -RepetitionInterval $repeat -RepetitionDuration $duration
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "OANDA MT5 runtime watchdog (user-level, periodic health tick)" `
    -Force | Out-Null

try {
    Start-ScheduledTask -TaskName $TaskName | Out-Null
} catch {
    # best-effort immediate run
}

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host "RUNTIME_WATCHDOG_TASK_REGISTERED"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "LastRunTime: $($info.LastRunTime)"
