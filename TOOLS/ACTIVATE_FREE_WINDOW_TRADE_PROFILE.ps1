param(
    [ValidateSet("auto","winter","summer")]
    [string]$Season = "auto"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$python = "python"
$generator = Join-Path $root "BIN\apply_free_window_trade_profile.py"
$configDir = Join-Path $root "CONFIG"
$activePath = Join-Path $configDir "strategy.json"

if (-not (Test-Path $generator)) {
    throw "Missing generator: $generator"
}
if (-not (Test-Path $activePath)) {
    throw "Missing active strategy: $activePath"
}

$generatedPath = & $python $generator --season $Season
if ($LASTEXITCODE -ne 0) {
    throw "Generator failed."
}
$generatedPath = $generatedPath.Trim()
if (-not (Test-Path $generatedPath)) {
    throw "Generated strategy not found: $generatedPath"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $configDir ("strategy.backup_before_free_window_activation_{0}.json" -f $timestamp)
Copy-Item -Path $activePath -Destination $backupPath -Force
Copy-Item -Path $generatedPath -Destination $activePath -Force

$active = Get-Content -Path $activePath -Raw | ConvertFrom-Json
$report = [ordered]@{
    ts_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    season_requested = $Season
    season_activated = [string]$active.free_window_training_profile_season
    schema = [string]$active.free_window_training_profile_schema
    backup_path = $backupPath
    active_path = $activePath
    generated_path = $generatedPath
    symbols_to_trade = @($active.symbols_to_trade)
    trade_windows = @($active.trade_windows.PSObject.Properties.Name)
    trade_window_symbol_intents = @($active.trade_window_symbol_intents.PSObject.Properties.Name)
}

$evidenceDir = Join-Path $root "EVIDENCE"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$reportPath = Join-Path $evidenceDir ("free_window_trade_profile_activation_{0}.json" -f $timestamp)
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8

Write-Output $reportPath
