param(
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$ProfileName = "MAKRO_I_MIKRO_BOT_AUTO"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$guardScript = "C:\OANDA_MT5_SYSTEM\TOOLS\mt5_risk_popup_guard.ps1"
$guardStatus = "C:\OANDA_MT5_SYSTEM\RUN\mt5_risk_guard_status.json"
$pythonScript = Join-Path $projectRoot "TOOLS\setup_mt5_microbots_profile.py"

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Start-Process powershell -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $guardScript,
    "-Mt5DataDir", $TerminalDataDir
) | Out-Null

Start-Sleep -Seconds 1

& python $pythonScript --terminal-data-dir $TerminalDataDir --mt5-exe $Mt5Exe --profile-name $ProfileName --launch

Start-Sleep -Seconds 8

if (Test-Path -LiteralPath $guardStatus) {
    Get-Content -LiteralPath $guardStatus -Raw
}
