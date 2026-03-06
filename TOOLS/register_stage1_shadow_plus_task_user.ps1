param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_LAB_DATA",
    [string]$TaskName = "OANDA_MT5_STAGE1_SHADOW_PLUS_HOURLY_USER",
    [string]$StartTime = "00:05",
    [int]$RepeatMinutes = 60,
    [string]$FocusGroup = "FX",
    [ValidateSet("strategy", "active")]
    [string]$CoverageScope = "active",
    [int]$LookbackHours = 24,
    [int]$ShadowLookbackDays = 14,
    [int]$IdleThresholdSec = 900,
    [switch]$DisableAutoApprove,
    [switch]$ShadowDryRun
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

$runner = Join-Path $Root "TOOLS\run_stage1_shadow_plus_cycle.ps1"
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Runner not found: $runner"
}

$argList = @(
    "-WindowStyle", "Hidden",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$runner`"",
    "-Root", "`"$Root`"",
    "-LabDataRoot", "`"$LabDataRoot`"",
    "-FocusGroup", $FocusGroup,
    "-CoverageScope", $CoverageScope,
    "-LookbackHours", [string]$LookbackHours,
    "-ShadowLookbackDays", [string]$ShadowLookbackDays,
    "-RequireIdle",
    "-IdleThresholdSec", [string]$IdleThresholdSec,
    "-RequireOutsideActive"
)
if ($DisableAutoApprove.IsPresent) {
    $argList += "-DisableAutoApprove"
}
if ($ShadowDryRun.IsPresent) {
    $argList += "-ShadowDryRun"
}
$arguments = $argList -join " "

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $Root
$startToday = [datetime]::Today.Add([TimeSpan]::Parse($StartTime))
if ($startToday -lt (Get-Date)) {
    $startToday = $startToday.AddDays(1)
}
$trigger = New-ScheduledTaskTrigger `
    -Once `
    -At $startToday `
    -RepetitionInterval (New-TimeSpan -Minutes ([Math]::Max(5, $RepeatMinutes))) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 70)

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "OANDA MT5 Stage1 Shadow+ hourly cycle (user-level)" `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host "STAGE1_SHADOW_PLUS_TASK_REGISTERED_USER"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "LastRunTime: $($info.LastRunTime)"
