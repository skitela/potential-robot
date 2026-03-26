param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
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

function Normalize-SymbolAlias {
    param([string]$Symbol)

    if ([string]::IsNullOrWhiteSpace($Symbol)) {
        return ""
    }

    return ($Symbol.Trim().ToUpperInvariant() -replace "\.PRO$", "")
}

function Get-PositiveRatio {
    param(
        [int]$PositiveRows,
        [int]$TotalRows
    )

    if ($TotalRows -le 0) {
        return $null
    }

    return [math]::Round(($PositiveRows / [double]$TotalRows), 4)
}

function Resolve-SourceMode {
    param(
        [string]$OnnxStatus,
        [string]$TrainingReadinessState,
        [string]$LocalTrainingEligibility,
        [int]$CandidateRows,
        [int]$RuntimeRows,
        [int]$OutcomeRows
    )

    if ($TrainingReadinessState -eq "TRAINING_SHADOW_READY" -or $LocalTrainingEligibility -eq "SHADOW_ONLY") {
        return "CIEN_NAUCZYCIELA_GLOBALNEGO"
    }

    if ($OnnxStatus -eq "MODEL_PER_SYMBOL_READY") {
        if ($OutcomeRows -gt 0) {
            return "GLOBALNY_PLUS_LOKALNY_DOMKNIETY"
        }
        if ($RuntimeRows -gt 0 -and $CandidateRows -gt 0) {
            return "GLOBALNY_PLUS_LOKALNY_W_RUNTIME"
        }
        if ($RuntimeRows -gt 0) {
            return "LOKALNY_RUNTIME_BEZ_KANDYDATOW"
        }
        return "LOKALNY_MODEL_BEZ_RUNTIME"
    }

    return "GLOBALNY_FALLBACK"
}

function Resolve-MainBlocker {
    param(
        [bool]$QdmReady,
        [double]$GlobalCoverageRatio,
        [int]$CandidateRows,
        [int]$RuntimeRows,
        [int]$OutcomeRows,
        [string]$OnnxQuality,
        [string]$LearningHealthState,
        [string]$TrustState,
        [string]$CostState
    )

    if (-not $QdmReady) {
        return "BRAK_QDM"
    }
    if ($CandidateRows -le 0) {
        return "BRAK_KANDYDATOW"
    }
    if ($RuntimeRows -le 0) {
        return "BRAK_RUNTIME_ONNX"
    }
    if ($OutcomeRows -le 0) {
        return "BRAK_WYNIKU_RYNKU"
    }
    if ($OnnxQuality -eq "SLABY") {
        return "JAKOSC_MALEGO_MODELU"
    }
    if ($TrustState -eq "LOW_SAMPLE") {
        return "MALA_PROBKA"
    }
    if ($TrustState -eq "FOREFIELD_DIRTY") {
        return "BRUDNY_FOREGROUND"
    }
    if ($CostState -in @("HIGH", "NON_REPRESENTATIVE")) {
        return "KOSZT_I_REPREZENTATYWNOSC"
    }
    if ($LearningHealthState -eq "FALLBACK_GLOBALNY") {
        return "FALLBACK_GLOBALNY"
    }
    if ($GlobalCoverageRatio -le 0.0) {
        return "BRAK_QDM_W_MODELU_GLOBALNYM"
    }
    return "BRAK_CZERWONEJ_FLAGI"
}

