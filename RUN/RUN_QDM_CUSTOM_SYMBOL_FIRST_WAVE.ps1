param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json",
    [string]$TerminalRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [string]$Period = "M1",
    [string]$FromDate = "2026.03.12",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 300,
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_first_wave_latest.json",
    [string]$LatestMarkdownPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_first_wave_latest.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FirstWaveSymbols {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Universe plan not found: $Path"
    }

    $plan = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $symbols = @($plan.paper_live_first_wave | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($symbols.Count -le 0) {
        throw "Universe plan has no paper_live_first_wave symbols."
    }

    return [pscustomobject]@{
        universe_version = [string]$plan.universe_version
        symbols = $symbols
    }
}

function Write-MarkdownReport {
    param(
        [string]$Path,
        [object]$Payload
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# QDM Custom Symbol First Wave")
    $lines.Add("")
    $lines.Add(("- generated_at_utc: {0}" -f $Payload.generated_at_utc))
    $lines.Add(("- universe_version: {0}" -f $Payload.universe_version))
    $lines.Add(("- state: {0}" -f $Payload.state))
    $lines.Add(("- successful_count: {0}" -f $Payload.successful_count))
    $lines.Add(("- failed_count: {0}" -f $Payload.failed_count))
    $lines.Add("")
    $lines.Add("## Symbols")
    $lines.Add("")
    foreach ($entry in @($Payload.results)) {
        $lines.Add(("### {0}" -f $entry.symbol_alias))
        $lines.Add(("- state: {0}" -f $entry.state))
        $lines.Add(("- broker_template_symbol: {0}" -f $entry.broker_template_symbol))
        $lines.Add(("- qdm_symbol: {0}" -f $entry.qdm_symbol))
        if ($null -ne $entry.result) {
            $customSymbol = $entry.result.custom_symbol
            if (-not [string]::IsNullOrWhiteSpace([string]$customSymbol)) {
                $lines.Add(("- custom_symbol: {0}" -f $customSymbol))
            }
            $importMessage = $entry.result.smoke.import_message
            if (-not [string]::IsNullOrWhiteSpace([string]$importMessage)) {
                $lines.Add(("- import_message: {0}" -f $importMessage))
            }
            $resultLabel = $entry.result.smoke.result_label
            if (-not [string]::IsNullOrWhiteSpace([string]$resultLabel)) {
                $lines.Add(("- smoke_result: {0}" -f $resultLabel))
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.error)) {
            $lines.Add(("- error: {0}" -f $entry.error))
        }
        $lines.Add("")
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    ($lines -join "`r`n") | Set-Content -LiteralPath $Path -Encoding UTF8
}

$batchScript = Join-Path $ProjectRoot "RUN\RUN_QDM_CUSTOM_SYMBOL_PILOT_BATCH.ps1"
if (-not (Test-Path -LiteralPath $batchScript)) {
    throw "Required batch script not found: $batchScript"
}

$firstWave = Get-FirstWaveSymbols -Path $UniversePlanPath
$raw = & $batchScript `
    -ProjectRoot $ProjectRoot `
    -UniversePlanPath $UniversePlanPath `
    -SymbolAliases $firstWave.symbols `
    -TerminalRoot $TerminalRoot `
    -Period $Period `
    -FromDate $FromDate `
    -ToDate $ToDate `
    -TimeoutSec $TimeoutSec `
    -LatestStatusPath $LatestStatusPath

$payload = if ($raw -is [string]) { $raw | ConvertFrom-Json } else { $raw }
$payload | Add-Member -NotePropertyName universe_version -NotePropertyValue $firstWave.universe_version -Force
$payload | Add-Member -NotePropertyName symbol_scope -NotePropertyValue "paper_live_first_wave" -Force

$payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
Write-MarkdownReport -Path $LatestMarkdownPath -Payload $payload

$payload | ConvertTo-Json -Depth 12
