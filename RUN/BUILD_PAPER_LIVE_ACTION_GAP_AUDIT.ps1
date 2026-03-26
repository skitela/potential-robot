param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$DailyReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\DAILY\raport_dzienny_latest.json",
    [string]$ActiveFleetVerdictsPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\active_fleet_verdicts_latest.json",
    [string]$DecisionLogsRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\logs",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$DecisionWindow = 80
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Normalize-SymbolAlias {
    param([string]$Symbol)

    if ([string]::IsNullOrWhiteSpace($Symbol)) {
        return ""
    }

    return ($Symbol.Trim().ToUpperInvariant() -replace "\.PRO$", "")
}

function Get-DecisionReasonSummary {
    param(
        [string]$DecisionCsvPath,
        [int]$Window
    )

    if (-not (Test-Path -LiteralPath $DecisionCsvPath)) {
        return [pscustomobject]@{
            latest_reason = ""
            dominant_reason = ""
            latest_phase = ""
            rows_considered = 0
        }
    }

    $rows = @(
        Import-Csv -LiteralPath $DecisionCsvPath -Delimiter "`t" -Encoding UTF8 -ErrorAction SilentlyContinue |
            Select-Object -Last ([Math]::Max(20, $Window))
    )

    if ($rows.Count -le 0) {
        return [pscustomobject]@{
            latest_reason = ""
            dominant_reason = ""
            latest_phase = ""
            rows_considered = 0
        }
    }

    $latest = $rows[-1]
    $dominant = $rows | Group-Object reason | Sort-Object Count -Descending | Select-Object -First 1
    return [pscustomobject]@{
        latest_reason = [string]$latest.reason
        dominant_reason = if ($null -ne $dominant) { [string]$dominant.Name } else { "" }
        latest_phase = [string]$latest.phase
        rows_considered = $rows.Count
    }
}

function Resolve-DirectBlock {
    param(
        [string]$LatestReason,
        [string]$DominantReason,
        [int]$Opens,
        [int]$Closes
    )

    if (($Opens + $Closes) -gt 0) {
        return "AKTYWNY_HANDLOWO"
    }

    $reasons = @($LatestReason, $DominantReason) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($reason in $reasons) {
        switch -Regex ($reason) {
            '^LOW_SAMPLE$' { return "MALA_PROBKA" }
            '^FOREFIELD_DIRTY' { return "BRUDNY_FOREGROUND" }
            '^PAPER_CONVERSION_BLOCKED' { return "BLOKADA_KONWERSJI_PAPER" }
            '^FREEZE_FAMILY$' { return "ZAMROZENIE_RODZINY" }
            '^FREEZE_FLEET$' { return "ZAMROZENIE_FLOTY" }
            '^FLEET_FREEZE$' { return "ZAMROZENIE_FLOTY" }
            '^SCORE_BELOW_TRIGGER$' { return "WYNIK_PONIZEJ_PROGU" }
            '^POSITION_ALREADY_OPEN$' { return "POZYCJA_JUZ_OTWARTA" }
            '^NONE$' { return "BRAK_SETUPU" }
        }
    }

    return "BRAK_JASNEGO_POWODU_Z_LOGU"
}

function Resolve-DeeperWhy {
    param(
        [string]$TrustState,
        [string]$CostPressure,
        [string]$DirectBlock
    )

    if ($TrustState -eq "LOW_SAMPLE") {
        return "za mala probka lokalna"
    }
    if ($TrustState -eq "FOREFIELD_DIRTY") {
        return "foreground jest brudny i symbol nie spelnia warunkow zaufania"
    }
    if ($TrustState -eq "PAPER_CONVERSION_BLOCKED") {
        return "symbol jest zablokowany w konwersji paper przez kontrakt bezpieczenstwa"
    }
    if ($CostPressure -eq "NON_REPRESENTATIVE") {
        return "koszt i reprezentatywnosc sa zbyt slabe do dzialania"
    }
    if ($CostPressure -eq "HIGH") {
        return "koszt wejscia jest zbyt wysoki"
    }
    switch ($DirectBlock) {
        "ZAMROZENIE_RODZINY" { return "agent rodziny zablokowal wejscia" }
        "ZAMROZENIE_FLOTY" { return "agent floty zablokowal wejscia" }
        "WYNIK_PONIZEJ_PROGU" { return "sygnaly sa, ale score nie przebija progu wejscia" }
        "BRAK_SETUPU" { return "symbol zyje, ale nie widzi jeszcze setupu do dzialania" }
        "POZYCJA_JUZ_OTWARTA" { return "symbol byl juz zajety otwarta pozycja" }
        default { return "wymaga dalszej diagnozy" }
    }
}

