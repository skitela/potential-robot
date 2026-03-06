param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [string]$TaskName = "OANDA_MT5_LAB_INSIGHTS_Q3H"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

$runner = Join-Path $Root "TOOLS\run_lab_insights.ps1"
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Runner not found: $runner"
}

$argList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$runner`"",
    "-Root", "`"$Root`"",
    "-LabDataRoot", "`"$LabDataRoot`""
)
$arguments = $argList -join " "

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $Root
$times = @("00:10","03:10","06:10","09:10","12:10","15:10","18:10","21:10")
$triggers = @()
foreach ($t in $times) {
    $triggers += New-ScheduledTaskTrigger -Daily -At $t
}
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $triggers `
    -Settings $settings `
    -Principal $principal `
    -Description "OANDA MT5 LAB insights digest every 3h" `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host "LAB_INSIGHTS_TASK_REGISTERED"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
