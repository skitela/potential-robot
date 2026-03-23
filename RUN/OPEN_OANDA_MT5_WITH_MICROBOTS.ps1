param(
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$ProfileName = "MAKRO_I_MIKRO_BOT_AUTO",
    [switch]$AllowBlockedAuditGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$guardScript = Join-Path $projectRoot "TOOLS\mt5_risk_popup_guard.ps1"
$guardStatus = Join-Path $projectRoot "EVIDENCE\OPS\mt5_risk_guard_status.json"
$pythonScript = Join-Path $projectRoot "TOOLS\setup_mt5_microbots_profile.py"

& (Join-Path $projectRoot "TOOLS\ASSERT_AUDIT_SUPERVISOR_GATE.ps1") `
    -ProjectRoot $projectRoot `
    -GateType ROLLOUT `
    -AllowBlocked:$AllowBlockedAuditGate | Out-Null

$targetTitlePattern = 'OANDA TMS Brokers S.A.'
Get-Process terminal64 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.MainWindowTitle -like "*$targetTitlePattern*" -and
        $_.MainWindowTitle -notmatch '\[VPS\]'
    } |
    Stop-Process -Force -ErrorAction SilentlyContinue

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
