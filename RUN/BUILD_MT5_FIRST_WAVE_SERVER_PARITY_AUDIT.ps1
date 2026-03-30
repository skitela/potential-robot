param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json",
    [string]$ContractPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\mt5_first_wave_server_parity_v1.json",
    [string]$RealismAuditPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_realism_audit_latest.json",
    [string]$TradeTransitionAuditPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\trade_transition_audit_latest.json",
    [string]$TruthStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_pretrade_execution_truth_status_latest.json",
    [string]$LocalModelReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\local_model_readiness_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
}

function Get-SafeObjectValue {
    param(
        [object]$Object,
        [string]$PropertyName,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        return $Object.$PropertyName
    }

    return $Default
}

function Test-TextValue {
    param([object]$Value)

    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-UpperSymbolMap {
    param(
        [object[]]$Items,
        [string]$PropertyName = "symbol_alias"
    )

    $map = @{}
    foreach ($entry in @($Items)) {
        $key = ([string](Get-SafeObjectValue -Object $entry -PropertyName $PropertyName -Default "")).ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }

        $map[$key] = $entry
    }

    return $map
}

$jsonPath = Join-Path $OutputRoot "mt5_first_wave_server_parity_latest.json"
$mdPath = Join-Path $OutputRoot "mt5_first_wave_server_parity_latest.md"
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$plan = Read-JsonFile -Path $UniversePlanPath
$contract = Read-JsonFile -Path $ContractPath
$realismAudit = Read-JsonFile -Path $RealismAuditPath
$tradeTransitionAudit = Read-JsonFile -Path $TradeTransitionAuditPath
$truthStatus = Read-JsonFile -Path $TruthStatusPath
$localModelReadiness = Read-JsonFile -Path $LocalModelReadinessPath

if ($null -eq $plan) { throw "Universe plan missing: $UniversePlanPath" }
if ($null -eq $contract) { throw "Parity contract missing: $ContractPath" }

