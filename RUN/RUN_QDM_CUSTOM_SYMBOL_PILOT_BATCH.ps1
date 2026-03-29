param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string[]]$SymbolAliases = @(),
    [string]$TerminalRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [string]$Period = "M1",
    [string]$FromDate = "2026.03.12",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 300,
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_batch_latest.json",
    [string]$PilotRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_registry_latest.json",
    [string]$ReadinessReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_technical_readiness_latest.json",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json"
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

function Get-DefaultSymbolAliases {
    param(
        [string]$UniversePlanPath,
        [string]$RegistryPath,
        [string]$ReadinessReportPath
    )

    $fallback = @("AUDUSD", "EURAUD", "EURUSD", "GBPUSD", "USDCAD", "USDCHF", "USDJPY")
    if (Test-Path -LiteralPath $UniversePlanPath) {
        try {
            $plan = Get-Content -LiteralPath $UniversePlanPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $firstWave = @($plan.paper_live_first_wave | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($firstWave.Count -gt 0) {
                return [pscustomobject]@{
                    symbols = $firstWave
                    source = "scalping_universe_first_wave"
                }
            }
        }
        catch {
        }
    }

    if (Test-Path -LiteralPath $ReadinessReportPath) {
        try {
            $report = Get-Content -LiteralPath $ReadinessReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $entries = @($report.entries | Where-Object { $_.technical_readiness -eq "QDM_HISTORY_READY" })
            if ($entries.Count -gt 0) {
                $statusWeights = @{
                    "LIVE_POSITIVE" = 0
                    "TESTER_POSITIVE" = 1
                    "NEAR_PROFIT" = 2
                    "NEGATIVE" = 3
                }
                $symbols = @(
                    $entries |
                        Sort-Object @{
                            Expression = {
                                $status = [string]$_.business_status
                                if ($statusWeights.ContainsKey($status)) { $statusWeights[$status] } else { 9 }
                            }
                        }, @{
                            Expression = { [int]$_.priority_rank }
                        }, @{
                            Expression = { [string]$_.symbol_alias }
                        } |
                        ForEach-Object { ([string]$_.symbol_alias).ToUpperInvariant() }
                )
                if ($symbols.Count -gt 0) {
                    return [pscustomobject]@{
                        symbols = $symbols
                        source = "technical_readiness"
                    }
                }
            }
        }
        catch {
        }
    }

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        return [pscustomobject]@{
            symbols = $fallback
            source = "fallback"
        }
    }

    try {
        $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $symbols = @($registry.symbols | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($symbols.Count -gt 0) {
            return [pscustomobject]@{
                symbols = $symbols
                source = "registry"
            }
        }
    }
    catch {
    }

    return [pscustomobject]@{
        symbols = $fallback
        source = "fallback"
    }
}

function Get-SymbolResolutionMap {
    param(
        [string]$RegistryPath,
        [string]$ReadinessReportPath
    )

    $registryMap = @{}
    if (Test-Path -LiteralPath $RegistryPath) {
        try {
            $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($item in @($registry.symbols)) {
                $alias = ([string]$item.symbol).ToUpperInvariant()
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                $registryMap[$alias] = $item
            }
        }
        catch {
        }
    }

    $readinessMap = @{}
    if (Test-Path -LiteralPath $ReadinessReportPath) {
        try {
            $report = Get-Content -LiteralPath $ReadinessReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($entry in @($report.entries)) {
                $alias = ([string]$entry.symbol_alias).ToUpperInvariant()
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                $readinessMap[$alias] = $entry
            }
        }
        catch {
        }
    }

    $resolutionMap = @{}
    foreach ($alias in @($registryMap.Keys + $readinessMap.Keys | Sort-Object -Unique)) {
        $registryEntry = if ($registryMap.ContainsKey($alias)) { $registryMap[$alias] } else { $null }
        $readinessEntry = if ($readinessMap.ContainsKey($alias)) { $readinessMap[$alias] } else { $null }
        $resolutionMap[$alias] = [pscustomobject]@{
            symbol_alias = $alias
            qdm_symbol = if ($null -ne $readinessEntry -and -not [string]::IsNullOrWhiteSpace([string]$readinessEntry.qdm_symbol)) { [string]$readinessEntry.qdm_symbol } else { $alias }
            broker_template_symbol = if ($null -ne $registryEntry -and -not [string]::IsNullOrWhiteSpace([string]$registryEntry.broker_symbol)) { [string]$registryEntry.broker_symbol } else { "{0}.pro" -f $alias }
            expert_code_symbol = if ($null -ne $registryEntry -and -not [string]::IsNullOrWhiteSpace([string]$registryEntry.code_symbol)) { [string]$registryEntry.code_symbol } else { $alias }
        }
    }

    return $resolutionMap
}

$pilotScript = Join-Path $ProjectRoot "RUN\RUN_QDM_CUSTOM_SYMBOL_PILOT.ps1"
if (-not (Test-Path -LiteralPath $pilotScript)) {
    throw "Required pilot script not found: $pilotScript"
}

$pwsh = (Get-Command powershell.exe -ErrorAction Stop).Source
$results = New-Object System.Collections.Generic.List[object]
$defaultSymbols = Get-DefaultSymbolAliases -UniversePlanPath $UniversePlanPath -RegistryPath $PilotRegistryPath -ReadinessReportPath $ReadinessReportPath
$resolutionMap = Get-SymbolResolutionMap -RegistryPath $RegistryPath -ReadinessReportPath $ReadinessReportPath
$selectedSymbolInput = @($SymbolAliases | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$selectedSymbols = if ($selectedSymbolInput.Count -gt 0) { @($selectedSymbolInput) } else { @($defaultSymbols.symbols) }
$selectedSymbolSource = if ($selectedSymbolInput.Count -gt 0) { "manual" } else { [string]$defaultSymbols.source }

foreach ($symbolAlias in $selectedSymbols) {
    $normalizedAlias = [string]$symbolAlias
    if ([string]::IsNullOrWhiteSpace($normalizedAlias)) {
        continue
    }

    $runResult = $null
    $state = "completed"
    $errorMessage = $null

    try {
        $resolution = if ($resolutionMap.ContainsKey($normalizedAlias.ToUpperInvariant())) { $resolutionMap[$normalizedAlias.ToUpperInvariant()] } else { $null }
        $resolvedQdmSymbol = if ($null -ne $resolution) { [string]$resolution.qdm_symbol } else { $normalizedAlias }
        $resolvedBrokerTemplateSymbol = if ($null -ne $resolution) { [string]$resolution.broker_template_symbol } else { "{0}.pro" -f $normalizedAlias.ToUpperInvariant() }
        $resolvedExpertCodeSymbol = if ($null -ne $resolution) { [string]$resolution.expert_code_symbol } else { $normalizedAlias }

        $raw = & $pwsh `
            -ExecutionPolicy Bypass `
            -File $pilotScript `
            -ProjectRoot $ProjectRoot `
            -SymbolAlias $normalizedAlias `
            -QdmSymbol $resolvedQdmSymbol `
            -BrokerTemplateSymbol $resolvedBrokerTemplateSymbol `
            -ExpertCodeSymbol $resolvedExpertCodeSymbol `
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
        qdm_symbol = $resolvedQdmSymbol
        broker_template_symbol = $resolvedBrokerTemplateSymbol
        expert_code_symbol = $resolvedExpertCodeSymbol
        state = $state
        error = $errorMessage
        result = $runResult
    }) | Out-Null
}

$successful = @($results | Where-Object { $_.state -eq "completed" }).Count
$failed = @($results | Where-Object { $_.state -ne "completed" }).Count
$batchState = if ($failed -gt 0) { "completed_with_failures" } else { "completed" }
$resultsArray = @($results.ToArray())

$report = [pscustomobject]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    selected_symbols = @($selectedSymbols)
    selected_symbol_source = $selectedSymbolSource
    successful_count = $successful
    failed_count = $failed
    state = $batchState
    results = $resultsArray
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
$report | ConvertTo-Json -Depth 10
