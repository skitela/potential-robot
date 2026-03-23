param(
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$ScriptPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py",
    [string]$DbPath = "C:\TRADING_DATA\RESEARCH\microbot_research.duckdb",
    [string]$CandidateParquetPath = "C:\TRADING_DATA\RESEARCH\datasets\candidate_signals_latest.parquet",
    [string]$QdmParquetPath = "C:\TRADING_DATA\RESEARCH\datasets\qdm_minute_bars_latest.parquet",
    [string]$OutputRoot = "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor",
    [string]$SymbolFilter = "",
    [string]$ArtifactStem = "paper_gate_acceptor_latest",
    [string]$TeacherModelPath = "",
    [switch]$ExportRuntimeNumeric,
    [string]$RuntimeOutputRoot = "",
    [string]$RuntimeArtifactStem = "",
    [int]$MinRows = 10000,
    [int]$MinPositiveRows = 500,
    [int]$MinNegativeRows = 500,
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

$arguments = @(
    $ScriptPath,
    "--db-path", $DbPath,
    "--candidate-parquet-path", $CandidateParquetPath,
    "--qdm-parquet-path", $QdmParquetPath,
    "--output-root", $OutputRoot,
    "--artifact-stem", $ArtifactStem,
    "--min-rows", $MinRows,
    "--min-positive-rows", $MinPositiveRows,
    "--min-negative-rows", $MinNegativeRows
)

if (-not [string]::IsNullOrWhiteSpace($SymbolFilter)) {
    $arguments += @("--symbol-filter", $SymbolFilter.Trim().ToUpperInvariant())
}
if (-not [string]::IsNullOrWhiteSpace($TeacherModelPath)) {
    $arguments += @("--teacher-model-path", $TeacherModelPath)
}
if ($ExportRuntimeNumeric) {
    $arguments += "--export-runtime-numeric"
}
if (-not [string]::IsNullOrWhiteSpace($RuntimeOutputRoot)) {
    $arguments += @("--runtime-output-root", $RuntimeOutputRoot)
}
if (-not [string]::IsNullOrWhiteSpace($RuntimeArtifactStem)) {
    $arguments += @("--runtime-artifact-stem", $RuntimeArtifactStem)
}

& $ResearchPython @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Paper gate trainer failed with exit code $LASTEXITCODE"
}
