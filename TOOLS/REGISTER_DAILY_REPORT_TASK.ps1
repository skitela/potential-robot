param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TaskName = "MakroIMikroBotRaportDzienny2030",
    [string]$RunAt = "20:30"
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $ProjectRoot "RUN\GENERATE_DAILY_REPORTS_NOW.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Brak skryptu uruchomieniowego raportów: $scriptPath"
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At $RunAt
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

[pscustomobject]@{
    schema_version = "1.0"
    task_name = $TaskName
    run_at = $RunAt
    script = $scriptPath
    status = "OK"
} | ConvertTo-Json -Depth 4
