param(
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$PriorityPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.json",
    [string]$OnnxRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string]$ReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_technical_readiness_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-SymbolAlias {
    param([string]$Symbol)

    if ([string]::IsNullOrWhiteSpace($Symbol)) {
        return ""
    }

    return ($Symbol.Trim().ToUpperInvariant() -replace "\.PRO$", "")
}

function Resolve-FleetVerdict {
    param(
        [string]$BusinessStatus,
        [string]$OnnxStatus,
        [bool]$QdmReady,
        [string]$PriorityBand
    )

    if ($BusinessStatus -eq "LIVE_POSITIVE") {
        return "UTRZYMAC"
    }

    if ($BusinessStatus -eq "TESTER_POSITIVE") {
        if ($QdmReady -and $OnnxStatus -eq "MODEL_PER_SYMBOL_READY") {
            return "KANDYDAT_PAPER_LIVE"
        }
        return "DOCISNAC"
    }

    if ($BusinessStatus -eq "NEAR_PROFIT") {
        return "DOCISNAC"
    }

    if ($PriorityBand -in @("CRITICAL", "HIGH")) {
        return "OBSERWOWAC"
    }

    return "OBNIZYC_PRIORYTET"
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    throw "Registry not found: $RegistryPath"
}
if (-not (Test-Path -LiteralPath $ProfitTrackingPath)) {
    throw "Profit tracking not found: $ProfitTrackingPath"
}
if (-not (Test-Path -LiteralPath $PriorityPath)) {
    throw "Priority report not found: $PriorityPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profitTracking = Get-Content -LiteralPath $ProfitTrackingPath -Raw -Encoding UTF8 | ConvertFrom-Json
$priorityReport = Get-Content -LiteralPath $PriorityPath -Raw -Encoding UTF8 | ConvertFrom-Json
$onnxRegistry = if (Test-Path -LiteralPath $OnnxRegistryPath) {
    Get-Content -LiteralPath $OnnxRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $null
}
$readinessReport = if (Test-Path -LiteralPath $ReadinessPath) {
    Get-Content -LiteralPath $ReadinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $null
}

$profitMap = @{}
foreach ($group in @("live_positive", "tester_positive", "near_profit", "runtime_watchlist", "all")) {
    if ($profitTracking.PSObject.Properties.Name -contains $group) {
        foreach ($item in @($profitTracking.$group)) {
            $alias = Normalize-SymbolAlias ([string]$item.symbol_alias)
            if (-not [string]::IsNullOrWhiteSpace($alias) -and -not $profitMap.ContainsKey($alias)) {
                $profitMap[$alias] = $item
            }
        }
    }
}

$priorityMap = @{}
foreach ($item in @($priorityReport.ranked_instruments)) {
    $alias = Normalize-SymbolAlias ([string]$item.symbol_alias)
    if (-not [string]::IsNullOrWhiteSpace($alias)) {
        $priorityMap[$alias] = $item
    }
}

$onnxMap = @{}
if ($null -ne $onnxRegistry -and $onnxRegistry.PSObject.Properties.Name -contains "items") {
    foreach ($item in @($onnxRegistry.items)) {
        $alias = Normalize-SymbolAlias ([string]$item.symbol)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $onnxMap[$alias] = $item
        }
    }
}

$readinessMap = @{}
if ($null -ne $readinessReport -and $readinessReport.PSObject.Properties.Name -contains "entries") {
    foreach ($item in @($readinessReport.entries)) {
        $alias = Normalize-SymbolAlias ([string]$item.symbol_alias)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $readinessMap[$alias] = $item
        }
    }
}

