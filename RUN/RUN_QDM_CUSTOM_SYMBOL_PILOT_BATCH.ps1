param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string[]]$SymbolAliases = @("AUDUSD", "NZDUSD", "USDCAD", "USDJPY", "EURUSD", "GBPUSD"),
    [string]$TerminalRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [string]$Period = "M1",
    [string]$FromDate = "2026.03.12",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 300,
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_batch_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToolResultToObject {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }
        try {
            return ($text | ConvertFrom-Json -ErrorAction Stop)
        }
        catch {
            return [pscustomobject]@{ raw_output = $text }
        }
    }

    if ($Value -is [System.Array] -and $Value.Count -gt 0) {
        $joined = ($Value | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if (-not [string]::IsNullOrWhiteSpace($joined)) {
            try {
                return ($joined | ConvertFrom-Json -ErrorAction Stop)
            }
            catch {
                return [pscustomobject]@{ raw_output = $joined }
            }
        }
    }

    return $Value
}

$pilotScript = Join-Path $ProjectRoot "RUN\RUN_QDM_CUSTOM_SYMBOL_PILOT.ps1"
if (-not (Test-Path -LiteralPath $pilotScript)) {
    throw "Required pilot script not found: $pilotScript"
}

$pwsh = (Get-Command powershell.exe -ErrorAction Stop).Source
$results = New-Object System.Collections.Generic.List[object]

foreach ($symbolAlias in $SymbolAliases) {
    $normalizedAlias = [string]$symbolAlias
    if ([string]::IsNullOrWhiteSpace($normalizedAlias)) {
        continue
    }

    $runResult = $null
    $state = "completed"
    $errorMessage = $null

    try {
        $raw = & $pwsh `
            -ExecutionPolicy Bypass `
            -File $pilotScript `
            -ProjectRoot $ProjectRoot `
            -SymbolAlias $normalizedAlias `
            -QdmSymbol $normalizedAlias `
            -BrokerTemplateSymbol ("{0}.pro" -f $normalizedAlias.ToUpperInvariant()) `
            -Period $Period `
            -FromDate $FromDate `
            -ToDate $ToDate `
            -TerminalRoot $TerminalRoot `
            -TimeoutSec $TimeoutSec
        $exitCode = $LASTEXITCODE
        $runResult = Convert-ToolResultToObject -Value $raw
        if ($exitCode -ne 0) {
            $state = "failed"
            $errorMessage = "pilot_exit_code=$exitCode"
        }
    }
    catch {
        $state = "failed"
        $errorMessage = $_.Exception.Message
    }

    $results.Add([pscustomobject]@{
        symbol_alias = $normalizedAlias.ToUpperInvariant()
        state = $state
        error = $errorMessage
        result = $runResult
    }) | Out-Null
}

$successful = @($results | Where-Object { $_.state -eq "completed" }).Count
$failed = @($results | Where-Object { $_.state -ne "completed" }).Count
$batchState = if ($failed -gt 0) { "completed_with_failures" } else { "completed" }
$selectedSymbols = @($SymbolAliases | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$resultsArray = @($results.ToArray())

$report = [pscustomobject]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    selected_symbols = $selectedSymbols
    successful_count = $successful
    failed_count = $failed
    state = $batchState
    results = $resultsArray
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
$report | ConvertTo-Json -Depth 10
