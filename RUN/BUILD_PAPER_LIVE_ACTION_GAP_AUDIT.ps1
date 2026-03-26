param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$DailyReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\DAILY\raport_dzienny_latest.json",
    [string]$ActiveFleetVerdictsPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\active_fleet_verdicts_latest.json",
    [string]$DecisionLogsRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\logs",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$SessionCoordinatorPath = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state\_global\session_capital_coordinator.csv",
    [string]$FamilyStatesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state\_families",
    [string]$CapitalContractPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\capital_risk_contract_v1.json",
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

function Read-KeyValueTable {
    param([string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -notmatch "`t") {
            continue
        }
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2) {
            $map[[string]$parts[0]] = [string]$parts[1]
        }
    }

    return $map
}

function Get-MapString {
    param($Map,[string]$Key,[string]$Default = "")
    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) { return $Default }
    return [string]$Map[$Key]
}

function Get-MapBool {
    param($Map,[string]$Key,[bool]$Default = $false)
    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) { return $Default }
    return ([int]$Map[$Key]) -ne 0
}

function Get-MapDouble {
    param($Map,[string]$Key,[double]$Default = 0.0)
    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) { return $Default }
    return [double]::Parse([string]$Map[$Key],[System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-FamilyPolicyState {
    param(
        [string]$FamilyStatesRootPath,
        [string]$SessionProfile
    )

    if ([string]::IsNullOrWhiteSpace($SessionProfile)) {
        return [pscustomobject]@{
            present = $false
            paper_mode_active = $false
            trust_reason = "MISSING"
            family_daily_loss_pct = 0.0
        }
    }

    $path = Join-Path $FamilyStatesRootPath ("{0}\tuning_family_policy.csv" -f $SessionProfile)
    $raw = Read-KeyValueTable -Path $path
    if ($raw.Count -le 0) {
        return [pscustomobject]@{
            present = $false
            paper_mode_active = $false
            trust_reason = "MISSING"
            family_daily_loss_pct = 0.0
        }
    }

    return [pscustomobject]@{
        present = $true
        paper_mode_active = (Get-MapBool -Map $raw -Key "paper_mode_active")
        trust_reason = (Get-MapString -Map $raw -Key "trust_reason" -Default "UNASSESSED")
        family_daily_loss_pct = (Get-MapDouble -Map $raw -Key "family_daily_loss_pct")
        paper_defensive = ((Get-MapString -Map $raw -Key "trust_reason" -Default "") -eq "FAMILY_DAILY_LOSS_DEFENSIVE")
    }
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
        [int]$Closes,
        [bool]$FleetPaperLock,
        [bool]$FamilyPaperLock,
        [bool]$FleetPaperDefensive,
        [bool]$FamilyPaperDefensive
    )

    if (($Opens + $Closes) -gt 0) {
        return "AKTYWNY_HANDLOWO"
    }

    if ($FleetPaperLock) {
        return "BLOKADA_KAPITALU_FLOTY"
    }

    if ($FamilyPaperLock) {
        return "BLOKADA_KAPITALU_RODZINY"
    }

    if ($FleetPaperDefensive) {
        return "STEROWANIE_DEFENSYWNE_FLOTY"
    }

    if ($FamilyPaperDefensive) {
        return "STEROWANIE_DEFENSYWNE_RODZINY"
    }

    $reasons = @($LatestReason, $DominantReason) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($reason in $reasons) {
        switch -Regex ($reason) {
            '^DEFENSIVE_FAMILY$' { return "STEROWANIE_DEFENSYWNE_RODZINY" }
            '^DEFENSIVE_FLEET$' { return "STEROWANIE_DEFENSYWNE_FLOTY" }
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
        [string]$DirectBlock,
        [double]$FleetDailyLossPct,
        [double]$FleetHardLossPct,
        [double]$FamilyDailyLossPct,
        [double]$FamilyHardLossPct
    )

    if ($DirectBlock -eq "BLOKADA_KAPITALU_FLOTY") {
        return ("przekroczono twardy dzienny limit straty floty paper: {0:N2}% > {1:N2}%" -f $FleetDailyLossPct, $FleetHardLossPct)
    }
    if ($DirectBlock -eq "BLOKADA_KAPITALU_RODZINY") {
        return ("przekroczono twardy dzienny limit straty rodziny: {0:N2}% > {1:N2}%" -f $FamilyDailyLossPct, $FamilyHardLossPct)
    }
    if ($DirectBlock -eq "STEROWANIE_DEFENSYWNE_FLOTY") {
        return ("flota paper przeszla w tryb obronny po stracie {0:N2}%%; wejscia zostaly ograniczone, ale nie zamrozone" -f $FleetDailyLossPct)
    }
    if ($DirectBlock -eq "STEROWANIE_DEFENSYWNE_RODZINY") {
        return ("rodzina przeszla w tryb obronny po stracie {0:N2}%%; ryzyko jest scisniete, ale nauka nadal trwa" -f $FamilyDailyLossPct)
    }
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
        [string]$CostPressure,
        [bool]$BlockSensible
    )

    switch ($DirectBlock) {
        "AKTYWNY_HANDLOWO" { return "utrzymac pod obserwacja; symbol juz pracuje na paper-live" }
        "BLOKADA_KAPITALU_FLOTY" {
            if ($BlockSensible) { return "utrzymac blokade kapitalowa i naprawiac strate floty zamiast odmrazac recznie" }
            return "sprawdzic koordynator kapitalu; blokada floty wyglada ostrzej niz wynika z kontraktu"
        }
        "BLOKADA_KAPITALU_RODZINY" {
            if ($BlockSensible) { return "utrzymac blokade rodziny i najpierw zredukowac strate albo chaos tej rodziny" }
            return "sprawdzic koordynator kapitalu rodziny; blokada wyglada ostrzej niz wynika z kontraktu"
        }
        "STEROWANIE_DEFENSYWNE_FLOTY" { return "utrzymac tryb obronny floty i diagnozowac zrodlo strat zamiast odmrazac calosc" }
        "STEROWANIE_DEFENSYWNE_RODZINY" { return "utrzymac tryb obronny rodziny i poprawiac jej jakosc wejsc bez twardego freeze" }
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

$registry = Read-JsonSafe -Path $RegistryPath
$capitalContract = Read-JsonSafe -Path $CapitalContractPath
$sessionCoordinator = Read-KeyValueTable -Path $SessionCoordinatorPath
$symbolMetaMap = @{}
if ($null -ne $registry) {
    foreach ($row in @($registry.symbols)) {
        $alias = Normalize-SymbolAlias ([string]$row.symbol)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $symbolMetaMap[$alias] = $row
        }
    }
}

$paperHardDailyLossPct = if ($null -ne $capitalContract -and $null -ne $capitalContract.paper) { [double]$capitalContract.paper.account_hard_daily_loss_pct } else { 0.0 }
$paperFamilyHardLossPct = if ($null -ne $capitalContract -and $null -ne $capitalContract.paper) { [double]$capitalContract.paper.family_hard_daily_loss_pct } else { 0.0 }
$fleetPaperLock = Get-MapBool -Map $sessionCoordinator -Key "fleet_paper_lock"
$fleetPaperLockReason = Get-MapString -Map $sessionCoordinator -Key "fleet_paper_lock_reason" -Default "NONE"
$fleetPaperDefensive = Get-MapBool -Map $sessionCoordinator -Key "fleet_paper_defensive"
$fleetPaperDefensiveReason = Get-MapString -Map $sessionCoordinator -Key "fleet_paper_defensive_reason" -Default "NONE"
$fleetDailyLossPct = Get-MapDouble -Map $sessionCoordinator -Key "fleet_daily_loss_pct"
$runtimeProfile = Get-MapString -Map $sessionCoordinator -Key "runtime_profile" -Default "UNKNOWN"
$capitalThresholdProfile = Get-MapString -Map $sessionCoordinator -Key "capital_threshold_profile" -Default ""
$paperThresholdProfileMismatch = (($runtimeProfile -in @("PAPER_LIVE","LAPTOP_RESEARCH")) -and $capitalThresholdProfile -ne "paper")

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

    $meta = if ($symbolMetaMap.ContainsKey($alias)) { $symbolMetaMap[$alias] } else { $null }
    $sessionProfile = if ($null -ne $meta) { [string]$meta.session_profile } else { "" }
    $familyPolicy = Get-FamilyPolicyState -FamilyStatesRootPath $FamilyStatesRoot -SessionProfile $sessionProfile
    $familyPaperLock = [bool]$familyPolicy.paper_mode_active
    if ([string]$familyPolicy.trust_reason -ne "FAMILY_DAILY_LOSS_HARD") {
        $familyPaperLock = $false
    }
    $familyPaperDefensive = [bool]$familyPolicy.paper_defensive
    $familyDailyLossPct = [double]$familyPolicy.family_daily_loss_pct
    $decisionPath = Join-Path (Join-Path $DecisionLogsRoot $alias) "decision_events.csv"
    $decisionSummary = Get-DecisionReasonSummary -DecisionCsvPath $decisionPath -Window $DecisionWindow
    $opens = [int]$instrument.otwarcia_dzis
    $closes = [int]$instrument.zamkniecia_dzis
    $trustState = [string]$instrument.trust_state
    $costPressure = [string]$instrument.cost_pressure
    $directBlock = Resolve-DirectBlock `
        -LatestReason ([string]$decisionSummary.latest_reason) `
        -DominantReason ([string]$decisionSummary.dominant_reason) `
        -Opens $opens `
        -Closes $closes `
        -FleetPaperLock $fleetPaperLock `
        -FamilyPaperLock $familyPaperLock `
        -FleetPaperDefensive $fleetPaperDefensive `
        -FamilyPaperDefensive $familyPaperDefensive
    $blockSensible = $false
    if ($directBlock -eq "BLOKADA_KAPITALU_FLOTY" -and $paperHardDailyLossPct -gt 0) {
        $blockSensible = ($fleetDailyLossPct -ge $paperHardDailyLossPct)
    }
    elseif ($directBlock -eq "BLOKADA_KAPITALU_RODZINY" -and $paperFamilyHardLossPct -gt 0) {
        $blockSensible = ($familyDailyLossPct -ge $paperFamilyHardLossPct)
    }
    $deeperWhy = Resolve-DeeperWhy `
        -TrustState $trustState `
        -CostPressure $costPressure `
        -DirectBlock $directBlock `
        -FleetDailyLossPct $fleetDailyLossPct `
        -FleetHardLossPct $paperHardDailyLossPct `
        -FamilyDailyLossPct $familyDailyLossPct `
        -FamilyHardLossPct $paperFamilyHardLossPct
    $fleet = if ($fleetMap.ContainsKey($alias)) { $fleetMap[$alias] } else { $null }

    $items.Add([pscustomobject]@{
        symbol_alias = $alias
        session_profile = $sessionProfile
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
        blokada_kapitalu_floty = $fleetPaperLock
        powod_blokady_floty = $fleetPaperLockReason
        sterowanie_defensywne_floty = $fleetPaperDefensive
        powod_sterowania_defensywnego_floty = $fleetPaperDefensiveReason
        strata_floty_proc = [math]::Round($fleetDailyLossPct, 4)
        prog_twardy_floty_proc = [math]::Round($paperHardDailyLossPct, 4)
        blokada_kapitalu_rodziny = $familyPaperLock
        powod_blokady_rodziny = [string]$familyPolicy.trust_reason
        sterowanie_defensywne_rodziny = $familyPaperDefensive
        strata_rodziny_proc = [math]::Round($familyDailyLossPct, 4)
        prog_twardy_rodziny_proc = [math]::Round($paperFamilyHardLossPct, 4)
        blokada_sensowna = $blockSensible
        recommendation = Resolve-Recommendation -DirectBlock $directBlock -TrustState $trustState -CostPressure $costPressure -BlockSensible $blockSensible
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
    runtime_profile = $runtimeProfile
    capital_threshold_profile = $capitalThresholdProfile
    paper_threshold_profile_match = (-not $paperThresholdProfileMismatch)
    fleet_capital_lock_active = $fleetPaperLock
    fleet_capital_lock_reason = $fleetPaperLockReason
    fleet_capital_defensive_active = $fleetPaperDefensive
    fleet_capital_defensive_reason = $fleetPaperDefensiveReason
    fleet_daily_loss_pct = [math]::Round($fleetDailyLossPct, 4)
    paper_hard_daily_loss_pct = [math]::Round($paperHardDailyLossPct, 4)
    fleet_capital_lock_symbol_count = @($itemsArray | Where-Object { $_.direct_block -eq "BLOKADA_KAPITALU_FLOTY" }).Count
    family_capital_lock_symbol_count = @($itemsArray | Where-Object { $_.direct_block -eq "BLOKADA_KAPITALU_RODZINY" }).Count
    fleet_defensive_count = @($itemsArray | Where-Object { $_.direct_block -eq "STEROWANIE_DEFENSYWNE_FLOTY" }).Count
    family_defensive_count = @($itemsArray | Where-Object { $_.direct_block -eq "STEROWANIE_DEFENSYWNE_RODZINY" }).Count
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
$lines.Add(("- runtime_profile: {0}" -f $report.summary.runtime_profile))
$lines.Add(("- fleet_capital_lock_active: {0}" -f ([string]$report.summary.fleet_capital_lock_active).ToLowerInvariant()))
$lines.Add(("- fleet_capital_lock_reason: {0}" -f $report.summary.fleet_capital_lock_reason))
$lines.Add(("- fleet_daily_loss_pct: {0}" -f $report.summary.fleet_daily_loss_pct))
$lines.Add(("- paper_hard_daily_loss_pct: {0}" -f $report.summary.paper_hard_daily_loss_pct))
$lines.Add(("- fleet_capital_lock_symbol_count: {0}" -f $report.summary.fleet_capital_lock_symbol_count))
$lines.Add(("- family_capital_lock_symbol_count: {0}" -f $report.summary.family_capital_lock_symbol_count))
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
