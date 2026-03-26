param(
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$ProfileName = "MAKRO_I_MIKRO_BOT_AUTO",
    [switch]$AllowBlockedAuditGate,
    [switch]$UseActiveLivePresets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$guardScript = Join-Path $projectRoot "TOOLS\mt5_risk_popup_guard.ps1"
$guardStatus = Join-Path $projectRoot "EVIDENCE\OPS\mt5_risk_guard_status.json"
$pythonScript = Join-Path $projectRoot "TOOLS\setup_mt5_microbots_profile.py"
$operatorViewScript = Join-Path $projectRoot "RUN\USTAW_OANDA_MT5_WIDOK_OPERATORA.ps1"
$profileReportJson = Join-Path $projectRoot "EVIDENCE\mt5_microbots_profile_setup_report.json"
$profileReportTxt = Join-Path $projectRoot "EVIDENCE\mt5_microbots_profile_setup_report.txt"
$vpsProfileReportJson = Join-Path $projectRoot "EVIDENCE\OPS\mt5_microbots_profile_setup_for_vps_latest.json"
$vpsProfileReportTxt = Join-Path $projectRoot "EVIDENCE\OPS\mt5_microbots_profile_setup_for_vps_latest.txt"
$presetRoot = if ($UseActiveLivePresets) {
    Join-Path $projectRoot "SERVER_PROFILE\PACKAGE\MQL5\Presets"
}
else {
    Join-Path $projectRoot "MQL5\Presets"
}

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

$pythonArgs = @(
    $pythonScript,
    "--terminal-data-dir", $TerminalDataDir,
    "--mt5-exe", $Mt5Exe,
    "--profile-name", $ProfileName,
    "--preset-root", $presetRoot,
    "--launch"
)
if ($UseActiveLivePresets) {
    $pythonArgs += "--use-active-presets"
}
& python @pythonArgs

Start-Sleep -Seconds 8

if ($UseActiveLivePresets -and (Test-Path -LiteralPath $profileReportJson)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $vpsProfileReportJson) | Out-Null
    Copy-Item -LiteralPath $profileReportJson -Destination $vpsProfileReportJson -Force
    if (Test-Path -LiteralPath $profileReportTxt) {
        Copy-Item -LiteralPath $profileReportTxt -Destination $vpsProfileReportTxt -Force
    }
}

try {
    & $operatorViewScript -Mt5Exe $Mt5Exe -ToolboxTab "Eksperci" -VpsTab "Eksperci" -OpenVpsPanel | Out-Null
} catch {
    Write-Warning ("Nie udalo sie ustawic widoku operatora MT5: {0}" -f $_.Exception.Message)
}

if (Test-Path -LiteralPath $guardStatus) {
    Get-Content -LiteralPath $guardStatus -Raw
}