function Resolve-Recommendation {
    param(
        [string]$MainBlocker,
        [string]$SourceMode
    )

    switch ($MainBlocker) {
        "BRAK_KANDYDATOW" { return "sprawdzic strategie i progi strojenia; symbol ma dane, ale nie produkuje kandydatow" }
        "BRAK_RUNTIME_ONNX" { return "sprawdzic kabel malego ONNX i inicjalizacje runtime" }
        "BRAK_WYNIKU_RYNKU" { return "domknac sprzezenie zwrotne outcome przed dalszym awansem" }
        "JAKOSC_MALEGO_MODELU" { return "doszkolic albo przebudowac maly model; nie promowac dalej" }
        "MALA_PROBKA" { return "utrzymac cien nauczyciela globalnego i dalej budowac probe" }
        "BRAK_QDM_W_MODELU_GLOBALNYM" { return "odswiezyc globalny trening, bo model nadal nie widzi pelnego QDM" }
        "KOSZT_I_REPREZENTATYWNOSC" { return "naprawic koszt i reprezentatywnosc zanim pojdzie kolejny trening" }
        "BRUDNY_FOREGROUND" { return "oczyscic foreground i kandydaty zanim symbol dostanie kolejny awans" }
        default {
            if ($SourceMode -eq "GLOBALNY_PLUS_LOKALNY_DOMKNIETY") {
                return "utrzymac pod twardym audytem i spokojnie rozwijac"
            }
            return "utrzymac obserwacje i zbierac dalsze dane"
        }
    }
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$globalMetricsPath = Join-Path $ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json"
$dataReadinessPath = Join-Path $opsRoot "instrument_data_readiness_latest.json"
$trainingReadinessPath = Join-Path $opsRoot "instrument_training_readiness_latest.json"
$learningHealthPath = Join-Path $opsRoot "learning_health_registry_latest.json"
$onnxMicroReviewPath = Join-Path $opsRoot "onnx_micro_review_latest.json"
$onnxFeedbackPath = Join-Path $opsRoot "onnx_feedback_loop_latest.json"
$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"

$globalMetrics = Read-JsonSafe -Path $globalMetricsPath
$dataReadiness = Read-JsonSafe -Path $dataReadinessPath
$trainingReadiness = Read-JsonSafe -Path $trainingReadinessPath
$learningHealth = Read-JsonSafe -Path $learningHealthPath
$onnxMicroReview = Read-JsonSafe -Path $onnxMicroReviewPath
$onnxFeedback = Read-JsonSafe -Path $onnxFeedbackPath
$registry = Read-JsonSafe -Path $registryPath

if ($null -eq $dataReadiness -or $null -eq $trainingReadiness -or $null -eq $learningHealth -or $null -eq $onnxMicroReview) {
    throw "Brakuje jednego z kluczowych raportow do audytu zrodel uczenia."
}

$globalCoverageMap = @{}
$globalCoverageSymbols = @()
$globalCoverageRatio = 0.0
$globalPositiveRate = $null
if ($null -ne $globalMetrics) {
    $coverage = Get-OptionalValue -Object (Get-OptionalValue -Object $globalMetrics -Name "dataset" -Default $null) -Name "qdm_coverage" -Default $null
    $globalCoverageSymbols = @((Get-OptionalValue -Object $coverage -Name "symbols_with_qdm" -Default @()))
    foreach ($item in @((Get-OptionalValue -Object $coverage -Name "symbol_coverage" -Default @()))) {
        $symbol = Normalize-SymbolAlias ([string](Get-OptionalValue -Object $item -Name "symbol" -Default ""))
        if (-not [string]::IsNullOrWhiteSpace($symbol)) {
            $globalCoverageMap[$symbol] = $item
        }
    }
    $globalCoverageRatio = [double](Get-OptionalValue -Object $coverage -Name "row_coverage_ratio" -Default 0.0)
    $globalPositiveRate = Get-OptionalValue -Object (Get-OptionalValue -Object $globalMetrics -Name "dataset" -Default $null) -Name "positive_rate" -Default $null
}

$dataMap = @{}
foreach ($item in @($dataReadiness.items)) {
    $symbol = Normalize-SymbolAlias ([string]$item.symbol_alias)
    if (-not [string]::IsNullOrWhiteSpace($symbol)) {
        $dataMap[$symbol] = $item
    }
}

$trainingMap = @{}
foreach ($item in @($trainingReadiness.items)) {
    $symbol = Normalize-SymbolAlias ([string]$item.symbol_alias)
    if (-not [string]::IsNullOrWhiteSpace($symbol)) {
        $trainingMap[$symbol] = $item
    }
}

$healthMap = @{}
foreach ($item in @($learningHealth.items)) {
    $symbol = Normalize-SymbolAlias ([string]$item.symbol_alias)
    if (-not [string]::IsNullOrWhiteSpace($symbol)) {
        $healthMap[$symbol] = $item
    }
}

$onnxMap = @{}
foreach ($item in @($onnxMicroReview.items)) {
    $symbol = Normalize-SymbolAlias ([string]$item.symbol_alias)
    if (-not [string]::IsNullOrWhiteSpace($symbol)) {
        $onnxMap[$symbol] = $item
    }
}

$registryMap = @{}
foreach ($item in @($registry.symbols)) {
    $symbol = Normalize-SymbolAlias ([string](Get-OptionalValue -Object $item -Name "symbol" -Default ""))
    if (-not [string]::IsNullOrWhiteSpace($symbol)) {
        $registryMap[$symbol] = $item
    }
}

$symbolOrder = New-Object System.Collections.Generic.List[string]
foreach ($item in @($registry.symbols)) {
    $symbol = Normalize-SymbolAlias ([string](Get-OptionalValue -Object $item -Name "symbol" -Default ""))
    if (-not [string]::IsNullOrWhiteSpace($symbol) -and -not $symbolOrder.Contains($symbol)) {
        $symbolOrder.Add($symbol) | Out-Null
    }
}
foreach ($symbol in @($dataMap.Keys)) {
    if (-not $symbolOrder.Contains($symbol)) {
        $symbolOrder.Add($symbol) | Out-Null
    }
}

$items = foreach ($symbol in $symbolOrder) {
    $data = Get-OptionalValue -Object $dataMap -Name $symbol -Default $null
    $training = Get-OptionalValue -Object $trainingMap -Name $symbol -Default $null
    $health = Get-OptionalValue -Object $healthMap -Name $symbol -Default $null
    $onnx = Get-OptionalValue -Object $onnxMap -Name $symbol -Default $null
    $globalCoverage = Get-OptionalValue -Object $globalCoverageMap -Name $symbol -Default $null
    $registryItem = Get-OptionalValue -Object $registryMap -Name $symbol -Default $null

    $qdmRows = [int](Get-OptionalValue -Object $data -Name "qdm_contract_rows" -Default 0)
    $candidateRows = [int](Get-OptionalValue -Object $data -Name "candidate_contract_rows" -Default 0)
    $learningRows = [int](Get-OptionalValue -Object $data -Name "learning_contract_rows" -Default 0)
    $runtimeRows = [int](Get-OptionalValue -Object $data -Name "onnx_runtime_rows" -Default 0)
    $outcomeRows = [int](Get-OptionalValue -Object $data -Name "outcome_rows" -Default 0)
    $statusOnnx = [string](Get-OptionalValue -Object $onnx -Name "status_onnx" -Default "GLOBAL_FALLBACK")
    $onnxQuality = [string](Get-OptionalValue -Object $onnx -Name "jakosc_onnx" -Default "FALLBACK_GLOBALNY")
    $localRows = [int](Get-OptionalValue -Object $onnx -Name "liczba_wierszy" -Default 0)
    $positiveRows = [int](Get-OptionalValue -Object $onnx -Name "dodatnie_wiersze" -Default 0)
    $negativeRows = [int](Get-OptionalValue -Object $onnx -Name "ujemne_wiersze" -Default 0)
    $positiveRatioLocal = Get-PositiveRatio -PositiveRows $positiveRows -TotalRows $localRows
    $globalCoverageRows = [int](Get-OptionalValue -Object $globalCoverage -Name "rows_with_qdm" -Default 0)
    $globalCoverageRatioSymbol = [double](Get-OptionalValue -Object $globalCoverage -Name "coverage_ratio" -Default 0.0)
    $trainingState = [string](Get-OptionalValue -Object $training -Name "training_readiness_state" -Default "")
    $localTrainingEligibility = [string](Get-OptionalValue -Object $training -Name "local_training_eligibility" -Default "")
    $learningHealthState = [string](Get-OptionalValue -Object $training -Name "learning_health_state" -Default (Get-OptionalValue -Object $health -Name "learning_health_state" -Default ""))
    $workMode = [string](Get-OptionalValue -Object $training -Name "work_mode" -Default (Get-OptionalValue -Object $health -Name "work_mode" -Default ""))
    $trustState = [string](Get-OptionalValue -Object $health -Name "trust_state" -Default "")
    $costState = [string](Get-OptionalValue -Object $health -Name "cost_state" -Default "")
    $sessionProfile = [string](Get-OptionalValue -Object $data -Name "session_profile" -Default (Get-OptionalValue -Object $onnx -Name "session_profile" -Default (Get-OptionalValue -Object $registryItem -Name "session_profile" -Default "")))
    $qdmReady = ($qdmRows -gt 0)
    $sourceMode = Resolve-SourceMode -OnnxStatus $statusOnnx -TrainingReadinessState $trainingState -LocalTrainingEligibility $localTrainingEligibility -CandidateRows $candidateRows -RuntimeRows $runtimeRows -OutcomeRows $outcomeRows
    $mainBlocker = Resolve-MainBlocker -QdmReady $qdmReady -GlobalCoverageRatio $globalCoverageRatioSymbol -CandidateRows $candidateRows -RuntimeRows $runtimeRows -OutcomeRows $outcomeRows -OnnxQuality $onnxQuality -LearningHealthState $learningHealthState -TrustState $trustState -CostState $costState

    [pscustomobject]@{
        symbol_alias = $symbol
        session_profile = $sessionProfile
        source_mode = $sourceMode
        glowna_blokada = $mainBlocker
        status_globalnego_modelu_qdm = $(if ($globalCoverageRatioSymbol -gt 0.0) { "QDM_WIDOCZNE" } else { "QDM_NIEWIDOCZNE" })
        globalny_model_qdm_coverage_ratio = [math]::Round($globalCoverageRatioSymbol, 4)
        globalny_model_qdm_rows = $globalCoverageRows
        status_malego_modelu = $statusOnnx
        jakosc_malego_modelu = $onnxQuality
        wiersze_malego_modelu = $localRows
        dodatni_udzial_malego_modelu = $positiveRatioLocal
        spelnia_cel_60p = $(if ($null -eq $positiveRatioLocal) { $false } else { $positiveRatioLocal -ge 0.60 })
        qdm_gotowe = $qdmReady
        qdm_wiersze = $qdmRows
        kandydaty_wiersze = $candidateRows
        wiersze_uczenia = $learningRows
        runtime_onnx_wiersze = $runtimeRows
        outcome_wiersze = $outcomeRows
        stan_treningu = $trainingState
        kwalifikacja_lokalna = $localTrainingEligibility
        stan_zdrowia_uczenia = $learningHealthState
        tryb_pracy = $workMode
        zaufanie = $trustState
        koszt = $costState
        rekomendacja = Resolve-Recommendation -MainBlocker $mainBlocker -SourceMode $sourceMode
    }
}

$globalVisibleCount = @($items | Where-Object { $_.status_globalnego_modelu_qdm -eq "QDM_WIDOCZNE" }).Count
$runtimeWithoutOutcomeCount = @($items | Where-Object { $_.runtime_onnx_wiersze -gt 0 -and $_.outcome_wiersze -le 0 }).Count
$candidateGapCount = @($items | Where-Object { $_.qdm_gotowe -and $_.kandydaty_wiersze -le 0 }).Count
$shadowOnlyCount = @($items | Where-Object { $_.kwalifikacja_lokalna -eq "SHADOW_ONLY" -or $_.stan_treningu -eq "TRAINING_SHADOW_READY" }).Count
$fallbackCount = @($items | Where-Object { $_.source_mode -eq "GLOBALNY_FALLBACK" }).Count
$blockedCount = @($items | Where-Object { $_.glowna_blokada -ne "BRAK_CZERWONEJ_FLAGI" }).Count
$target60Count = @($items | Where-Object { $_.spelnia_cel_60p }).Count
$target60MissedCount = @($items | Where-Object { $_.wiersze_malego_modelu -gt 0 -and -not $_.spelnia_cel_60p }).Count
$globalCoverageGapCount = [math]::Max(0, @($items | Where-Object { $_.qdm_gotowe }).Count - $globalVisibleCount)

$summary = [ordered]@{
    total_symbols = @($items).Count
    globalny_model_qdm_coverage_ratio = [math]::Round($globalCoverageRatio, 4)
    globalny_model_qdm_visible_symbols = $globalVisibleCount
    globalny_model_qdm_visibility_gap_count = $globalCoverageGapCount
    lokalny_model_ready_count = @($items | Where-Object { $_.status_malego_modelu -eq "MODEL_PER_SYMBOL_READY" }).Count
    shadow_only_count = $shadowOnlyCount
    fallback_globalny_count = $fallbackCount
    candidate_gap_count = $candidateGapCount
    runtime_without_outcome_count = $runtimeWithoutOutcomeCount
    blocked_count = $blockedCount
    target_60p_met_count = $target60Count
    target_60p_missed_count = $target60MissedCount
    runtime_active_symbols = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $onnxFeedback -Name "summary" -Default $null) -Name "liczba_symboli_aktywnych_60m" -Default 0)
    runtime_total_observations = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $onnxFeedback -Name "summary" -Default $null) -Name "liczba_obserwacji_onnx" -Default 0)
    dodatni_udzial_globalnego_modelu = $(if ($null -eq $globalPositiveRate) { $null } else { [math]::Round([double]$globalPositiveRate, 4) })
}

