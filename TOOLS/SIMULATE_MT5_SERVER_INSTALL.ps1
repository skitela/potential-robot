param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$SimRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\REMOTE_SIM",
    [switch]$AllowBlockedAuditGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$simPath = $SimRoot
$terminalData = Join-Path $simPath "TerminalData"
$commonFiles = Join-Path $simPath "CommonFiles"

if (Test-Path -LiteralPath $simPath) {
    Remove-Item -LiteralPath $simPath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $terminalData | Out-Null
New-Item -ItemType Directory -Force -Path $commonFiles | Out-Null

& (Join-Path $projectPath "TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1") `
    -ProjectRoot $projectPath `
    -TargetTerminalDataDir $terminalData `
    -TargetCommonFilesDir $commonFiles `
    -AllowBlockedAuditGate:$AllowBlockedAuditGate `
    -CreateRuntimeFolders | Out-Null

& (Join-Path $projectPath "TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1") `
    -TargetTerminalDataDir $terminalData `
    -TargetCommonFilesDir $commonFiles | Out-Null

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    sim_root = $simPath
    terminal_data_dir = $terminalData
    common_files_dir = $commonFiles
    ok = $true
}

$jsonPath = Join-Path $projectPath "EVIDENCE\simulate_mt5_server_install_report.json"
$txtPath = Join-Path $projectPath "EVIDENCE\simulate_mt5_server_install_report.txt"

$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $txtPath -Encoding ASCII
$result | ConvertTo-Json -Depth 5
