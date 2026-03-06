param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [string]$TaskName = "OANDA_MT5_STAGE1_LEARNING_DAILY_USER",
    [string]$StartTime = "22:30",
    [string]$FocusGroup = "FX",
    [int]$LookbackHours = 24,
    [int]$RetentionDays = 14,
    [ValidateSet("strategy", "active")]
    [string]$CoverageScope = "active",
    [int]$MinTotalPerSymbol = 30,
    [int]$MinNoTradePerSymbol = 10,
    [int]$MinTradePathPerSymbol = 1,
    [int]$MinBucketsPerSymbol = 2,
    [switch]$FailOnAllStaleCounterfactual
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

$runner = Join-Path $Root "TOOLS\run_stage1_learning_cycle.ps1"
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
    "-LookbackHours", [string]$LookbackHours,
    "-RetentionDays", [string]$RetentionDays,
    "-CoverageScope", $CoverageScope,
    "-MinTotalPerSymbol", [string]$MinTotalPerSymbol,
    "-MinNoTradePerSymbol", [string]$MinNoTradePerSymbol,
    "-MinTradePathPerSymbol", [string]$MinTradePathPerSymbol,
    "-MinBucketsPerSymbol", [string]$MinBucketsPerSymbol
)
if ($FailOnAllStaleCounterfactual.IsPresent) {
    $argList += "-FailOnAllStaleCounterfactual"
}
$arguments = $argList -join " "

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $Root
$trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 90)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "OANDA MT5 Stage1 learning cycle (user-level)" `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host "STAGE1_TASK_REGISTERED_USER"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "LastRunTime: $($info.LastRunTime)"