function Resolve-Recommendation {
    param(
        [string]$DirectBlock,
        [string]$TrustState,
        [string]$CostPressure
    )

    switch ($DirectBlock) {
        "AKTYWNY_HANDLOWO" { return "utrzymac pod obserwacja; symbol juz pracuje na paper-live" }
        "MALA_PROBKA" { return "dalej budowac probe i nie wymuszac wejsc" }
        "BRUDNY_FOREGROUND" { return "oczyscic foreground i sprawdzic invalidacje kandydatow" }
        "BLOKADA_KONWERSJI_PAPER" { return "sprawdzic kontrakt bezpieczenstwa paper i powod blokady konwersji" }
        "ZAMROZENIE_RODZINY" { return "sprawdzic decyzje agenta rodziny i warunki odmrozenia" }
        "ZAMROZENIE_FLOTY" { return "sprawdzic decyzje agenta floty i warunki odmrozenia" }
        "WYNIK_PONIZEJ_PROGU" { return "przejrzec progi wejscia i score trigger" }
        "BRAK_SETUPU" { return "utrzymac obserwacje; brak technicznego setupu" }
        default {
            if ($CostPressure -in @("HIGH", "NON_REPRESENTATIVE")) {
                return "naprawic koszt i reprezentatywnosc zanim symbol wejdzie w dzialanie"
            }
            if ($TrustState -eq "TRUSTED") {
                return "szukac glebiej w decyzjach strojenia i progach wejscia"
            }
            return "diagnozowac dalej wraz z logami decyzji"
        }
    }
}

$dailyReport = Read-JsonSafe -Path $DailyReportPath
if ($null -eq $dailyReport -or $null -eq $dailyReport.instrumenty) {
    throw "Brakuje raportu dziennego z instrumentami: $DailyReportPath"
}

