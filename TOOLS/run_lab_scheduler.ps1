param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_LAB_DATA",
    [string]$FocusGroup = "FX",
    [int]$LookbackDays = 180,
    [int]$HorizonMinutes = 60,
    [int]$TimeoutSec = 1800,
    [int]$SnapshotRetentionDays = 14,
    [switch]$SkipSnapshotRetention,
    [switch]$AllowActiveWindow,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-Location -Path $Root

$argsList = @(
    "-B",
    "TOOLS\lab_scheduler.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--focus-group", $FocusGroup,
    "--lookback-days", [string]$LookbackDays,
    "--horizon-minutes", [string]$HorizonMinutes,
    "--timeout-sec", [string]$TimeoutSec,
    "--snapshot-retention-days", [string]$SnapshotRetentionDays
)
if ($AllowActiveWindow) { $argsList += "--allow-active-window" }
if ($Force) { $argsList += "--force" }
if ($SkipSnapshotRetention) { $argsList += "--skip-snapshot-retention" }

$pyVersionArgs = @()
try {
    & py -3.12 -c "import sys; print(sys.version)" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $pyVersionArgs = @("-3.12")
    }
} catch {
    $pyVersionArgs = @()
}

py @($pyVersionArgs + $argsList)
