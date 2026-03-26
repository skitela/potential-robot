param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_PAPER_LOSS_SOURCE_AUDIT.py"
$dailyReportPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\raport_dzienny_latest.json"
$outputJson = Join-Path $ProjectRoot "EVIDENCE\OPS\paper_loss_source_audit_latest.json"
$outputMd = Join-Path $ProjectRoot "EVIDENCE\OPS\paper_loss_source_audit_latest.md"

foreach ($path in @($ResearchPython, $scriptPath, $dailyReportPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required path not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputJson) | Out-Null

& $ResearchPython $scriptPath `
    --project-root $ProjectRoot `
    --common-root $CommonRoot `
    --daily-report $dailyReportPath `
    --output-json $outputJson `
    --output-md $outputMd

if ($LASTEXITCODE -ne 0) {
    throw "Failed to build paper loss source audit."
}

Get-Content -LiteralPath $outputJson -Raw -Encoding UTF8