$activeFleetVerdicts = Read-JsonSafe -Path $ActiveFleetVerdictsPath
$fleetMap = @{}
if ($null -ne $activeFleetVerdicts) {
    $rows = if ($null -ne $activeFleetVerdicts.verdicts) { @($activeFleetVerdicts.verdicts) } else { @() }
    foreach ($row in $rows) {
        $alias = Normalize-SymbolAlias ([string]$row.symbol_alias)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $fleetMap[$alias] = $row
        }
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$items = New-Object System.Collections.Generic.List[object]

foreach ($instrument in @($dailyReport.instrumenty)) {
    $alias = Normalize-SymbolAlias ([string]$instrument.instrument)
    if ([string]::IsNullOrWhiteSpace($alias)) {
        continue
    }

    $decisionPath = Join-Path (Join-Path $DecisionLogsRoot $alias) "decision_events.csv"
    $decisionSummary = Get-DecisionReasonSummary -DecisionCsvPath $decisionPath -Window $DecisionWindow
    $opens = [int]$instrument.otwarcia_dzis
    $closes = [int]$instrument.zamkniecia_dzis
    $trustState = [string]$instrument.trust_state
    $costPressure = [string]$instrument.cost_pressure
    $directBlock = Resolve-DirectBlock -LatestReason ([string]$decisionSummary.latest_reason) -DominantReason ([string]$decisionSummary.dominant_reason) -Opens $opens -Closes $closes
    $deeperWhy = Resolve-DeeperWhy -TrustState $trustState -CostPressure $costPressure -DirectBlock $directBlock
    $fleet = if ($fleetMap.ContainsKey($alias)) { $fleetMap[$alias] } else { $null }

    $items.Add([pscustomobject]@{
        symbol_alias = $alias
        swiezy = [bool]$instrument.swiezy
        status_pracy = [string]$instrument.status_pracy
        otwarcia_dzis = $opens
        zamkniecia_dzis = $closes
        wygrane_dzis = [int]$instrument.wygrane_dzis
        przegrane_dzis = [int]$instrument.przegrane_dzis
        netto_dzis = [double]$instrument.netto_dzis
        trust_state = $trustState
        cost_pressure = $costPressure
        execution_quality = [string]$instrument.execution_quality
        latest_reason = [string]$decisionSummary.latest_reason
        dominant_reason_window = [string]$decisionSummary.dominant_reason
        latest_phase = [string]$decisionSummary.latest_phase
        direct_block = $directBlock
        deeper_why = $deeperWhy
        recommendation = Resolve-Recommendation -DirectBlock $directBlock -TrustState $trustState -CostPressure $costPressure
        business_status = if ($null -ne $fleet) { [string]$fleet.business_status } else { "" }
        onnx_status = if ($null -ne $fleet) { [string]$fleet.onnx_status } else { "" }
        onnx_jakosc = if ($null -ne $fleet) { [string]$fleet.onnx_jakosc } else { "" }
    }) | Out-Null
}

$itemsArray = @($items.ToArray() | Sort-Object @{ Expression = { if ($_.otwarcia_dzis -gt 0) { 0 } else { 1 } } }, symbol_alias)
$idleFresh = @($itemsArray | Where-Object { $_.swiezy -and $_.otwarcia_dzis -eq 0 })

$summary = [ordered]@{
    total_symbols = $itemsArray.Count
    fresh_symbols = @($itemsArray | Where-Object { $_.swiezy }).Count
    active_trade_count = @($itemsArray | Where-Object { $_.otwarcia_dzis -gt 0 }).Count
    fresh_but_idle_count = $idleFresh.Count
    fleet_freeze_count = @($itemsArray | Where-Object { $_.direct_block -eq "ZAMROZENIE_FLOTY" }).Count
    family_freeze_count = @($itemsArray | Where-Object { $_.direct_block -eq "ZAMROZENIE_RODZINY" }).Count
    low_sample_count = @($itemsArray | Where-Object { $_.direct_block -eq "MALA_PROBKA" }).Count
    foreground_dirty_count = @($itemsArray | Where-Object { $_.direct_block -eq "BRUDNY_FOREGROUND" }).Count
    paper_conversion_blocked_count = @($itemsArray | Where-Object { $_.direct_block -eq "BLOKADA_KONWERSJI_PAPER" }).Count
    cost_block_count = @($itemsArray | Where-Object { $_.cost_pressure -in @("HIGH", "NON_REPRESENTATIVE") -and $_.otwarcia_dzis -eq 0 }).Count
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    summary = $summary
    top_idle_symbols = @($idleFresh | Select-Object -First 10)
    top_active_symbols = @($itemsArray | Where-Object { $_.otwarcia_dzis -gt 0 } | Select-Object -First 10)
    items = $itemsArray
}

$jsonPath = Join-Path $OutputRoot "paper_live_action_gap_audit_latest.json"
$mdPath = Join-Path $OutputRoot "paper_live_action_gap_audit_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Paper Live Action Gap Audit")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- fresh_symbols: {0}" -f $report.summary.fresh_symbols))
$lines.Add(("- active_trade_count: {0}" -f $report.summary.active_trade_count))
$lines.Add(("- fresh_but_idle_count: {0}" -f $report.summary.fresh_but_idle_count))
$lines.Add(("- fleet_freeze_count: {0}" -f $report.summary.fleet_freeze_count))
$lines.Add(("- family_freeze_count: {0}" -f $report.summary.family_freeze_count))
$lines.Add(("- low_sample_count: {0}" -f $report.summary.low_sample_count))
$lines.Add(("- foreground_dirty_count: {0}" -f $report.summary.foreground_dirty_count))
$lines.Add(("- paper_conversion_blocked_count: {0}" -f $report.summary.paper_conversion_blocked_count))
$lines.Add(("- cost_block_count: {0}" -f $report.summary.cost_block_count))
$lines.Add("")
$lines.Add("## Fresh But Idle")
$lines.Add("")
if ($report.top_idle_symbols.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $report.top_idle_symbols) {
        $lines.Add(("- {0}: direct_block={1}, why={2}, trust={3}, cost={4}, latest_reason={5}, dominant_reason={6}" -f
            $item.symbol_alias,
            $item.direct_block,
            $item.deeper_why,
            $item.trust_state,
            $item.cost_pressure,
            $item.latest_reason,
            $item.dominant_reason_window))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
