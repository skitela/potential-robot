param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$TerminalOrigin = "C:\Program Files\OANDA TMS MT5 Terminal",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "Light",
    [int]$HoursBack = 96,
    [int]$TimeoutSec = 480,
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\broker_parity_refresh_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$exportFleetScript = Join-Path $ProjectRoot "RUN\EXPORT_BROKER_MINUTE_TAIL_ACTIVE_FLEET.ps1"
$refreshResearchScript = Join-Path $ProjectRoot "RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1"
$tailBridgeScript = Join-Path $ProjectRoot "RUN\BUILD_SERVER_PARITY_TAIL_BRIDGE.ps1"
$ledgerScript = Join-Path $ProjectRoot "RUN\BUILD_BROKER_NET_LEDGER.ps1"

foreach ($path in @($exportFleetScript, $refreshResearchScript, $tailBridgeScript, $ledgerScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$startedAt = Get-Date

$exportResult = & $exportFleetScript `
    -ProjectRoot $ProjectRoot `
    -TerminalOrigin $TerminalOrigin `
    -HoursBack $HoursBack `
    -TimeoutSec $TimeoutSec | ConvertFrom-Json

$researchResult = & $refreshResearchScript `
    -ProjectRoot $ProjectRoot `
    -EnvRoot $EnvRoot `
    -CommonRoot $CommonRoot `
    -OutputRoot $OutputRoot `
    -PerfProfile $PerfProfile | Out-String

$tailBridgeResult = & $tailBridgeScript | ConvertFrom-Json
$ledgerResult = & $ledgerScript | ConvertFrom-Json

$status = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    started_at_utc = $startedAt.ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    output_root = $OutputRoot
    terminal_origin = $TerminalOrigin
    perf_profile = $PerfProfile
    hours_back = $HoursBack
    export_fleet = $exportResult
    research_refresh_summary = $researchResult.Trim()
    tail_bridge = $tailBridgeResult
    broker_net_ledger = $ledgerResult
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
$status | ConvertTo-Json -Depth 10
