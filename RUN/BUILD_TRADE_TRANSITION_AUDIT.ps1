param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
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

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
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
            $map[$parts[0]] = $parts[1]
        }
    }

    return $map
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$activePresetRoot = Join-Path $ProjectRoot "SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive"
$migrationReportPath = Join-Path $ProjectRoot "EVIDENCE\migrate_oanda_mt5_vps_clean_latest.json"
$paperLiveSyncPath = Join-Path $opsRoot "paper_live_sync_latest.json"
$localProfileReportPath = Join-Path $ProjectRoot "EVIDENCE\mt5_microbots_profile_setup_report.json"
$vpsProfileReportPath = Join-Path $opsRoot "mt5_microbots_profile_setup_for_vps_latest.json"
$paperGapPath = Join-Path $opsRoot "paper_live_action_gap_audit_latest.json"
$trainerScriptPath = Join-Path $ProjectRoot "TOOLS\mb_ml_core\trainer.py"
$featureContractPath = Join-Path $ProjectRoot "TOOLS\mb_ml_core\features.py"
$executionPingContractPath = Join-Path $CommonRoot "state\_global\execution_ping_contract.csv"
$jsonPath = Join-Path $OutputRoot "trade_transition_audit_latest.json"
$mdPath = Join-Path $OutputRoot "trade_transition_audit_latest.md"

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$registry = Read-JsonSafe -Path $registryPath
if ($null -eq $registry) {
    throw "Brakuje rejestru mikrobotow: $registryPath"
}

$migrationReport = Read-JsonSafe -Path $migrationReportPath
$paperLiveSyncReport = Read-JsonSafe -Path $paperLiveSyncPath
$localProfileReport = Read-JsonSafe -Path $localProfileReportPath
$vpsProfileReport = Read-JsonSafe -Path $vpsProfileReportPath
$paperGap = Read-JsonSafe -Path $paperGapPath
$pingContract = Read-KeyValueTable -Path $executionPingContractPath
$trainerText = if (Test-Path -LiteralPath $trainerScriptPath) { Get-Content -LiteralPath $trainerScriptPath -Raw -Encoding UTF8 } else { "" }
$featureContractText = if (Test-Path -LiteralPath $featureContractPath) { Get-Content -LiteralPath $featureContractPath -Raw -Encoding UTF8 } else { "" }

$registrySymbols = @($registry.symbols)
$expectedActivePresets = foreach ($row in $registrySymbols) {
    "{0}_ACTIVE.set" -f ([System.IO.Path]::GetFileNameWithoutExtension([string]$row.preset))
}
$packageActivePresetFiles = if (Test-Path -LiteralPath $activePresetRoot) {
    @(Get-ChildItem -LiteralPath $activePresetRoot -File -Filter "*.set" | Select-Object -ExpandProperty Name)
}
else {
    @()
}
$missingActivePresets = @($expectedActivePresets | Where-Object { $packageActivePresetFiles -notcontains $_ })

$profileForDiagnosis = if ($null -ne $vpsProfileReport) { $vpsProfileReport } else { $localProfileReport }
$profileCharts = @((Get-OptionalValue -Object $profileForDiagnosis -Name "charts" -Default @()))
$activeCharts = @(
    $profileCharts | Where-Object {
        $presetMode = [string](Get-OptionalValue -Object $_ -Name "preset_mode" -Default "")
        $presetName = [string](Get-OptionalValue -Object $_ -Name "preset" -Default "")
        $resolvedPresetPath = [string](Get-OptionalValue -Object $_ -Name "resolved_preset_path" -Default "")
        $presetMode -eq "active_live" -or $presetName -like "*_ACTIVE.set" -or $resolvedPresetPath -match '\\ActiveLive\\'
    }
)
$safeCharts = @($profileCharts | Where-Object { $activeCharts -notcontains $_ })

$hasDedicatedVpsProfileReport = ($null -ne $vpsProfileReport)
$migrationOk = [bool](Get-OptionalValue -Object $migrationReport -Name "ok" -Default $false)
$migrationStage = [string](Get-OptionalValue -Object $migrationReport -Name "stage" -Default "")
$paperLiveSyncOk = [bool](Get-OptionalValue -Object $paperLiveSyncReport -Name "ok" -Default $false)
$paperLiveSyncStatus = [string](Get-OptionalValue -Object $paperLiveSyncReport -Name "status" -Default "")
$paperLiveSyncStatusNormalized = $paperLiveSyncStatus.Trim()
$migrationConfirmed = ($migrationOk -or $paperLiveSyncOk)
$serverPingEnabled = ([string](Get-OptionalValue -Object $pingContract -Name "enabled" -Default "0") -eq "1")
$serverPingSource = [string](Get-OptionalValue -Object $pingContract -Name "source" -Default "")
$trainerUsesRuntimeLatency = (($trainerText -match 'runtime_latency_us') -or ($featureContractText -match 'runtime_latency_us'))
$trainerUsesServerPing = (($trainerText -match 'server_operational_ping_ms' -or $trainerText -match 'execution_ping_contract') -or ($featureContractText -match 'server_operational_ping_ms'))
$trainerUsesServerLatency = (($trainerText -match 'server_local_latency_us_avg' -or $trainerText -match 'server_local_latency_us_max') -or ($featureContractText -match 'server_local_latency_us_avg') -or ($featureContractText -match 'server_local_latency_us_max'))

