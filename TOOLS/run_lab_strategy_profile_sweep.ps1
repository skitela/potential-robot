param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [int]$LookbackDays = 3,
    [int]$HorizonMinutes = 60,
    [string]$Profiles = "BASELINE,CANDLE_ONLY,RENKO_ONLY,CANDLE_RENKO_CONFLUENCE",
    [double]$ProfileScoreThreshold = 0.55,
    [switch]$ProfileRequireBias,
    [int]$MinSample = 20,
    [double]$PoluzujThresholdPipsPerTrade = 0.5,
    [double]$DocisnijThresholdPipsPerTrade = -1.5,
    [int]$TimeoutSec = 1800,
    [double]$MinIntervalHours = 6.0,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-Location -Path $Root

$argsList = @(
    "-B",
    "TOOLS\lab_strategy_profile_sweep.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--lookback-days", [string]$LookbackDays,
    "--horizon-minutes", [string]$HorizonMinutes,
    "--profiles", $Profiles,
    "--profile-score-threshold", [string]$ProfileScoreThreshold,
    "--min-sample", [string]$MinSample,
    "--poluzuj-threshold-pips-per-trade", [string]$PoluzujThresholdPipsPerTrade,
    "--docisnij-threshold-pips-per-trade", [string]$DocisnijThresholdPipsPerTrade,
    "--timeout-sec", [string]$TimeoutSec,
    "--min-interval-hours", [string]$MinIntervalHours
)
if ($ProfileRequireBias) { $argsList += "--profile-require-bias" }
if ($Force) { $argsList += "--force" }

py -3.12 @argsList