$topCritical = @(
    $items |
        Sort-Object @{
            Expression = {
                switch ($_.glowna_blokada) {
                    "BRAK_KANDYDATOW" { 0 }
                    "BRAK_WYNIKU_RYNKU" { 1 }
                    "JAKOSC_MALEGO_MODELU" { 2 }
                    "BRAK_QDM_W_MODELU_GLOBALNYM" { 3 }
                    "MALA_PROBKA" { 4 }
                    default { 9 }
                }
            }
        }, @{
            Expression = { $_.runtime_onnx_wiersze }
            Descending = $false
        }, symbol_alias |
        Select-Object -First 8
)

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    summary = $summary
    top_critical = $topCritical
    items = $items
}

$jsonPath = Join-Path $OutputRoot "learning_source_audit_latest.json"
$mdPath = Join-Path $OutputRoot "learning_source_audit_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Audyt Zrodel Uczenia")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- globalny_model_qdm_coverage_ratio: {0}" -f $summary.globalny_model_qdm_coverage_ratio))
$lines.Add(("- globalny_model_qdm_visible_symbols: {0}" -f $summary.globalny_model_qdm_visible_symbols))
$lines.Add(("- globalny_model_qdm_visibility_gap_count: {0}" -f $summary.globalny_model_qdm_visibility_gap_count))
$lines.Add(("- lokalny_model_ready_count: {0}" -f $summary.lokalny_model_ready_count))
$lines.Add(("- shadow_only_count: {0}" -f $summary.shadow_only_count))
$lines.Add(("- fallback_globalny_count: {0}" -f $summary.fallback_globalny_count))
$lines.Add(("- candidate_gap_count: {0}" -f $summary.candidate_gap_count))
$lines.Add(("- runtime_without_outcome_count: {0}" -f $summary.runtime_without_outcome_count))
$lines.Add(("- blocked_count: {0}" -f $summary.blocked_count))
$lines.Add(("- target_60p_met_count: {0}" -f $summary.target_60p_met_count))
$lines.Add(("- target_60p_missed_count: {0}" -f $summary.target_60p_missed_count))
$lines.Add("")
foreach ($item in @($items)) {
    $lines.Add(("## {0}" -f $item.symbol_alias))
    $lines.Add(("- profil: {0}" -f $item.session_profile))
    $lines.Add(("- source_mode: {0}" -f $item.source_mode))
    $lines.Add(("- glowna_blokada: {0}" -f $item.glowna_blokada))
    $lines.Add(("- status_globalnego_modelu_qdm: {0}" -f $item.status_globalnego_modelu_qdm))
    $lines.Add(("- globalny_model_qdm_coverage_ratio: {0}" -f $item.globalny_model_qdm_coverage_ratio))
    $lines.Add(("- status_malego_modelu: {0}" -f $item.status_malego_modelu))
    $lines.Add(("- jakosc_malego_modelu: {0}" -f $item.jakosc_malego_modelu))
    $lines.Add(("- wiersze_malego_modelu: {0}" -f $item.wiersze_malego_modelu))
    $lines.Add(("- dodatni_udzial_malego_modelu: {0}" -f $(if ($null -eq $item.dodatni_udzial_malego_modelu) { "brak" } else { $item.dodatni_udzial_malego_modelu })))
    $lines.Add(("- qdm_wiersze: {0}" -f $item.qdm_wiersze))
    $lines.Add(("- kandydaty_wiersze: {0}" -f $item.kandydaty_wiersze))
    $lines.Add(("- runtime_onnx_wiersze: {0}" -f $item.runtime_onnx_wiersze))
    $lines.Add(("- outcome_wiersze: {0}" -f $item.outcome_wiersze))
    $lines.Add(("- stan_treningu: {0}" -f $item.stan_treningu))
    $lines.Add(("- kwalifikacja_lokalna: {0}" -f $item.kwalifikacja_lokalna))
    $lines.Add(("- stan_zdrowia_uczenia: {0}" -f $item.stan_zdrowia_uczenia))
    $lines.Add(("- rekomendacja: {0}" -f $item.rekomendacja))
    $lines.Add("")
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