$paperSummary = Get-OptionalValue -Object $paperGap -Name "summary" -Default $null
$activeTradeCount = [int](Get-OptionalValue -Object $paperSummary -Name "active_trade_count" -Default 0)
$runtimeProfile = [string](Get-OptionalValue -Object $paperSummary -Name "runtime_profile" -Default "")
$capitalThresholdProfile = [string](Get-OptionalValue -Object $paperSummary -Name "capital_threshold_profile" -Default "")
$paperThresholdProfileMatch = [bool](Get-OptionalValue -Object $paperSummary -Name "paper_threshold_profile_match" -Default $false)
$fleetCapitalLockActive = [bool](Get-OptionalValue -Object $paperSummary -Name "fleet_capital_lock_active" -Default $false)
$fleetCapitalLockReason = [string](Get-OptionalValue -Object $paperSummary -Name "fleet_capital_lock_reason" -Default "")
$fleetCapitalDefensiveActive = [bool](Get-OptionalValue -Object $paperSummary -Name "fleet_capital_defensive_active" -Default $false)
$fleetCapitalDefensiveReason = [string](Get-OptionalValue -Object $paperSummary -Name "fleet_capital_defensive_reason" -Default "")
$fleetDailyLossPct = [double](Get-OptionalValue -Object $paperSummary -Name "fleet_daily_loss_pct" -Default 0.0)
$paperHardDailyLossPct = [double](Get-OptionalValue -Object $paperSummary -Name "paper_hard_daily_loss_pct" -Default 0.0)
$fleetCapitalLockSymbolCount = [int](Get-OptionalValue -Object $paperSummary -Name "fleet_capital_lock_symbol_count" -Default 0)
$familyCapitalLockSymbolCount = [int](Get-OptionalValue -Object $paperSummary -Name "family_capital_lock_symbol_count" -Default 0)
$fleetDefensiveCount = [int](Get-OptionalValue -Object $paperSummary -Name "fleet_defensive_count" -Default 0)
$familyDefensiveCount = [int](Get-OptionalValue -Object $paperSummary -Name "family_defensive_count" -Default 0)
$fleetFreezeCount = [int](Get-OptionalValue -Object $paperSummary -Name "fleet_freeze_count" -Default 0)
$familyFreezeCount = [int](Get-OptionalValue -Object $paperSummary -Name "family_freeze_count" -Default 0)
$costBlockCount = [int](Get-OptionalValue -Object $paperSummary -Name "cost_block_count" -Default 0)
$lowSampleCount = [int](Get-OptionalValue -Object $paperSummary -Name "low_sample_count" -Default 0)
$foregroundDirtyCount = [int](Get-OptionalValue -Object $paperSummary -Name "foreground_dirty_count" -Default 0)

$verdict = "PRZEJSCIE_OBSERWACJA_HANDEL_WYMAGA_UWAGI"
$dlategoZe = "Przynajmniej jedna warstwa miedzy obserwacja, uczeniem i dzialaniem handlowym nadal nie jest domknieta."
$recommendation = "Utrzymac audyt i naprawiac po kolei warstwe wdrozenia oraz warstwe blokad decyzyjnych."

