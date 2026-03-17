param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TaskName = "MakroIMikroBot_RaportWieczorny_2030",
    [string]$At = "20:30"
)

$ErrorActionPreference = "Stop"

$runner = Join-Path $ProjectRoot "RUN\GENERATE_EVENING_REPORT_NOW.ps1"
if (-not (Test-Path -LiteralPath $runner)) {
    throw "Brak skryptu uruchomieniowego: $runner"
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$runner`""
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

[pscustomobject]@{
    task_name = $TaskName
    at = $At
    runner = $runner
    status = "REGISTERED"
} | ConvertTo-Json -Depth 4
