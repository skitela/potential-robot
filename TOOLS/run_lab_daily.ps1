param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [string]$FocusGroup = "FX",
    [int]$LookbackDays = 30,
    [int]$HorizonMinutes = 60,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-Location -Path $Root

$argsList = @(
    "-B",
    "TOOLS\lab_daily_pipeline.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--focus-group", $FocusGroup,
    "--lookback-days", [string]$LookbackDays,
    "--horizon-minutes", [string]$HorizonMinutes,
    "--daily-guard"
)
if ($Force) { $argsList += "--force" }

py @argsList