$verdicts = @(
    @($registry.symbols) |
        ForEach-Object {
            $alias = Normalize-SymbolAlias ([string]$_.symbol)
            $profit = if ($profitMap.ContainsKey($alias)) { $profitMap[$alias] } else { $null }
            $priority = if ($priorityMap.ContainsKey($alias)) { $priorityMap[$alias] } else { $null }
            $onnx = if ($onnxMap.ContainsKey($alias)) { $onnxMap[$alias] } else { $null }
            $readiness = if ($readinessMap.ContainsKey($alias)) { $readinessMap[$alias] } else { $null }
            $businessStatus = if ($null -ne $profit) { [string]$profit.status } else { "NEGATIVE" }
            $priorityBand = if ($null -ne $profit) { [string]$profit.current_priority_band } elseif ($null -ne $priority) { [string]$priority.priority_band } else { "" }
            $priorityRank = if ($null -ne $profit) { [int]$profit.priority_rank } elseif ($null -ne $priority) { [int]$priority.rank } else { 999 }
            $onnxStatus = if ($null -ne $onnx) { [string]$onnx.status } else { "BRAK" }
            $qdmReady = if ($null -ne $profit) { [bool]$profit.qdm_custom_pilot_ready } elseif ($null -ne $readiness) { [string]$readiness.technical_readiness -eq "FULL_QDM_CUSTOM_READY" } else { $false }
            $verdict = Resolve-FleetVerdict -BusinessStatus $businessStatus -OnnxStatus $onnxStatus -QdmReady $qdmReady -PriorityBand $priorityBand

            [pscustomobject]@{
                symbol_alias = $alias
                session_profile = [string]$_.session_profile
                business_status = $businessStatus
                priority_band = $priorityBand
                priority_rank = $priorityRank
                technical_readiness = if ($null -ne $readiness) { [string]$readiness.technical_readiness } else { "UNKNOWN" }
                onnx_status = $onnxStatus
                qdm_custom_gotowy = $qdmReady
                tester_pnl_usd = if ($null -ne $profit) { $profit.best_tester_pnl } else { $null }
                live_net_24h = if ($null -ne $profit) { $profit.live_net_24h } else { $null }
                recommended_action = if ($null -ne $profit) { [string]$profit.recommended_action } elseif ($null -ne $priority) { [string]$priority.recommended_action } else { "" }
                werdykt_koncowy = $verdict
            }
        } |
        Sort-Object @{ Expression = { $_.priority_rank } }, symbol_alias
)

$summary = [ordered]@{
    total_symbols = $verdicts.Count
    kandydat_paper_live = @($verdicts | Where-Object { $_.werdykt_koncowy -eq "KANDYDAT_PAPER_LIVE" }).Count
    docisnac = @($verdicts | Where-Object { $_.werdykt_koncowy -eq "DOCISNAC" }).Count
    utrzymac = @($verdicts | Where-Object { $_.werdykt_koncowy -eq "UTRZYMAC" }).Count
    obserwowac = @($verdicts | Where-Object { $_.werdykt_koncowy -eq "OBSERWOWAC" }).Count
    obnizyc_priorytet = @($verdicts | Where-Object { $_.werdykt_koncowy -eq "OBNIZYC_PRIORYTET" }).Count
}

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    summary = $summary
    verdicts = $verdicts
}

$jsonPath = Join-Path $OutputRoot "active_fleet_verdicts_latest.json"
$mdPath = Join-Path $OutputRoot "active_fleet_verdicts_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Werdykty Aktywnej Floty")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- liczba instrumentow: {0}" -f $summary.total_symbols))
$lines.Add(("- kandydat_paper_live: {0}" -f $summary.kandydat_paper_live))
$lines.Add(("- docisnac: {0}" -f $summary.docisnac))
$lines.Add(("- utrzymac: {0}" -f $summary.utrzymac))
$lines.Add(("- obserwowac: {0}" -f $summary.obserwowac))
$lines.Add(("- obnizyc_priorytet: {0}" -f $summary.obnizyc_priorytet))
$lines.Add("")
foreach ($item in @($verdicts)) {
    $lines.Add(("- {0}: werdykt={1}, status={2}, profil={3}, onnx={4}, qdm={5}, tester_pnl_usd={6}, live_net_24h={7}, action={8}" -f
        $item.symbol_alias,
        $item.werdykt_koncowy,
        $item.business_status,
        $item.session_profile,
        $item.onnx_status,
        $item.qdm_custom_gotowy,
        $item.tester_pnl_usd,
        $item.live_net_24h,
        $item.recommended_action))
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
