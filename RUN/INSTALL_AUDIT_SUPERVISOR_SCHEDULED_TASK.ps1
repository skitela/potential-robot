param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TaskName = "MakroIMikroBotAuditSupervisor",
    [int]$CycleSeconds = 300,
    [int]$HeavySweepEveryCycles = 6,
    [ValidateSet("Off", "Safe", "Controlled")]
    [string]$AutoHealLevel = "Off",
    [switch]$ApplySafeAutoHeal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $ProjectRoot "RUN\START_AUDIT_SUPERVISOR_BACKGROUND.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Brak skryptu startowego superwizora audytu: $scriptPath"
}

$effectiveAutoHealLevel = if ($PSBoundParameters.ContainsKey("AutoHealLevel")) {
    $AutoHealLevel
}
elseif ($ApplySafeAutoHeal) {
    "Safe"
}
else {
    "Off"
}
$autoHealFlag = if ($effectiveAutoHealLevel -eq "Off") { "" } else { " -AutoHealLevel $effectiveAutoHealLevel" }
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ProjectRoot `"$ProjectRoot`" -CycleSeconds $CycleSeconds -HeavySweepEveryCycles $HeavySweepEveryCycles$autoHealFlag"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argument
$triggers = @(
    New-ScheduledTaskTrigger -AtLogOn
    New-ScheduledTaskTrigger -AtStartup
)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings -Force -ErrorAction Stop | Out-Null

[pscustomobject]@{
    schema_version = "1.0"
    task_name = $TaskName
    script = $scriptPath
    cycle_seconds = $CycleSeconds
    heavy_sweep_every_cycles = $HeavySweepEveryCycles
    auto_heal_level = $effectiveAutoHealLevel
    apply_safe_auto_heal = [bool]$ApplySafeAutoHeal
    status = "OK"
} | ConvertTo-Json -Depth 4
