param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$DbPath = "C:\TRADING_DATA\RESEARCH\microbot_research.duckdb",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$OutcomeHorizonSec = 21600,
    [double]$ScoreThreshold = 0.5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pythonExe = Join-Path $EnvRoot "Scripts\python.exe"
$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_ONNX_FEEDBACK_LOOP_REPORT.py"

if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Research python not found: $pythonExe"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "ONNX feedback report script not found: $scriptPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

& $pythonExe $scriptPath `
    --db-path $DbPath `
    --output-root $OutputRoot `
    --outcome-horizon-sec $OutcomeHorizonSec `
    --score-threshold $ScoreThreshold
