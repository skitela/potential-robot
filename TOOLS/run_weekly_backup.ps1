param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [string]$BackupRoot = "C:\OANDA_MT5_SYSTEM\BACKUPS",
    [ValidateSet("monday","tuesday","wednesday","thursday","friday","saturday","sunday")]
    [string]$PreferredWeekday = "sunday",
    [int]$MaxDaysWithoutBackup = 7,
    [switch]$Force,
    [switch]$IncludeUsbToken,
    [string]$TokenEnvPath = "",
    [string]$UsbLabel = "OANDAKEY"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$py = "python"
$script = Join-Path $Root "TOOLS\weekly_system_backup.py"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing script: $script"
}

$argsList = @(
    $script,
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--backup-root", $BackupRoot,
    "--preferred-weekday", $PreferredWeekday,
    "--max-days-without-backup", [string]$MaxDaysWithoutBackup
)
if ($Force) { $argsList += "--force" }
if ($IncludeUsbToken) { $argsList += "--include-usb-token" }
if (-not [string]::IsNullOrWhiteSpace($TokenEnvPath)) { $argsList += @("--token-env-path", $TokenEnvPath) }
if (-not [string]::IsNullOrWhiteSpace($UsbLabel)) { $argsList += @("--usb-label", $UsbLabel) }

Write-Host "RUN_WEEKLY_BACKUP start"
Write-Host ("root=" + $Root)
Write-Host ("backup_root=" + $BackupRoot)
& $py @argsList
$rc = $LASTEXITCODE
Write-Host ("RUN_WEEKLY_BACKUP done rc=" + $rc)
exit $rc

