param(
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$ProfileName = "MAKRO_I_MIKRO_BOT_VPS_CLEAR",
    [string]$Symbol = "EURUSD.pro"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$pythonScript = Join-Path $projectRoot "TOOLS\setup_mt5_safe_empty_profile.py"

& python $pythonScript --terminal-data-dir $TerminalDataDir --mt5-exe $Mt5Exe --profile-name $ProfileName --symbol $Symbol --launch

Start-Sleep -Seconds 5

$reportPath = Join-Path $projectRoot "EVIDENCE\mt5_vps_clear_profile_report.json"
if (Test-Path -LiteralPath $reportPath) {
    Get-Content -LiteralPath $reportPath -Raw
}