if ($missingActivePresets.Count -gt 0) {
    $verdict = "BLOKADA_WDROZENIOWA_PRESETOW"
    $dlategoZe = "Pakiet serwerowy nie ma kompletu aktywnych presetow z wlaczonym wejsciem handlowym."
    $recommendation = "Uzupelnic aktywne presety przed kolejna migracja i nie synchronizowac bez nich serwera."
}
elseif (-not $hasDedicatedVpsProfileReport) {
    $verdict = "BRAK_DOWODU_PROFILU_VPS"
    $dlategoZe = "Nie ma jeszcze swiezego raportu potwierdzajacego, ze profil migracyjny dla serwera byl zbudowany z aktywnych presetow."
    $recommendation = "Przy kolejnej migracji zapisac i utrzymac osobny raport profilu serwerowego."
}
elseif ($profileCharts.Count -gt 0 -and $activeCharts.Count -lt $profileCharts.Count) {
    $verdict = "PROFIL_VPS_ZBUDOWANY_Z_BEZPIECZNYCH_PRESETOW"
    $dlategoZe = "Profil uzyty dla serwera zawiera co najmniej jeden bezpieczny preset, ktory nie pozwala przejsc z obserwacji do handlu."
    $recommendation = "Budowac profil migracyjny tylko z presetow ActiveLive i walidowac to przed synchronizacja VPS."
}
elseif (-not $migrationConfirmed) {
    $verdict = "MIGRACJA_SERWERA_NIEPOTWIERDZONA"
    $dlategoZe = "Nie ma jeszcze swiezego, zgodnego dowodu udanej migracji serwera na aktywnych presetach."
    $recommendation = "Naprawic automatyke migracji albo zapis swiezego raportu synchronizacji zanim beda analizowane blokady decyzyjne."
}
elseif (-not $paperThresholdProfileMatch) {
    $verdict = "NIEZGODNY_PROFIL_PROGOW_PAPER"
    $dlategoZe = ("Koordynator sesyjny dla profilu '{0}' nie pracuje na papierowych progach ryzyka, wiec decyzje blokad i trybu obronnego sa niewiarygodne." -f $runtimeProfile)
    $recommendation = "Przelaczyc koordynator na papierowy kontrakt progow, odswiezyc runtime i dopiero potem oceniac blokady decyzyjne."
}
elseif ($fleetCapitalLockActive) {
    $verdict = "AKTYWNA_BLOKADA_KAPITALU_FLOTY"
    $dlategoZe = ("Koordynator kapitalu trzyma cala flote w trybie papierowym, bo dzienna strata paper wynosi {0:N2}% przy twardym limicie {1:N2}%." -f $fleetDailyLossPct, $paperHardDailyLossPct)
    $recommendation = "Nie odmrazac recznie. Najpierw naprawiac przyczyny strat, bo to jest glowna blokada przejscia z obserwacji do handlu."
}
elseif ($fleetCapitalDefensiveActive) {
    $verdict = "PAPER_DEFENSYWNY_ALE_AKTYWNY"
    $dlategoZe = ("Koordynator kapitalu nie zamrozil juz floty papierowej, ale przelaczyl ja w tryb obronny po stracie {0:N2}%; ryzyko jest przyciete, a wejscia maja byc selektywne." -f $fleetDailyLossPct)
    $recommendation = "Utrzymac tryb obronny i rozbijac przyczyne strat instrument po instrumencie zamiast wracac do twardego freeze."
}
elseif ($activeTradeCount -le 0 -and ($fleetFreezeCount + $familyFreezeCount + $costBlockCount + $lowSampleCount + $foregroundDirtyCount) -gt 0) {
    $verdict = "BLOKADY_DECYZYJNE_DOMINUJA"
    $dlategoZe = "Sciezka wdrozenia wyglada poprawnie, ale instrumenty sa zatrzymywane glownie przez koszt, zamrozenia flotowe albo zbyt mala probe."
    $recommendation = "Korygowac agentow strojenia i warunki wejscia, nie sama migracje."
}
elseif ($activeTradeCount -gt 0) {
    $verdict = "SCIEZKA_HANDLU_DZIALA_ALE_JEST_SELEKTYWNA"
    $dlategoZe = "Czesc instrumentow przechodzi juz do dzialania handlowego, ale pozostale nadal zatrzymuja blokady decyzyjne."
    $recommendation = "Naprawiac blokady decyzyjne instrument po instrumencie bez ruszania dzialajacej sciezki serwerowej."
}

