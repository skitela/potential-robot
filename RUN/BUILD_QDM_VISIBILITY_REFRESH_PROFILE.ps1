param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$PythonExe = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolPath = Join-Path $ProjectRoot "TOOLS\BUILD_QDM_VISIBILITY_REFRESH_PROFILE.py"
$qdmProfilePath = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_missing_only_profile_latest.json"
$candidatePath = Join-Path $ResearchRoot "datasets\contracts\candidate_signals_norm_latest.parquet"
$qdmMinuteBarsPath = Join-Path $ResearchRoot "datasets\qdm_minute_bars_latest.parquet"
$globalMetricsPath = Join-Path $ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json"
$outputJson = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_visibility_refresh_profile_latest.json"
$outputMd = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_visibility_refresh_profile_latest.md"
$outputCsv = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_visibility_refresh_pack_latest.csv"

foreach ($path in @($toolPath, $PythonExe, $qdmProfilePath, $candidatePath, $qdmMinuteBarsPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required path not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputJson) | Out-Null

& $PythonExe $toolPath `
    --qdm-profile $qdmProfilePath `
    --candidate-contract $candidatePath `
    --qdm-minute-bars $qdmMinuteBarsPath `
    --global-metrics $globalMetricsPath `
    --output-json $outputJson `
    --output-md $outputMd `
    --output-csv $outputCsv

if ($LASTEXITCODE -ne 0) {
    throw "Failed to build QDM visibility refresh profile."
}

Get-Content -LiteralPath $outputJson -Raw -Encoding UTF8
