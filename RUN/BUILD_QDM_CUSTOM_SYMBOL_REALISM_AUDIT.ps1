param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json",
    [string]$FirstWaveStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_first_wave_latest.json",
    [string]$PilotRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_registry_latest.json",
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

function Test-NonEmpty {
    param([object]$Value)

    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-FirstNonEmptyValue {
    param([object[]]$Candidates)

    foreach ($candidate in @($Candidates)) {
        if (Test-NonEmpty -Value $candidate) {
            return [string]$candidate
        }
    }

    return $null
}

function Get-PlanFirstWave {
    param([string]$Path)

    $plan = Read-JsonFile -Path $Path
    if ($null -eq $plan) {
        throw "Universe plan missing: $Path"
    }

    $symbols = @($plan.paper_live_first_wave | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($symbols.Count -le 0) {
        throw "Universe plan has no paper_live_first_wave symbols."
    }

    return [pscustomobject]@{
        universe_version = [string]$plan.universe_version
        symbols = $symbols
    }
}

function Get-RegistryMap {
    param([object]$Registry)

    $map = @{}
    if ($null -eq $Registry) {
        return $map
    }

    foreach ($entry in @($Registry.entries)) {
        $alias = ([string](Get-SafeObjectValue -Object $entry -PropertyName "symbol_alias" -Default "")).ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($alias)) {
            continue
        }
        $map[$alias] = $entry
    }

    return $map
}

function Get-FirstWaveMap {
    param([object]$FirstWaveStatus)

    $map = @{}
    if ($null -eq $FirstWaveStatus) {
        return $map
    }

    foreach ($entry in @($FirstWaveStatus.results)) {
        $alias = ([string](Get-SafeObjectValue -Object $entry -PropertyName "symbol_alias" -Default "")).ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($alias)) {
            continue
        }
        $map[$alias] = $entry
    }

    return $map
}

$jsonPath = Join-Path $OutputRoot "qdm_custom_symbol_realism_audit_latest.json"
$mdPath = Join-Path $OutputRoot "qdm_custom_symbol_realism_audit_latest.md"
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$plan = Get-PlanFirstWave -Path $UniversePlanPath
$firstWaveStatus = Read-JsonFile -Path $FirstWaveStatusPath
$pilotRegistry = Read-JsonFile -Path $PilotRegistryPath
$registryMap = Get-RegistryMap -Registry $pilotRegistry
$firstWaveMap = Get-FirstWaveMap -FirstWaveStatus $firstWaveStatus

$results = New-Object System.Collections.Generic.List[object]

