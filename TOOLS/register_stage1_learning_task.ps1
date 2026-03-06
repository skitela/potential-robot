param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [string]$TaskName = "OANDA_MT5_STAGE1_LEARNING_DAILY",
    [string]$StartTime = "22:30",
    [string]$FocusGroup = "FX",
    [int]$LookbackHours = 24,
    [int]$RetentionDays = 14,
    [ValidateSet("strategy", "active")]
    [string]$CoverageScope = "active",
    [switch]$FailOnAllStaleCounterfactual
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $Root "TOOLS\run_stage1_learning_cycle.ps1"
if (!(Test-Path $scriptPath)) {
    throw "Missing script: $scriptPath"
}

$arg = "-ExecutionPolicy Bypass -File `"$scriptPath`" -Root `"$Root`" -LabDataRoot `"$LabDataRoot`" -FocusGroup `"$FocusGroup`" -LookbackHours $LookbackHours -RetentionDays $RetentionDays -CoverageScope $CoverageScope"
if ($FailOnAllStaleCounterfactual.IsPresent) {
    $arg += " -FailOnAllStaleCounterfactual"
}
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arg
$trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "REGISTER_STAGE1_LEARNING_TASK_OK task=$TaskName start=$StartTime root=$Root focus=$FocusGroup"
