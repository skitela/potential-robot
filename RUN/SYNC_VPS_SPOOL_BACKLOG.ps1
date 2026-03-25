param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$SourceRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\spool"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pythonExe = Join-Path $EnvRoot "Scripts\python.exe"
$scriptPath = Join-Path $ProjectRoot "TOOLS\IMPORT_VPS_SPOOL_CHUNKS.py"
$outputJson = Join-Path $ProjectRoot "EVIDENCE\OPS\vps_spool_sync_latest.json"
$latestMd = Join-Path $ProjectRoot "EVIDENCE\OPS\vps_spool_sync_latest.md"
$statePath = Join-Path $ResearchRoot "reports\vps_spool_sync_state_latest.json"
$inboxRoot = Join-Path $ResearchRoot "vps_spool_inbox"

if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Research python not found: $pythonExe"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Spool import script not found: $scriptPath"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputJson) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $statePath) | Out-Null
New-Item -ItemType Directory -Force -Path $inboxRoot | Out-Null

& $pythonExe $scriptPath `
    --source-root $SourceRoot `
    --inbox-root $inboxRoot `
    --state-path $statePath `
    --output-json $outputJson `
    --latest-md $latestMd
