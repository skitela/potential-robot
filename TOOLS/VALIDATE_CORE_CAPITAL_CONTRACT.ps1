param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($CommonFilesRoot)) {
    $CommonFilesRoot = Join-Path $env:APPDATA "MetaQuotes\\Terminal\\Common\\Files\\MAKRO_I_MIKRO_BOT"
}

$configPath = Join-Path $projectPath "CONFIG\\core_capital_contract_v1.json"
$statePath = Join-Path $CommonFilesRoot "state\\_global\\core_capital_contract.csv"
$issues = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $configPath)) {
    $issues.Add("Missing config: $configPath")
}

if (-not (Test-Path -LiteralPath $statePath)) {
    $issues.Add("Missing runtime state: $statePath")
}

$stateMap = @{}
if (Test-Path -LiteralPath $statePath) {
    foreach ($line in (Get-Content -LiteralPath $statePath -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2) {
            $stateMap[$parts[0]] = $parts[1]
        }
    }
}

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    config_path = $configPath
    state_path = $statePath
    state_present = (Test-Path -LiteralPath $statePath)
    enabled = $stateMap["enabled"]
    revision = $stateMap["revision"]
    paper_core_capital = $stateMap["paper_core_capital"]
    live_core_capital = $stateMap["live_core_capital"]
    ok = ($issues.Count -eq 0)
    issues = @($issues)
}

$result | ConvertTo-Json -Depth 4