$summary = [ordered]@{
    registry_symbols_count = @($registrySymbols).Count
    package_active_preset_count = @($packageActivePresetFiles).Count
    missing_active_preset_count = @($missingActivePresets).Count
    dedicated_vps_profile_report_present = $hasDedicatedVpsProfileReport
    profile_chart_count = @($profileCharts).Count
    profile_active_chart_count = @($activeCharts).Count
    profile_safe_chart_count = @($safeCharts).Count
    migration_ok = $migrationOk
    migration_stage = $migrationStage
    paper_live_sync_ok = $paperLiveSyncOk
    paper_live_sync_status = $paperLiveSyncStatus
    migration_confirmed = $migrationConfirmed
    server_execution_ping_contract_enabled = $serverPingEnabled
    server_execution_ping_contract_source = $serverPingSource
    global_model_uses_runtime_latency = $trainerUsesRuntimeLatency
    global_model_uses_server_ping = $trainerUsesServerPing
    global_model_uses_server_latency = $trainerUsesServerLatency
    paper_active_trade_count = $activeTradeCount
    paper_runtime_profile = $runtimeProfile
    paper_capital_threshold_profile = $capitalThresholdProfile
    paper_threshold_profile_match = $paperThresholdProfileMatch
    paper_fleet_capital_lock_active = $fleetCapitalLockActive
    paper_fleet_capital_lock_reason = $fleetCapitalLockReason
    paper_fleet_capital_defensive_active = $fleetCapitalDefensiveActive
    paper_fleet_capital_defensive_reason = $fleetCapitalDefensiveReason
    paper_fleet_daily_loss_pct = $fleetDailyLossPct
    paper_hard_daily_loss_pct = $paperHardDailyLossPct
    paper_fleet_capital_lock_symbol_count = $fleetCapitalLockSymbolCount
    paper_family_capital_lock_symbol_count = $familyCapitalLockSymbolCount
    paper_fleet_defensive_count = $fleetDefensiveCount
    paper_family_defensive_count = $familyDefensiveCount
    paper_fleet_freeze_count = $fleetFreezeCount
    paper_family_freeze_count = $familyFreezeCount
    paper_cost_block_count = $costBlockCount
    paper_low_sample_count = $lowSampleCount
    paper_foreground_dirty_count = $foregroundDirtyCount
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    verdict = $verdict
    dlatego_ze = $dlategoZe
    recommendation = $recommendation
    summary = $summary
    missing_active_presets = @($missingActivePresets)
    profile_charts = @($profileCharts)
    top_paper_blocks = if ($null -ne $paperGap) { @($paperGap.items | Select-Object -First 8) } else { @() }
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Audyt Przejscia Obserwacja Handel")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- dlatego_ze: {0}" -f $report.dlatego_ze))
$lines.Add(("- recommendation: {0}" -f $report.recommendation))
$lines.Add(("- profile_active_chart_count: {0}" -f $summary.profile_active_chart_count))
$lines.Add(("- profile_safe_chart_count: {0}" -f $summary.profile_safe_chart_count))
$lines.Add(("- migration_ok: {0}" -f ([string]$summary.migration_ok).ToLowerInvariant()))
$lines.Add(("- paper_live_sync_ok: {0}" -f ([string]$summary.paper_live_sync_ok).ToLowerInvariant()))
$lines.Add(("- migration_confirmed: {0}" -f ([string]$summary.migration_confirmed).ToLowerInvariant()))
$lines.Add(("- server_execution_ping_contract_enabled: {0}" -f ([string]$summary.server_execution_ping_contract_enabled).ToLowerInvariant()))
$lines.Add(("- global_model_uses_runtime_latency: {0}" -f ([string]$summary.global_model_uses_runtime_latency).ToLowerInvariant()))
$lines.Add(("- global_model_uses_server_ping: {0}" -f ([string]$summary.global_model_uses_server_ping).ToLowerInvariant()))
$lines.Add(("- global_model_uses_server_latency: {0}" -f ([string]$summary.global_model_uses_server_latency).ToLowerInvariant()))
$lines.Add(("- paper_runtime_profile: {0}" -f $summary.paper_runtime_profile))
$lines.Add(("- paper_fleet_capital_lock_active: {0}" -f ([string]$summary.paper_fleet_capital_lock_active).ToLowerInvariant()))
$lines.Add(("- paper_fleet_capital_lock_reason: {0}" -f $summary.paper_fleet_capital_lock_reason))
$lines.Add(("- paper_fleet_capital_defensive_active: {0}" -f ([string]$summary.paper_fleet_capital_defensive_active).ToLowerInvariant()))
$lines.Add(("- paper_fleet_capital_defensive_reason: {0}" -f $summary.paper_fleet_capital_defensive_reason))
$lines.Add(("- paper_fleet_daily_loss_pct: {0}" -f $summary.paper_fleet_daily_loss_pct))
$lines.Add(("- paper_hard_daily_loss_pct: {0}" -f $summary.paper_hard_daily_loss_pct))
$lines.Add("")
$lines.Add("## Braki aktywnych presetow")
$lines.Add("")
if (@($missingActivePresets).Count -eq 0) {
    $lines.Add("- brak")
}
else {
    foreach ($item in $missingActivePresets) {
        $lines.Add(("- {0}" -f $item))
    }
}
$lines.Add("")
$lines.Add("## Najwazniejsze blokady paper-live")
$lines.Add("")
if (@($report.top_paper_blocks).Count -eq 0) {
    $lines.Add("- brak danych")
}
else {
    foreach ($item in $report.top_paper_blocks) {
        $lines.Add(("- {0}: direct_block={1}, why={2}, trust={3}, cost={4}" -f
            $item.symbol_alias,
            $item.direct_block,
            $item.deeper_why,
            $item.trust_state,
            $item.cost_pressure))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
