param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$FleetVerdictsPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\active_fleet_verdicts_latest.json",
    [string]$WinnerDeploymentPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\winner_deployment_latest.json",
    [string]$OnnxFeedbackPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_feedback_loop_latest.json",
    [string]$OnnxMicroReviewPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_micro_review_latest.json",
    [string]$OnnxSymbolRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string]$PaperLiveFeedbackPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.json",
    [string]$LearningStackAuditPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\learning_stack_audit_latest.json",
    [string]$LocalTrainingGuardrailsPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_local_training_guardrails_latest.json",
    [string]$QdmWeakestProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_weakest_profile_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
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

function Normalize-SymbolKey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return ($Value.Trim().ToUpperInvariant())
}

function New-MapByKeys {
    param(
        [object[]]$Items,
        [string[]]$CandidateKeys
    )

    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        foreach ($keyName in $CandidateKeys) {
            if (-not ($item.PSObject.Properties.Name -contains $keyName)) {
                continue
            }

            $key = Normalize-SymbolKey -Value ([string]$item.$keyName)
            if ([string]::IsNullOrWhiteSpace($key)) {
                continue
            }

            if (-not $map.ContainsKey($key)) {
                $map[$key] = $item
            }
        }
    }

    return $map
}

function Get-OptionalNumber {
    param(
        [object]$Object,
        [string]$Name,
        [double]$Default = 0.0
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    $value = $Object.$Name
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $Default
    }

    return [double]$value
}

function Get-OptionalString {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Default = ""
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    return [string]$Object.$Name
}

