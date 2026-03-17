param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($CommonFilesRoot)) {
    $CommonFilesRoot = Join-Path $env:APPDATA "MetaQuotes\\Terminal\\Common\\Files\\MAKRO_I_MIKRO_BOT"
}

$configPath = Join-Path $projectPath "CONFIG\\core_capital_contract_v1.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing core capital contract config: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$stateDir = Join-Path $CommonFilesRoot "state\\_global"
Ensure-Dir $stateDir

$outPath = Join-Path $stateDir "core_capital_contract.csv"
$rows = @(
    "enabled`t$([int][bool]$config.runtime.enabled)"
    "revision`t$([int]$config.runtime.revision)"
    "refresh_interval_sec`t$([int]$config.runtime.refresh_interval_sec)"
    "paper_core_capital`t$([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0:F2}',[double]$config.paper.core_capital))"
    "live_core_capital`t$([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0:F2}',[double]$config.live.core_capital))"
)
$rows | Set-Content -LiteralPath $outPath -Encoding UTF8

$reportDir = Join-Path $projectPath "EVIDENCE"
Ensure-Dir $reportDir
$reportPath = Join-Path $reportDir ("APPLY_CORE_CAPITAL_CONTRACT_{0}.json" -f ((Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")))

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    common_files_root = $CommonFilesRoot
    source_config = $configPath
    state_path = $outPath
    enabled = [bool]$config.runtime.enabled
    revision = [int]$config.runtime.revision
    paper_core_capital = [double]$config.paper.core_capital
    live_core_capital = [double]$config.live.core_capital
}

$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$result | ConvertTo-Json -Depth 4
