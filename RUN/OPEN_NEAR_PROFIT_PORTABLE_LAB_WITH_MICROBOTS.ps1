param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LabTerminalRoot = "C:\TRADING_TOOLS\MT5_NEAR_PROFIT_LAB",
    [string]$ProfileName = "MAKRO_I_MIKRO_BOT_AUTO",
    [bool]$CompileAll = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$prepareScript = Join-Path $ProjectRoot "RUN\PREPARE_NEAR_PROFIT_PORTABLE_LAB.ps1"
$pythonScript = Join-Path $ProjectRoot "TOOLS\setup_mt5_microbots_profile.py"
$reportJson = Join-Path $ProjectRoot "EVIDENCE\OPS\near_profit_portable_lab_profile_latest.json"
$reportTxt = Join-Path $ProjectRoot "EVIDENCE\OPS\near_profit_portable_lab_profile_latest.txt"

if (-not (Test-Path -LiteralPath $prepareScript)) {
    throw "Brak skryptu przygotowania laboratorium: $prepareScript"
}
if (-not (Test-Path -LiteralPath $pythonScript)) {
    throw "Brak skryptu budowy profilu: $pythonScript"
}

$prepared = & $prepareScript -ProjectRoot $ProjectRoot -LabTerminalRoot $LabTerminalRoot -CompileAll:$CompileAll
$mt5Exe = Join-Path $LabTerminalRoot "terminal64.exe"

$pythonArgs = @(
    $pythonScript,
    "--terminal-data-dir", $LabTerminalRoot,
    "--mt5-exe", $mt5Exe,
    "--profile-name", $ProfileName,
    "--preset-root", (Join-Path $ProjectRoot "MQL5\Presets"),
    "--launch"
)
& python @pythonArgs | Out-Null

$profileReportJson = Join-Path $ProjectRoot "EVIDENCE\mt5_microbots_profile_setup_report.json"
$profileReportTxt = Join-Path $ProjectRoot "EVIDENCE\mt5_microbots_profile_setup_report.txt"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportJson) | Out-Null
if (Test-Path -LiteralPath $profileReportJson) {
    Copy-Item -LiteralPath $profileReportJson -Destination $reportJson -Force
}
if (Test-Path -LiteralPath $profileReportTxt) {
    Copy-Item -LiteralPath $profileReportTxt -Destination $reportTxt -Force
}

[pscustomobject]@{
    terminal_root = $LabTerminalRoot
    mt5_exe = $mt5Exe
    profile_name = $ProfileName
    report_json = $reportJson
    report_txt = $reportTxt
    prepare_result = $prepared
}