function Get-OptionalBool {
    param(
        [object]$Object,
        [string]$Name,
        [bool]$Default = $false
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    $value = $Object.$Name
    if ($null -eq $value) {
        return $Default
    }

    if ($value -is [bool]) {
        return [bool]$value
    }

    $text = ([string]$value).Trim().ToLowerInvariant()
    switch ($text) {
        "true" { return $true }
        "1" { return $true }
        "yes" { return $true }
        "tak" { return $true }
        "false" { return $false }
        "0" { return $false }
        "no" { return $false }
        "nie" { return $false }
        default { return $Default }
    }
}

function Get-SampleFreshnessState {
    param(
        [double]$RuntimeRows,
        [bool]$PaperFresh,
        [bool]$QdmReady,
        [double]$QdmRows,
        [double]$ModelRows
    )

    if ($RuntimeRows -gt 0 -and $PaperFresh) {
        return "SWIEZA_RUNTIME"
    }

    if ($QdmReady -and $QdmRows -gt 0) {
        return "SWIEZA_HISTORYCZNA"
    }

    if ($ModelRows -gt 0) {
        return "HISTORYCZNA"
    }

    return "UBOGA"
}

function Get-LearningHealthState {
    param(
        [string]$OnnxStatus,
        [string]$OnnxQuality,
        [string]$OnnxAudit,
        [double]$ModelRows,
        [double]$RuntimeRows,
        [double]$OutcomeRows,
        [double]$PrioritySampleCount,
        [string]$BusinessStatus,
        [string]$CostState,
        [string]$TrustState,
        [double]$TesterPnl,
        [double]$PaperNet
    )

    if ($OnnxStatus -eq "GLOBAL_FALLBACK") {
        return "FALLBACK_GLOBALNY"
    }

    if (($PrioritySampleCount -gt 0 -and $PrioritySampleCount -lt 40) -or ($ModelRows -gt 0 -and $ModelRows -lt 30000 -and $RuntimeRows -eq 0)) {
        return "MALA_PROBKA"
    }

    if ($OnnxQuality -eq "SLABY" -or $OnnxAudit -eq "DOSZKOLIC_MALY_MODEL") {
        return "WYMAGA_DOSZKOLENIA"
    }

    if (
        $BusinessStatus -eq "NEGATIVE" -and
        ($CostState -in @("NON_REPRESENTATIVE", "HIGH") -or $TrustState -in @("LOW_SAMPLE", "FOREFIELD_DIRTY", "PAPER_CONVERSION_BLOCKED"))
    ) {
        return "WYMAGA_REGENERACJI"
    }

    if ($OutcomeRows -ge 250 -and $OnnxQuality -in @("MOCNY", "DOBRY") -and ($TesterPnl -ge 0 -or $PaperNet -ge 0)) {
        return "GOTOWY_DO_MIEKKIEJ_BRAMKI"
    }

    if ($RuntimeRows -gt 0 -and $OnnxQuality -in @("MOCNY", "DOBRY", "OSTROZNIE")) {
        return "UCZY_SIE_ZDROWO"
    }

    if ($OnnxStatus -eq "MODEL_PER_SYMBOL_READY" -and $OnnxQuality -in @("MOCNY", "DOBRY", "OSTROZNIE")) {
        return "GOTOWY_DO_OBSERWACJI"
    }

    if ($TesterPnl -gt 0 -or $PaperNet -gt 0) {
        return "GOTOWY_DO_UCZENIA"
    }

    return "WYMAGA_REGENERACJI"
}

function Get-WorkMode {
    param(
        [string]$HealthState,
        [string]$BusinessStatus,
        [double]$PaperNet,
        [double]$RuntimeRows
    )

    switch ($HealthState) {
        "FALLBACK_GLOBALNY" { return "FALLBACK_DO_NAUCZYCIELA" }
        "MALA_PROBKA" { return "WYHAMUJ_I_ZBIERAJ_PROBKE" }
        "WYMAGA_DOSZKOLENIA" { return "REGENERUJ" }
        "WYMAGA_REGENERACJI" { return "REGENERUJ" }
        "GOTOWY_DO_OBSERWACJI" { return "OBSERWUJ" }
        "GOTOWY_DO_MIEKKIEJ_BRAMKI" { return "DOCISKAJ" }
        "UCZY_SIE_ZDROWO" {
            if ($BusinessStatus -in @("TESTER_POSITIVE", "LIVE_POSITIVE") -and ($PaperNet -ge 0 -or $RuntimeRows -gt 0)) {
                return "EKSPLOATUJ"
            }

            return "DOCISKAJ"
        }
        default {
            if ($BusinessStatus -eq "NEAR_PROFIT") {
                return "DOCISKAJ"
            }

            return "OBSERWUJ"
        }
    }
}

function Get-HealthPriority {
    param(
        [string]$HealthState,
        [string]$WorkMode
    )

    switch ($HealthState) {
        "FALLBACK_GLOBALNY" { return 0 }
        "WYMAGA_DOSZKOLENIA" { return 1 }
        "WYMAGA_REGENERACJI" { return 2 }
        "MALA_PROBKA" { return 3 }
        "GOTOWY_DO_MIEKKIEJ_BRAMKI" { return 4 }
        "GOTOWY_DO_OBSERWACJI" { return 5 }
        "UCZY_SIE_ZDROWO" { return 6 }
        "GOTOWY_DO_PAPER_LIVE" { return 7 }
        default {
            switch ($WorkMode) {
                "REGENERUJ" { return 2 }
                "DOCISKAJ" { return 4 }
                "OBSERWUJ" { return 5 }
                "EKSPLOATUJ" { return 6 }
                default { return 8 }
            }
        }
    }
}

function Get-HealthRecommendation {
    param(
        [string]$HealthState,
        [string]$OnnxQuality,
        [double]$RuntimeRows,
        [double]$OutcomeRows,
        [bool]$QdmCoverageVisible
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    switch ($HealthState) {
        "FALLBACK_GLOBALNY" { [void]$reasons.Add("utrzymac nauczyciela globalnego i budowac lokalna probke") }
        "MALA_PROBKA" { [void]$reasons.Add("zwiekszyc probe i nie przepalac testera na sile") }
        "WYMAGA_DOSZKOLENIA" { [void]$reasons.Add("doszkolic maly model i sprawdzic kontrakt cech") }
        "WYMAGA_REGENERACJI" { [void]$reasons.Add("naprawic dane lub koszt zanim pojdzie kolejny trening") }
        "GOTOWY_DO_OBSERWACJI" { [void]$reasons.Add("zbierac runtime ONNX zanim zapadna decyzje promocyjne") }
        "GOTOWY_DO_MIEKKIEJ_BRAMKI" { [void]$reasons.Add("mozna szykowac lagodna bramke, ale nadal bez agresji") }
        "UCZY_SIE_ZDROWO" { [void]$reasons.Add("utrzymac zdrowy cykl uczenia i pilnowac dryfu") }
        default { [void]$reasons.Add("utrzymac monitoring i regularna higienie") }
    }

    if ($RuntimeRows -gt 0 -and $OutcomeRows -eq 0) {
        [void]$reasons.Add("brakuje jeszcze domknietego wyniku rynku dla obserwacji ONNX")
    }
    if (-not $QdmCoverageVisible) {
        [void]$reasons.Add("QDM nie jest jeszcze widoczny w aktywnym pokryciu modelu")
    }
    if ($OnnxQuality -eq "MOCNY") {
        [void]$reasons.Add("jakosc modelu jest mocna, ograniczeniem jest glownie obieg danych")
    }
    elseif ($OnnxQuality -eq "SLABY") {
        [void]$reasons.Add("jakosc modelu jest slaba i wymaga przebudowy lub lepszej probki")
    }

    return (($reasons.ToArray()) -join "; ")
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$registry = Read-JsonFile -Path $RegistryPath
if ($null -eq $registry) {
    throw "Microbot registry not found or invalid: $RegistryPath"
}

$profitTracking = Read-JsonFile -Path $ProfitTrackingPath
$fleetVerdicts = Read-JsonFile -Path $FleetVerdictsPath
$winnerDeployment = Read-JsonFile -Path $WinnerDeploymentPath
$onnxFeedback = Read-JsonFile -Path $OnnxFeedbackPath
$onnxMicroReview = Read-JsonFile -Path $OnnxMicroReviewPath
$onnxSymbolRegistry = Read-JsonFile -Path $OnnxSymbolRegistryPath
$paperLiveFeedback = Read-JsonFile -Path $PaperLiveFeedbackPath
$learningStackAudit = Read-JsonFile -Path $LearningStackAuditPath
$localTrainingGuardrails = Read-JsonFile -Path $LocalTrainingGuardrailsPath
$qdmWeakestProfile = Read-JsonFile -Path $QdmWeakestProfilePath

$profitMap = New-MapByKeys -Items @($profitTracking.all) -CandidateKeys @("symbol_alias")
$verdictMap = New-MapByKeys -Items @($fleetVerdicts.verdicts) -CandidateKeys @("symbol_alias")
$winnerMap = New-MapByKeys -Items @($winnerDeployment.winners) -CandidateKeys @("symbol_alias")
$onnxFeedbackMap = New-MapByKeys -Items @($onnxFeedback.items) -CandidateKeys @("symbol_alias")
$onnxMicroReviewMap = New-MapByKeys -Items @($onnxMicroReview.items) -CandidateKeys @("symbol_alias")
$onnxRegistryMap = New-MapByKeys -Items @($onnxSymbolRegistry.items) -CandidateKeys @("symbol")
$qdmWeakestMap = New-MapByKeys -Items @($qdmWeakestProfile.included) -CandidateKeys @("symbol_alias")
$guardrailMap = New-MapByKeys -Items @($localTrainingGuardrails.items) -CandidateKeys @("symbol_alias")

$paperItems = New-Object System.Collections.Generic.List[object]
foreach ($item in @($paperLiveFeedback.top_active)) {
    $paperItems.Add($item) | Out-Null
}
foreach ($item in @($paperLiveFeedback.key_instruments)) {
    $paperItems.Add($item) | Out-Null
}
$paperMap = New-MapByKeys -Items @($paperItems.ToArray()) -CandidateKeys @("instrument")

$qdmCoverageSet = @{}
if ($null -ne $learningStackAudit -and $null -ne $learningStackAudit.learning) {
    foreach ($symbol in @($learningStackAudit.learning.qdm_symbols_with_coverage)) {
        $normalized = Normalize-SymbolKey -Value ([string]$symbol)
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            $qdmCoverageSet[$normalized] = $true
        }
    }
}

$items = New-Object System.Collections.Generic.List[object]

foreach ($symbolEntry in @($registry.symbols)) {
    $alias = [string]$symbolEntry.symbol
    $key = Normalize-SymbolKey -Value $alias

    $profitEntry = if ($profitMap.ContainsKey($key)) { $profitMap[$key] } else { $null }
    $verdictEntry = if ($verdictMap.ContainsKey($key)) { $verdictMap[$key] } else { $null }
    $winnerEntry = if ($winnerMap.ContainsKey($key)) { $winnerMap[$key] } else { $null }
    $onnxFeedbackEntry = if ($onnxFeedbackMap.ContainsKey($key)) { $onnxFeedbackMap[$key] } else { $null }
    $onnxMicroReviewEntry = if ($onnxMicroReviewMap.ContainsKey($key)) { $onnxMicroReviewMap[$key] } else { $null }
    $onnxRegistryEntry = if ($onnxRegistryMap.ContainsKey($key)) { $onnxRegistryMap[$key] } else { $null }
    $paperEntry = if ($paperMap.ContainsKey($key)) { $paperMap[$key] } else { $null }
    $qdmWeakestEntry = if ($qdmWeakestMap.ContainsKey($key)) { $qdmWeakestMap[$key] } else { $null }
    $guardrailEntry = if ($guardrailMap.ContainsKey($key)) { $guardrailMap[$key] } else { $null }

    $businessStatus = Get-OptionalString -Object $verdictEntry -Name "business_status" -Default (Get-OptionalString -Object $profitEntry -Name "status" -Default "UNKNOWN")
    $fleetVerdict = Get-OptionalString -Object $verdictEntry -Name "werdykt_koncowy" -Default ""
    $onnxStatus = Get-OptionalString -Object $verdictEntry -Name "onnx_status" -Default (Get-OptionalString -Object $onnxRegistryEntry -Name "status" -Default "UNKNOWN")
    $onnxQuality = Get-OptionalString -Object $verdictEntry -Name "onnx_jakosc" -Default (Get-OptionalString -Object $onnxMicroReviewEntry -Name "jakosc_onnx" -Default "")
    $onnxAudit = Get-OptionalString -Object $verdictEntry -Name "onnx_krzyzowy_audyt" -Default ""
    $trustState = Get-OptionalString -Object $profitEntry -Name "current_priority_trust" -Default (Get-OptionalString -Object $paperEntry -Name "trust" -Default "")
    $costState = Get-OptionalString -Object $profitEntry -Name "current_priority_cost" -Default (Get-OptionalString -Object $paperEntry -Name "cost" -Default "")

    $modelRows = Get-OptionalNumber -Object $onnxRegistryEntry -Name "rows_total" -Default (Get-OptionalNumber -Object $onnxMicroReviewEntry -Name "liczba_wierszy" -Default 0)
    $runtimeRows = Get-OptionalNumber -Object $onnxFeedbackEntry -Name "obserwacje_onnx" -Default 0
    $runtimePaperRows = Get-OptionalNumber -Object $onnxFeedbackEntry -Name "obserwacje_paper" -Default 0
    $runtimeLiveRows = Get-OptionalNumber -Object $onnxFeedbackEntry -Name "obserwacje_live" -Default 0
    $outcomeRows = Get-OptionalNumber -Object $onnxFeedbackEntry -Name "obserwacje_z_wynikiem_rynku" -Default 0
    $runtimeCandidateRows = Get-OptionalNumber -Object $onnxFeedbackEntry -Name "obserwacje_z_kandydatem" -Default 0
    $prioritySampleCount = Get-OptionalNumber -Object $profitEntry -Name "current_priority_learning_sample_count" -Default 0
    $qdmPilotRows = Get-OptionalNumber -Object $profitEntry -Name "qdm_pilot_row_count" -Default 0
    $qdmReady = (Get-OptionalBool -Object $profitEntry -Name "qdm_custom_pilot_ready" -Default $false) -or (Get-OptionalBool -Object $verdictEntry -Name "qdm_custom_gotowy" -Default $false)
    if (-not $qdmReady -and $qdmPilotRows -gt 0) {
        $qdmReady = $true
    }

    $testerPnl = Get-OptionalNumber -Object $profitEntry -Name "best_tester_pnl" -Default (Get-OptionalNumber -Object $winnerEntry -Name "wynik_testera_usd" -Default 0)
    $paperNet = Get-OptionalNumber -Object $paperEntry -Name "net" -Default (Get-OptionalNumber -Object $verdictEntry -Name "live_net_24h" -Default 0)
    $paperFresh = Get-OptionalBool -Object $paperEntry -Name "fresh" -Default $false
    $paperFreshnessSeconds = Get-OptionalNumber -Object $paperEntry -Name "freshness_seconds" -Default -1
    $priorityRank = [int](Get-OptionalNumber -Object $profitEntry -Name "priority_rank" -Default 999)
    $priorityBand = Get-OptionalString -Object $profitEntry -Name "current_priority_band" -Default ""
    $qdmCoverageVisible = $qdmCoverageSet.ContainsKey($key)

    $sampleFreshnessState = Get-SampleFreshnessState -RuntimeRows $runtimeRows -PaperFresh $paperFresh -QdmReady $qdmReady -QdmRows $qdmPilotRows -ModelRows $modelRows
    $healthState = Get-LearningHealthState `
        -OnnxStatus $onnxStatus `
        -OnnxQuality $onnxQuality `
        -OnnxAudit $onnxAudit `
        -ModelRows $modelRows `
        -RuntimeRows $runtimeRows `
        -OutcomeRows $outcomeRows `
        -PrioritySampleCount $prioritySampleCount `
        -BusinessStatus $businessStatus `
        -CostState $costState `
        -TrustState $trustState `
        -TesterPnl $testerPnl `
        -PaperNet $paperNet
    $workMode = Get-WorkMode -HealthState $healthState -BusinessStatus $businessStatus -PaperNet $paperNet -RuntimeRows $runtimeRows
    $healthPriority = Get-HealthPriority -HealthState $healthState -WorkMode $workMode
    $recommendation = Get-HealthRecommendation -HealthState $healthState -OnnxQuality $onnxQuality -RuntimeRows $runtimeRows -OutcomeRows $outcomeRows -QdmCoverageVisible $qdmCoverageVisible
    $guardrailState = Get-OptionalString -Object $guardrailEntry -Name "guardrail_state" -Default ""
    $guardrailReason = Get-OptionalString -Object $guardrailEntry -Name "diagnosis" -Default ""

    if ($guardrailState -eq "FORCED_GLOBAL_FALLBACK") {
        $healthState = "FALLBACK_GLOBALNY"
        $workMode = "FALLBACK_DO_NAUCZYCIELA"
        $healthPriority = Get-HealthPriority -HealthState $healthState -WorkMode $workMode
        if (-not [string]::IsNullOrWhiteSpace($guardrailReason)) {
            $recommendation = "$recommendation; guardrail lokalnego toru wymusza fallback: $guardrailReason"
        }
    }
    elseif ($guardrailState -eq "PROBATION_ONLY" -and $healthState -in @("UCZY_SIE_ZDROWO", "GOTOWY_DO_MIEKKIEJ_BRAMKI", "GOTOWY_DO_OBSERWACJI")) {
        $workMode = "OBSERWUJ"
        $healthPriority = Get-HealthPriority -HealthState $healthState -WorkMode $workMode
        if (-not [string]::IsNullOrWhiteSpace($guardrailReason)) {
            $recommendation = "$recommendation; guardrail lokalnego toru zostawia symbol tylko w probacji: $guardrailReason"
        }
    }

    $items.Add([pscustomobject]@{
        symbol_alias = $alias
        broker_symbol = [string]$symbolEntry.broker_symbol
        session_profile = [string]$symbolEntry.session_profile
        business_status = $businessStatus
        fleet_verdict = $fleetVerdict
        priority_rank = $priorityRank
        priority_band = $priorityBand
        trust_state = $trustState
        cost_state = $costState
        onnx_status = $onnxStatus
        onnx_quality = $onnxQuality
        onnx_audit = $onnxAudit
        local_training_guardrail_state = $guardrailState
        local_training_guardrail_reason = $guardrailReason
        qdm_custom_ready = $qdmReady
        qdm_pilot_rows = [int]$qdmPilotRows
        qdm_rank = if ($null -ne $qdmWeakestEntry) { [int]$qdmWeakestEntry.rank } else { 999 }
        qdm_symbol_coverage_visible = $qdmCoverageVisible
        sample_model_rows = [int]$modelRows
        sample_runtime_onnx_rows = [int]$runtimeRows
        sample_runtime_candidate_rows = [int]$runtimeCandidateRows
        sample_runtime_outcome_rows = [int]$outcomeRows
        sample_priority_learning_count = [int]$prioritySampleCount
        sample_freshness_state = $sampleFreshnessState
        paper_share_pct = if ($runtimeRows -gt 0) { [math]::Round((100.0 * $runtimePaperRows / $runtimeRows), 2) } else { 0.0 }
        live_share_pct = if ($runtimeRows -gt 0) { [math]::Round((100.0 * $runtimeLiveRows / $runtimeRows), 2) } else { 0.0 }
        paper_net_pln = [math]::Round($paperNet, 2)
        paper_fresh = $paperFresh
        paper_freshness_seconds = if ($paperFreshnessSeconds -ge 0) { [int]$paperFreshnessSeconds } else { $null }
        tester_pnl_usd = [math]::Round($testerPnl, 2)
        learning_health_state = $healthState
        work_mode = $workMode
        health_priority = $healthPriority
        recommendation = $recommendation
    }) | Out-Null
}

$itemsArray = @(
    $items.ToArray() |
        Sort-Object `
            @{ Expression = { [int]$_.health_priority }; Ascending = $true }, `
            @{ Expression = { [int]$_.priority_rank }; Ascending = $true }, `
            @{ Expression = { -1.0 * [double]$_.sample_runtime_onnx_rows }; Ascending = $true }, `
            symbol_alias
)

$summary = [ordered]@{
    total_symbols = $itemsArray.Count
    fallback_globalny = @($itemsArray | Where-Object { $_.learning_health_state -eq "FALLBACK_GLOBALNY" }).Count
    mala_probka = @($itemsArray | Where-Object { $_.learning_health_state -eq "MALA_PROBKA" }).Count
    wymaga_doszkolenia = @($itemsArray | Where-Object { $_.learning_health_state -eq "WYMAGA_DOSZKOLENIA" }).Count
    wymaga_regeneracji = @($itemsArray | Where-Object { $_.learning_health_state -eq "WYMAGA_REGENERACJI" }).Count
    gotowy_do_uczenia = @($itemsArray | Where-Object { $_.learning_health_state -eq "GOTOWY_DO_UCZENIA" }).Count
    uczy_sie_zdrowo = @($itemsArray | Where-Object { $_.learning_health_state -eq "UCZY_SIE_ZDROWO" }).Count
    gotowy_do_obserwacji = @($itemsArray | Where-Object { $_.learning_health_state -eq "GOTOWY_DO_OBSERWACJI" }).Count
    gotowy_do_miekkiej_bramki = @($itemsArray | Where-Object { $_.learning_health_state -eq "GOTOWY_DO_MIEKKIEJ_BRAMKI" }).Count
    gotowy_do_paper_live = @($itemsArray | Where-Object { $_.learning_health_state -eq "GOTOWY_DO_PAPER_LIVE" }).Count
    runtime_active_symbols = @($itemsArray | Where-Object { $_.sample_runtime_onnx_rows -gt 0 }).Count
    runtime_outcome_symbols = @($itemsArray | Where-Object { $_.sample_runtime_outcome_rows -gt 0 }).Count
    qdm_visible_symbols = @($itemsArray | Where-Object { $_.qdm_symbol_coverage_visible }).Count
    qdm_ready_symbols = @($itemsArray | Where-Object { $_.qdm_custom_ready }).Count
    do_regeneracji = @($itemsArray | Where-Object { $_.work_mode -eq "REGENERUJ" }).Count
    do_docisku = @($itemsArray | Where-Object { $_.work_mode -eq "DOCISKAJ" }).Count
    do_obserwacji = @($itemsArray | Where-Object { $_.work_mode -eq "OBSERWUJ" }).Count
    do_eksploatacji = @($itemsArray | Where-Object { $_.work_mode -eq "EKSPLOATUJ" }).Count
}

$topRegeneration = @($itemsArray | Where-Object { $_.work_mode -eq "REGENERUJ" } | Select-Object -First 6)
$topPressure = @($itemsArray | Where-Object { $_.work_mode -in @("DOCISKAJ", "WYHAMUJ_I_ZBIERAJ_PROBKE", "FALLBACK_DO_NAUCZYCIELA") } | Select-Object -First 6)
$topHealthy = @($itemsArray | Where-Object { $_.learning_health_state -in @("UCZY_SIE_ZDROWO", "GOTOWY_DO_MIEKKIEJ_BRAMKI", "GOTOWY_DO_OBSERWACJI") } | Select-Object -First 6)

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    summary = $summary
    top_regeneration = $topRegeneration
    top_pressure = $topPressure
    top_healthy = $topHealthy
    items = $itemsArray
}

$jsonPath = Join-Path $OutputRoot "learning_health_registry_latest.json"
$mdPath = Join-Path $OutputRoot "learning_health_registry_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Learning Health Registry")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add("")
$lines.Add("## Summary")
$lines.Add("")
foreach ($prop in $summary.GetEnumerator()) {
    $lines.Add(("- {0}: {1}" -f $prop.Key, $prop.Value))
}
$lines.Add("")
$lines.Add("## Top Pressure")
$lines.Add("")
foreach ($item in $topPressure) {
    $lines.Add(("- {0}: health={1}, mode={2}, rank={3}, onnx={4}/{5}, model_rows={6}, runtime_rows={7}, tester_pnl_usd={8}, paper_net_pln={9}" -f
        $item.symbol_alias,
        $item.learning_health_state,
        $item.work_mode,
        $item.priority_rank,
        $item.onnx_status,
        $item.onnx_quality,
        $item.sample_model_rows,
        $item.sample_runtime_onnx_rows,
        $item.tester_pnl_usd,
        $item.paper_net_pln))
}
$lines.Add("")
$lines.Add("## Top Regeneration")
$lines.Add("")
foreach ($item in $topRegeneration) {
    $lines.Add(("- {0}: health={1}, onnx={2}/{3}, trust={4}, cost={5}, recommendation={6}" -f
        $item.symbol_alias,
        $item.learning_health_state,
        $item.onnx_status,
        $item.onnx_quality,
        $item.trust_state,
        $item.cost_state,
        $item.recommendation))
}
$lines.Add("")
$lines.Add("## Top Healthy")
$lines.Add("")
foreach ($item in $topHealthy) {
    $lines.Add(("- {0}: health={1}, mode={2}, runtime_rows={3}, outcome_rows={4}, qdm_visible={5}, recommendation={6}" -f
        $item.symbol_alias,
        $item.learning_health_state,
        $item.work_mode,
        $item.sample_runtime_onnx_rows,
        $item.sample_runtime_outcome_rows,
        $item.qdm_symbol_coverage_visible,
        $item.recommendation))
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8 -Compress
