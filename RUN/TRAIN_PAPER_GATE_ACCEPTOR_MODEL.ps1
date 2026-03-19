param(
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$ScriptPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py",
    [string]$DbPath = "C:\TRADING_DATA\RESEARCH\microbot_research.duckdb",
    [string]$OutputRoot = "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "ConcurrentLab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ResearchPython)) {
    throw "Research python not found: $ResearchPython"
}
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Training script not found: $ScriptPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

& "C:\MAKRO_I_MIKRO_BOT\RUN\SET_MICROBOT_RESEARCH_PERF_ENV.ps1" -Profile $PerfProfile | Out-Host

& $ResearchPython $ScriptPath --db-path $DbPath --output-root $OutputRoot