foreach ($symbolAlias in @($plan.symbols)) {
    $registryEntry = if ($registryMap.ContainsKey($symbolAlias)) { $registryMap[$symbolAlias] } else { $null }
    $firstWaveEntry = if ($firstWaveMap.ContainsKey($symbolAlias)) { $firstWaveMap[$symbolAlias] } else { $null }
    $runResult = Get-SafeObjectValue -Object $firstWaveEntry -PropertyName "result" -Default $null
    $smoke = Get-SafeObjectValue -Object $runResult -PropertyName "smoke" -Default $null

    $customSymbol = [string](Get-SafeObjectValue -Object $runResult -PropertyName "custom_symbol" -Default (Get-SafeObjectValue -Object $registryEntry -PropertyName "custom_symbol" -Default $null))
    $brokerTemplateSymbol = [string](Get-SafeObjectValue -Object $firstWaveEntry -PropertyName "broker_template_symbol" -Default (Get-SafeObjectValue -Object $runResult -PropertyName "broker_template_symbol" -Default $null))
    $importMessage = Get-FirstNonEmptyValue -Candidates @(
        (Get-SafeObjectValue -Object $smoke -PropertyName "import_message" -Default $null),
        (Get-SafeObjectValue -Object $registryEntry -PropertyName "import_message" -Default $null)
    )
    $propertyMirrorMessage = Get-FirstNonEmptyValue -Candidates @(
        (Get-SafeObjectValue -Object $smoke -PropertyName "property_mirror_message" -Default $null),
        (Get-SafeObjectValue -Object $registryEntry -PropertyName "property_mirror_message" -Default $null)
    )
    $sessionMirrorMessage = Get-FirstNonEmptyValue -Candidates @(
        (Get-SafeObjectValue -Object $smoke -PropertyName "session_mirror_message" -Default $null),
        (Get-SafeObjectValue -Object $registryEntry -PropertyName "session_mirror_message" -Default $null)
    )
    $resultLabel = [string](Get-SafeObjectValue -Object $smoke -PropertyName "result_label" -Default (Get-SafeObjectValue -Object $registryEntry -PropertyName "result_label" -Default $null))
    $learningObservationRows = [int](Get-SafeObjectValue -Object $smoke -PropertyName "learning_observation_rows" -Default 0)
    $paperLearningState = [string](Get-SafeObjectValue -Object $smoke -PropertyName "paper_learning_state" -Default $null)
    $modelNormalized = [bool](Get-SafeObjectValue -Object $smoke -PropertyName "model_normalized_for_qdm_custom_symbol" -Default (Get-SafeObjectValue -Object $registryEntry -PropertyName "model_normalized_for_qdm_custom_symbol" -Default $false))
    $registrySource = [string](Get-SafeObjectValue -Object $registryEntry -PropertyName "source" -Default "")

    $smokeReady = ($resultLabel -eq "successfully_finished")
    $importReady = (Test-NonEmpty -Value $importMessage) -or ((Test-NonEmpty -Value $customSymbol) -and $smokeReady)
    $propertyMirrorReady = Test-NonEmpty -Value $propertyMirrorMessage
    $sessionMirrorReady = Test-NonEmpty -Value $sessionMirrorMessage
    $learningReady = ($learningObservationRows -gt 0 -or $paperLearningState -eq "READY")
    $brokerMirrorReady = ($importReady -and $propertyMirrorReady -and $sessionMirrorReady)
    $realismReady = ($brokerMirrorReady -and $smokeReady -and $learningReady -and $modelNormalized)

    $blockers = New-Object System.Collections.Generic.List[string]
    if (-not $importReady) { $blockers.Add("IMPORT_MESSAGE_MISSING") | Out-Null }
    if (-not $propertyMirrorReady) { $blockers.Add("PROPERTY_MIRROR_MISSING") | Out-Null }
    if (-not $sessionMirrorReady) { $blockers.Add("SESSION_MIRROR_MISSING") | Out-Null }
    if (-not $smokeReady) { $blockers.Add("SMOKE_NOT_SUCCESSFUL") | Out-Null }
    if (-not $learningReady) { $blockers.Add("LEARNING_NOT_READY") | Out-Null }
    if (-not $modelNormalized) { $blockers.Add("MODEL_NOT_NORMALIZED_FOR_QDM") | Out-Null }

    $results.Add([pscustomobject]@{
        symbol_alias = $symbolAlias
        custom_symbol = $customSymbol
        broker_template_symbol = $brokerTemplateSymbol
        registry_source = if ([string]::IsNullOrWhiteSpace($registrySource)) { "unknown" } else { $registrySource }
        import_ready = $importReady
        property_mirror_ready = $propertyMirrorReady
        session_mirror_ready = $sessionMirrorReady
        broker_mirror_ready = $brokerMirrorReady
        smoke_ready = $smokeReady
        learning_ready = $learningReady
        model_normalized_for_qdm = $modelNormalized
        realism_ready = $realismReady
        result_label = $resultLabel
        paper_learning_state = $paperLearningState
        learning_observation_rows = $learningObservationRows
        import_message = $(if (Test-NonEmpty -Value $importMessage) { $importMessage } elseif ($importReady) { "INFERRED_FROM_CUSTOM_SYMBOL_AND_SUCCESSFUL_SMOKE" } else { $null })
        property_mirror_message = $(if ($propertyMirrorReady) { $propertyMirrorMessage } else { $null })
        session_mirror_message = $(if ($sessionMirrorReady) { $sessionMirrorMessage } else { $null })
        blockers = @($blockers)
    }) | Out-Null
}

$resultsArray = $results.ToArray()
$selectedCount = $resultsArray.Count
$realismReadyCount = @($resultsArray | Where-Object { $_.realism_ready }).Count
$brokerMirrorReadyCount = @($resultsArray | Where-Object { $_.broker_mirror_ready }).Count
$propertyMirrorReadyCount = @($resultsArray | Where-Object { $_.property_mirror_ready }).Count
$sessionMirrorReadyCount = @($resultsArray | Where-Object { $_.session_mirror_ready }).Count
$learningReadyCount = @($resultsArray | Where-Object { $_.learning_ready }).Count
$smokeReadyCount = @($resultsArray | Where-Object { $_.smoke_ready }).Count
$currentRunCount = @($resultsArray | Where-Object { $_.registry_source -eq "current_run" }).Count
$backfilledCount = @($resultsArray | Where-Object { $_.registry_source -ne "current_run" }).Count
$partialCount = @($resultsArray | Where-Object { -not $_.realism_ready -and ($_.smoke_ready -or $_.learning_ready -or $_.broker_mirror_ready) }).Count