$planFirstWave = @($plan.paper_live_first_wave | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$contractSymbols = @($contract.target_symbols | ForEach-Object { ([string]$_.symbol_alias).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$contractSymbolMap = Get-UpperSymbolMap -Items @($contract.target_symbols)
$realismMap = if ($null -ne $realismAudit) { Get-UpperSymbolMap -Items @($realismAudit.results) } else { @{} }
$truthHookMap = if ($null -ne $truthStatus) { Get-UpperSymbolMap -Items @($truthStatus.hooks.items) } else { @{} }
$localModelMap = if ($null -ne $localModelReadiness) { Get-UpperSymbolMap -Items @($localModelReadiness.items) } else { @{} }

$truthSummary = Get-SafeObjectValue -Object $truthStatus -PropertyName "truth_summary" -Default $null
$tradeSummary = Get-SafeObjectValue -Object $tradeTransitionAudit -PropertyName "summary" -Default $null

$migrationConfirmed = [bool](Get-SafeObjectValue -Object $tradeSummary -PropertyName "migration_confirmed" -Default $false)
$paperLiveSyncOk = [bool](Get-SafeObjectValue -Object $tradeSummary -PropertyName "paper_live_sync_ok" -Default $false)
$serverPingReady = [bool](Get-SafeObjectValue -Object $tradeSummary -PropertyName "server_execution_ping_contract_enabled" -Default $false)
$serverLatencyReady = (
    [bool](Get-SafeObjectValue -Object $tradeSummary -PropertyName "global_model_uses_runtime_latency" -Default $false) -and
    [bool](Get-SafeObjectValue -Object $tradeSummary -PropertyName "global_model_uses_server_ping" -Default $false) -and
    [bool](Get-SafeObjectValue -Object $tradeSummary -PropertyName "global_model_uses_server_latency" -Default $false)
)
$runtimeProfile = [string](Get-SafeObjectValue -Object $tradeSummary -PropertyName "paper_runtime_profile" -Default "")
$targetRuntimeProfile = [string](Get-SafeObjectValue -Object $contract -PropertyName "target_runtime_profile" -Default "")
$runtimeProfileMatch = (Test-TextValue -Value $runtimeProfile) -and ($runtimeProfile -eq $targetRuntimeProfile)
$capitalIsolationReady = -not [bool](Get-SafeObjectValue -Object $tradeSummary -PropertyName "paper_fleet_capital_lock_active" -Default $false)
$activePresetCoverageReady = ([int](Get-SafeObjectValue -Object $tradeSummary -PropertyName "profile_active_chart_count" -Default 0) -eq $contractSymbols.Count)
$liveTruthDataReady = (
    [int](Get-SafeObjectValue -Object $truthSummary -PropertyName "pretrade_rows" -Default 0) -gt 0 -and
    [int](Get-SafeObjectValue -Object $truthSummary -PropertyName "execution_rows" -Default 0) -gt 0 -and
    [int](Get-SafeObjectValue -Object $truthSummary -PropertyName "truth_chain_rows" -Default 0) -gt 0
)

$results = New-Object System.Collections.Generic.List[object]

foreach ($symbolAlias in $contractSymbols) {
    $contractEntry = $contractSymbolMap[$symbolAlias]
    $realismEntry = if ($realismMap.ContainsKey($symbolAlias)) { $realismMap[$symbolAlias] } else { $null }
    $truthHookEntry = if ($truthHookMap.ContainsKey($symbolAlias)) { $truthHookMap[$symbolAlias] } else { $null }
    $modelEntry = if ($localModelMap.ContainsKey($symbolAlias)) { $localModelMap[$symbolAlias] } else { $null }

    $expectedBrokerSymbol = [string](Get-SafeObjectValue -Object $contractEntry -PropertyName "broker_symbol" -Default "")
    $expectedCustomSymbol = [string](Get-SafeObjectValue -Object $contractEntry -PropertyName "custom_symbol" -Default "")
    $brokerTemplateSymbol = [string](Get-SafeObjectValue -Object $realismEntry -PropertyName "broker_template_symbol" -Default (Get-SafeObjectValue -Object $modelEntry -PropertyName "broker_symbol" -Default ""))
    $customSymbol = [string](Get-SafeObjectValue -Object $realismEntry -PropertyName "custom_symbol" -Default "")

    $propertyMirrorReady = [bool](Get-SafeObjectValue -Object $realismEntry -PropertyName "property_mirror_ready" -Default $false)
    $sessionMirrorReady = [bool](Get-SafeObjectValue -Object $realismEntry -PropertyName "session_mirror_ready" -Default $false)
    $brokerMirrorReady = [bool](Get-SafeObjectValue -Object $realismEntry -PropertyName "broker_mirror_ready" -Default $false)
    $smokeReady = [bool](Get-SafeObjectValue -Object $realismEntry -PropertyName "smoke_ready" -Default $false)
    $learningReady = [bool](Get-SafeObjectValue -Object $realismEntry -PropertyName "learning_ready" -Default $false)
    $learningObservationRows = [int](Get-SafeObjectValue -Object $realismEntry -PropertyName "learning_observation_rows" -Default 0)

    $pretradeHookReady = (
        [bool](Get-SafeObjectValue -Object $truthHookEntry -PropertyName "pretrade_include" -Default $false) -and
        [bool](Get-SafeObjectValue -Object $truthHookEntry -PropertyName "pretrade_call" -Default $false)
    )
    $executionHookReady = (
        [bool](Get-SafeObjectValue -Object $truthHookEntry -PropertyName "execution_include" -Default $false) -and
        [bool](Get-SafeObjectValue -Object $truthHookEntry -PropertyName "execution_call" -Default $false)
    )
    $truthHooksReady = ($pretradeHookReady -and $executionHookReady)
    $symbolLiveTruthReady = ($truthHooksReady -and $liveTruthDataReady)

    $runtimeContractPresent = [bool](Get-SafeObjectValue -Object $modelEntry -PropertyName "runtime_contract_present" -Default $false)
    $localModelAvailable = [bool](Get-SafeObjectValue -Object $modelEntry -PropertyName "local_model_available" -Default $false)
    $rollbackDetected = [bool](Get-SafeObjectValue -Object $modelEntry -PropertyName "rollback_detected" -Default $false)
    $guardrailState = [string](Get-SafeObjectValue -Object $modelEntry -PropertyName "guardrail_state" -Default "")
    $teacherDependencyLevel = [string](Get-SafeObjectValue -Object $modelEntry -PropertyName "teacher_dependency_level" -Default "")

    $brokerSymbolMatch = (Test-TextValue -Value $expectedBrokerSymbol) -and ($brokerTemplateSymbol -eq $expectedBrokerSymbol)
    $customSymbolMatch = (Test-TextValue -Value $expectedCustomSymbol) -and ($customSymbol -eq $expectedCustomSymbol)
    $rollbackGuardAllowed = (-not $rollbackDetected) -and ($guardrailState -ne "FORCED_GLOBAL_FALLBACK")

    $nearServerReady = (
        $brokerSymbolMatch -and
        $customSymbolMatch -and
        $brokerMirrorReady -and
        $smokeReady -and
        $learningReady -and
        $truthHooksReady -and
        $symbolLiveTruthReady -and
        $runtimeContractPresent -and
        $localModelAvailable -and
        $rollbackGuardAllowed
    )

    $parityState = if ($nearServerReady) {
        "PRAWIE_SERWEROWY"
    }
    elseif ($brokerMirrorReady -and $smokeReady -and $learningReady -and $truthHooksReady -and $runtimeContractPresent) {
        "CZESCIOWO_GOTOWY"
    }
    else {
        "WYMAGA_DALSZEGO_WDROZENIA"
    }

    $blockers = New-Object System.Collections.Generic.List[string]
    if (-not $brokerSymbolMatch) { $blockers.Add("NIEZGODNY_SYMBOL_BROKERA") | Out-Null }
    if (-not $customSymbolMatch) { $blockers.Add("NIEZGODNY_SYMBOL_LABORATORYJNY") | Out-Null }
    if (-not $propertyMirrorReady) { $blockers.Add("BRAK_LUSTRA_WLASCIWOSCI") | Out-Null }
    if (-not $sessionMirrorReady) { $blockers.Add("BRAK_LUSTRA_SESJI") | Out-Null }
    if (-not $brokerMirrorReady) { $blockers.Add("BRAK_GOTOWEGO_LUSTRA_BROKERA") | Out-Null }
    if (-not $smokeReady) { $blockers.Add("BRAK_POPRAWNEGO_PRZEBIEGU_TESTOWEGO") | Out-Null }
    if (-not $learningReady) { $blockers.Add("BRAK_GOTOWEGO_MATERIALU_UCZACEGO") | Out-Null }
    if (-not $pretradeHookReady) { $blockers.Add("BRAK_HAKA_PRZED_ZLECENIEM") | Out-Null }
    if (-not $executionHookReady) { $blockers.Add("BRAK_HAKA_WYKONANIA") | Out-Null }
    if (-not $symbolLiveTruthReady) { $blockers.Add("BRAK_ZYWEJ_PRAWDY_WYKONANIA") | Out-Null }
    if (-not $runtimeContractPresent) { $blockers.Add("BRAK_KONTRAKTU_WYKONAWCZEGO") | Out-Null }
    if (-not $localModelAvailable) { $blockers.Add("BRAK_MODELU_LOKALNEGO") | Out-Null }
    if (-not $rollbackGuardAllowed) { $blockers.Add("AKTYWNY_BEZPIECZNIK_ROLLBACK") | Out-Null }

    $results.Add([pscustomobject]@{
        symbol_alias = $symbolAlias
        broker_symbol = $expectedBrokerSymbol
        broker_symbol_observed = $brokerTemplateSymbol
        broker_symbol_match = $brokerSymbolMatch
        custom_symbol = $expectedCustomSymbol
        custom_symbol_observed = $customSymbol
        custom_symbol_match = $customSymbolMatch
        property_mirror_ready = $propertyMirrorReady
        session_mirror_ready = $sessionMirrorReady
        broker_mirror_ready = $brokerMirrorReady
        smoke_ready = $smokeReady
        learning_ready = $learningReady
        learning_observation_rows = $learningObservationRows
        pretrade_truth_hook_ready = $pretradeHookReady
        execution_truth_hook_ready = $executionHookReady
        live_truth_data_ready = $symbolLiveTruthReady
        runtime_contract_present = $runtimeContractPresent
        local_model_available = $localModelAvailable
        rollback_guard_allowed = $rollbackGuardAllowed
        teacher_dependency_level = $teacherDependencyLevel
        parity_state = $parityState
        blockers = @($blockers)
    }) | Out-Null
}

$resultsArray = $results.ToArray()
$nearServerCount = @($resultsArray | Where-Object { $_.parity_state -eq "PRAWIE_SERWEROWY" }).Count
$partialCount = @($resultsArray | Where-Object { $_.parity_state -eq "CZESCIOWO_GOTOWY" }).Count
$blockedCount = @($resultsArray | Where-Object { $_.parity_state -eq "WYMAGA_DALSZEGO_WDROZENIA" }).Count
$truthHookReadyCount = @($resultsArray | Where-Object { $_.pretrade_truth_hook_ready -and $_.execution_truth_hook_ready }).Count
$liveTruthReadyCount = @($resultsArray | Where-Object { $_.live_truth_data_ready }).Count
$localModelReadyCount = @($resultsArray | Where-Object { $_.local_model_available }).Count
$rollbackBlockedCount = @($resultsArray | Where-Object { -not $_.rollback_guard_allowed }).Count

$universeAligned = (($contractSymbols | Sort-Object) -join "|") -eq (($planFirstWave | Sort-Object) -join "|")

$globalBlockers = New-Object System.Collections.Generic.List[string]
if (-not $universeAligned) { $globalBlockers.Add("NIEZGODNY_KONTRAKT_CZWORKI") | Out-Null }
if (-not $migrationConfirmed) { $globalBlockers.Add("BRAK_POTWIERDZONEJ_MIGRACJI_SERWERA") | Out-Null }
if (-not $paperLiveSyncOk) { $globalBlockers.Add("BRAK_PELNEJ_SYNCHRONIZACJI_PAPER_LIVE") | Out-Null }
if (-not $serverPingReady) { $globalBlockers.Add("BRAK_KONTRAKTU_CZASU_ODPOWIEDZI_SERWERA") | Out-Null }
if (-not $serverLatencyReady) { $globalBlockers.Add("BRAK_PELNEGO_OPUZNIENIA_SERWERA_W_MODELU") | Out-Null }
if (-not $runtimeProfileMatch) { $globalBlockers.Add("NIEZGODNY_PROFIL_WYKONAWCZY") | Out-Null }
if (-not $capitalIsolationReady) { $globalBlockers.Add("BRAK_IZOLACJI_KAPITALU_DLA_CZWORKI") | Out-Null }
if (-not $activePresetCoverageReady) { $globalBlockers.Add("BRAK_PELNEGO_POKRYCIA_AKTYWNYCH_WYKRESOW") | Out-Null }
if (-not $liveTruthDataReady) { $globalBlockers.Add("BRAK_ZYWEGO_LANCUCHA_PRAWDA_PRZED_I_PO_WYKONANIU") | Out-Null }

$verdict = if (
    $nearServerCount -eq $contractSymbols.Count -and
    $migrationConfirmed -and
    $paperLiveSyncOk -and
    $serverPingReady -and
    $serverLatencyReady -and
    $runtimeProfileMatch -and
    $capitalIsolationReady -and
    $activePresetCoverageReady -and
    $liveTruthDataReady
) {
    "PIERWSZA_FALA_PRAWIE_SERWEROWA"
}
elseif (
    $partialCount + $nearServerCount -eq $contractSymbols.Count -and
    $truthHookReadyCount -eq $contractSymbols.Count -and
    $serverPingReady -and
    $serverLatencyReady
) {
    "PIERWSZA_FALA_PARITY_CZESCIOWE"
}
else {
    "PIERWSZA_FALA_PARITY_ZABLOKOWANE"
}

$report = [pscustomobject]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    universe_version = [string]$plan.universe_version
    broker_runtime = [string](Get-SafeObjectValue -Object $contract -PropertyName "broker_runtime" -Default "")
    symbol_scope = [string](Get-SafeObjectValue -Object $contract -PropertyName "symbol_scope" -Default "paper_live_first_wave")
    verdict = $verdict
    dlatego_ze = $(switch ($verdict) {
        "PIERWSZA_FALA_PRAWIE_SERWEROWA" { "Czworka ma lustro brokera, zywy lancuch prawdy wykonania, zgodny profil wykonawczy i nie jest juz zanieczyszczona blokada calej floty." }
        "PIERWSZA_FALA_PARITY_CZESCIOWE" { "Czworka ma juz silne lustro brokera i gotowe haki prawdy wykonania, ale nadal brakuje zywego zapisu wykonania albo pelnej zgodnosci profilu serwerowego." }
        default { "Czworka nadal nie ma wszystkich warunkow potrzebnych do uczenia i oceny prawie takiej jak na serwerze." }
    })
    recommendation = $(switch ($verdict) {
        "PIERWSZA_FALA_PRAWIE_SERWEROWA" { "Utrzymac biezaca zgodnosc i przejsc do scislejszego strojenia lokalnych modeli oraz walidacji wykonania." }
        "PIERWSZA_FALA_PARITY_CZESCIOWE" { "Najpierw ozywic zywy zapis prawdy wykonania, a potem odseparowac kapital i przejsc na docelowy profil wykonawczy czworki." }
        default { "Najpierw domknac zywa prawde wykonania, profil wykonawczy i izolacje kapitalu, a dopiero potem promowac lokalne modele." }
    })
    summary = [pscustomobject]@{
        target_symbol_count = $contractSymbols.Count
        universe_aligned = $universeAligned
        near_server_count = $nearServerCount
        partial_count = $partialCount
        blocked_count = $blockedCount
        truth_hook_ready_count = $truthHookReadyCount
        live_truth_ready_count = $liveTruthReadyCount
        local_model_ready_count = $localModelReadyCount
        rollback_blocked_count = $rollbackBlockedCount
        migration_confirmed = $migrationConfirmed
        paper_live_sync_ok = $paperLiveSyncOk
        server_execution_ping_contract_enabled = $serverPingReady
        server_latency_ready = $serverLatencyReady
        runtime_profile_observed = $runtimeProfile
        runtime_profile_target = $targetRuntimeProfile
        runtime_profile_match = $runtimeProfileMatch
        capital_isolation_ready = $capitalIsolationReady
        active_preset_coverage_ready = $activePresetCoverageReady
        truth_chain_live_ready = $liveTruthDataReady
    }
    global_blockers = @($globalBlockers)
    results = $resultsArray
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Audyt Zgodnosci Serwerowej Pierwszej Fali")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- dlatego_ze: {0}" -f $report.dlatego_ze))
$lines.Add(("- recommendation: {0}" -f $report.recommendation))
$lines.Add(("- near_server_count: {0}" -f $report.summary.near_server_count))
$lines.Add(("- partial_count: {0}" -f $report.summary.partial_count))
$lines.Add(("- blocked_count: {0}" -f $report.summary.blocked_count))
$lines.Add(("- truth_hook_ready_count: {0}" -f $report.summary.truth_hook_ready_count))
$lines.Add(("- live_truth_ready_count: {0}" -f $report.summary.live_truth_ready_count))
$lines.Add(("- migration_confirmed: {0}" -f ([string]$report.summary.migration_confirmed).ToLowerInvariant()))
$lines.Add(("- paper_live_sync_ok: {0}" -f ([string]$report.summary.paper_live_sync_ok).ToLowerInvariant()))
$lines.Add(("- runtime_profile_observed: {0}" -f $report.summary.runtime_profile_observed))
$lines.Add(("- runtime_profile_target: {0}" -f $report.summary.runtime_profile_target))
$lines.Add(("- runtime_profile_match: {0}" -f ([string]$report.summary.runtime_profile_match).ToLowerInvariant()))
$lines.Add(("- capital_isolation_ready: {0}" -f ([string]$report.summary.capital_isolation_ready).ToLowerInvariant()))
$lines.Add("")
$lines.Add("## Blokery globalne")
$lines.Add("")
if (@($report.global_blockers).Count -eq 0) {
    $lines.Add("- brak")
}
else {
    foreach ($blocker in @($report.global_blockers)) {
        $lines.Add(("- {0}" -f $blocker))
    }
}
$lines.Add("")
$lines.Add("## Symbole")
$lines.Add("")
foreach ($entry in @($resultsArray)) {
    $lines.Add(("### {0}" -f $entry.symbol_alias))
    $lines.Add(("- parity_state: {0}" -f $entry.parity_state))
    $lines.Add(("- broker_symbol_match: {0}" -f ([string]$entry.broker_symbol_match).ToLowerInvariant()))
    $lines.Add(("- custom_symbol_match: {0}" -f ([string]$entry.custom_symbol_match).ToLowerInvariant()))
    $lines.Add(("- broker_mirror_ready: {0}" -f ([string]$entry.broker_mirror_ready).ToLowerInvariant()))
    $lines.Add(("- smoke_ready: {0}" -f ([string]$entry.smoke_ready).ToLowerInvariant()))
    $lines.Add(("- learning_ready: {0}" -f ([string]$entry.learning_ready).ToLowerInvariant()))
    $lines.Add(("- learning_observation_rows: {0}" -f $entry.learning_observation_rows))
    $lines.Add(("- pretrade_truth_hook_ready: {0}" -f ([string]$entry.pretrade_truth_hook_ready).ToLowerInvariant()))
    $lines.Add(("- execution_truth_hook_ready: {0}" -f ([string]$entry.execution_truth_hook_ready).ToLowerInvariant()))
    $lines.Add(("- live_truth_data_ready: {0}" -f ([string]$entry.live_truth_data_ready).ToLowerInvariant()))
    $lines.Add(("- runtime_contract_present: {0}" -f ([string]$entry.runtime_contract_present).ToLowerInvariant()))
    $lines.Add(("- local_model_available: {0}" -f ([string]$entry.local_model_available).ToLowerInvariant()))
    $lines.Add(("- rollback_guard_allowed: {0}" -f ([string]$entry.rollback_guard_allowed).ToLowerInvariant()))
    $lines.Add(("- teacher_dependency_level: {0}" -f $entry.teacher_dependency_level))
    if (@($entry.blockers).Count -gt 0) {
        $lines.Add(("- blockers: {0}" -f (@($entry.blockers) -join ", ")))
    }
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