$verdict = if ($realismReadyCount -eq $selectedCount -and $currentRunCount -eq $selectedCount) {
    "QDM_BROKER_MIRROR_READY"
}
elseif ($realismReadyCount -eq $selectedCount) {
    "QDM_BROKER_MIRROR_READY_WITH_BACKFILL"
}
elseif ($smokeReadyCount -eq $selectedCount -and $learningReadyCount -eq $selectedCount) {
    "QDM_BROKER_MIRROR_PARTIAL"
}
else {
    "QDM_BROKER_MIRROR_BLOCKED"
}

$report = [pscustomobject]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    universe_version = $plan.universe_version
    symbol_scope = "paper_live_first_wave"
    verdict = $verdict
    summary = [pscustomobject]@{
        selected_count = $selectedCount
        realism_ready_count = $realismReadyCount
        broker_mirror_ready_count = $brokerMirrorReadyCount
        property_mirror_ready_count = $propertyMirrorReadyCount
        session_mirror_ready_count = $sessionMirrorReadyCount
        smoke_ready_count = $smokeReadyCount
        learning_ready_count = $learningReadyCount
        current_run_count = $currentRunCount
        backfilled_count = $backfilledCount
        partial_count = $partialCount
    }
    results = $resultsArray
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# QDM Custom Symbol Realism Audit")
$lines.Add("")
$lines.Add(("- generated_at_utc: {0}" -f $report.generated_at_utc))
$lines.Add(("- universe_version: {0}" -f $report.universe_version))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- selected_count: {0}" -f $report.summary.selected_count))
$lines.Add(("- realism_ready_count: {0}" -f $report.summary.realism_ready_count))
$lines.Add(("- broker_mirror_ready_count: {0}" -f $report.summary.broker_mirror_ready_count))
$lines.Add(("- property_mirror_ready_count: {0}" -f $report.summary.property_mirror_ready_count))
$lines.Add(("- session_mirror_ready_count: {0}" -f $report.summary.session_mirror_ready_count))
$lines.Add(("- smoke_ready_count: {0}" -f $report.summary.smoke_ready_count))
$lines.Add(("- learning_ready_count: {0}" -f $report.summary.learning_ready_count))
$lines.Add(("- current_run_count: {0}" -f $report.summary.current_run_count))
$lines.Add(("- backfilled_count: {0}" -f $report.summary.backfilled_count))
$lines.Add("")
$lines.Add("## Symbols")
$lines.Add("")
foreach ($entry in $resultsArray) {
    $lines.Add(("### {0}" -f $entry.symbol_alias))
    $lines.Add(("- custom_symbol: {0}" -f $entry.custom_symbol))
    $lines.Add(("- broker_template_symbol: {0}" -f $entry.broker_template_symbol))
    $lines.Add(("- registry_source: {0}" -f $entry.registry_source))
    $lines.Add(("- realism_ready: {0}" -f $entry.realism_ready))
    $lines.Add(("- broker_mirror_ready: {0}" -f $entry.broker_mirror_ready))
    $lines.Add(("- smoke_ready: {0}" -f $entry.smoke_ready))
    $lines.Add(("- learning_ready: {0}" -f $entry.learning_ready))
    $lines.Add(("- model_normalized_for_qdm: {0}" -f $entry.model_normalized_for_qdm))
    $lines.Add(("- result_label: {0}" -f $entry.result_label))
    $lines.Add(("- paper_learning_state: {0}" -f $entry.paper_learning_state))
    $lines.Add(("- learning_observation_rows: {0}" -f $entry.learning_observation_rows))
    if ($entry.import_ready) {
        $lines.Add(("- import_message: {0}" -f $entry.import_message))
    }
    if ($entry.property_mirror_ready) {
        $lines.Add(("- property_mirror_message: {0}" -f $entry.property_mirror_message))
    }
    if ($entry.session_mirror_ready) {
        $lines.Add(("- session_mirror_message: {0}" -f $entry.session_mirror_message))
    }
    if (@($entry.blockers).Count -gt 0) {
        $lines.Add(("- blockers: {0}" -f (@($entry.blockers) -join ", ")))
    }
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
