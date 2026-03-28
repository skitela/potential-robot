param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH"
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

function Read-TextSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function To-Bool {
    param([object]$Value)

    return [bool]$Value
}

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $Default
    }

    try {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property) {
            return $Default
        }
        return $property.Value
    }
    catch {
        return $Default
    }
}

function Get-OptionalNumber {
    param(
        [object]$Object,
        [string[]]$Names,
        [double]$Default = 0.0
    )

    foreach ($name in @($Names)) {
        $value = Get-OptionalValue -Object $Object -Name $name -Default $null
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [double]$value
        }
    }

    return $Default
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$metricsPath = Join-Path $ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_latest_metrics.json"
$reportPath = Join-Path $ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_report_latest.md"
$learningSourceAuditPath = Join-Path $opsRoot "learning_source_audit_latest.json"
$qdmVisibilityRefreshPath = Join-Path $opsRoot "qdm_visibility_refresh_profile_latest.json"
$trainingScriptPath = Join-Path $ProjectRoot "TOOLS\mb_ml_core\trainer.py"
$modelDefinitionPath = Join-Path $ProjectRoot "TOOLS\mb_ml_core\models.py"
$exportScriptPath = Join-Path $ProjectRoot "TOOLS\mb_ml_core\export.py"
$paperTradingPath = Join-Path $ProjectRoot "MQL5\Include\Core\MbPaperTrading.mqh"
$executionPrecheckPath = Join-Path $ProjectRoot "MQL5\Include\Core\MbExecutionPrecheck.mqh"
$mlRuntimeBridgePath = Join-Path $ProjectRoot "MQL5\Include\Core\MbMlRuntimeBridge.mqh"
$researchPythonPath = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
$globalOnnxPath = Join-Path $ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_latest.onnx"
$jsonPath = Join-Path $opsRoot "ml_scalping_fit_audit_latest.json"

$metrics = Read-JsonSafe -Path $metricsPath
$learningSourceAudit = Read-JsonSafe -Path $learningSourceAuditPath
$qdmVisibilityRefresh = Read-JsonSafe -Path $qdmVisibilityRefreshPath
$trainingScriptText = Read-TextSafe -Path $trainingScriptPath
$modelDefinitionText = Read-TextSafe -Path $modelDefinitionPath
$exportScriptText = Read-TextSafe -Path $exportScriptPath
$reportText = Read-TextSafe -Path $reportPath
$paperTradingText = Read-TextSafe -Path $paperTradingPath
$executionPrecheckText = Read-TextSafe -Path $executionPrecheckPath
$mlRuntimeBridgeText = Read-TextSafe -Path $mlRuntimeBridgePath

$summary = Get-OptionalValue -Object $metrics -Name "summary" -Default $null
$metricValues = Get-OptionalValue -Object $metrics -Name "metrics" -Default $null
$featureContract = Get-OptionalValue -Object $metrics -Name "feature_contract" -Default $null
if ($null -eq $featureContract -and $null -ne $summary) {
    $featureContract = Get-OptionalValue -Object $summary -Name "feature_contract" -Default $null
}
$teacherFeatures = @(
    Get-OptionalValue -Object $metrics -Name "teacher_features" -Default @()
)
$numericFeatures = @(
    Get-OptionalValue -Object $featureContract -Name "numeric_features" -Default @()
)
$categoricalFeatures = @(
    Get-OptionalValue -Object $featureContract -Name "categorical_features" -Default @()
)
$allFeatures = @($teacherFeatures + $numericFeatures + $categoricalFeatures)

$modelFamily = if ($trainingScriptText -match '"family"\s*:\s*"SGDClassifier"' -or $trainingScriptText -match "\bSGDClassifier\b") { "SGDClassifier" } else { "UNKNOWN" }
$usesBrokerNetTarget = ($trainingScriptText -match 'training_target"\s*:\s*"net_pln_broker"') -or ($trainingScriptText -match '"net_pln_broker"') -or ($reportText -match 'target = net_pln')
$usesAcceptedTarget = -not $usesBrokerNetTarget
$usesServerPing = @($allFeatures) -contains 'server_operational_ping_ms'
$usesServerLatency = (@($allFeatures) -contains 'server_local_latency_us_avg') -and (@($allFeatures) -contains 'server_local_latency_us_max')
$usesRuntimeLatency = @($allFeatures) -contains 'runtime_latency_us'
$supportsOnnxExport = (Test-Path -LiteralPath $globalOnnxPath) -or ($exportScriptText -match 'skl2onnx') -or ($exportScriptText -match 'to_onnx')
$supportsSparseCategorical = ($modelDefinitionText -match 'OneHotEncoder') -and ($modelDefinitionText -match 'StandardScaler')
$researchEnvReady = Test-Path -LiteralPath $researchPythonPath
$paperTracksSpread = $paperTradingText -match 'opened_spread_points'
$paperTracksCommission = ($paperTradingText -match 'commission') -or ($mlRuntimeBridgeText -match 'commission_pln')
$paperTracksSwap = ($paperTradingText -match 'swap') -or ($mlRuntimeBridgeText -match 'swap_pln')
$paperTracksBrokerNetPnl = ($paperTradingText -match 'netto') -or ($paperTradingText -match 'net_pnl') -or ($paperTradingText -match 'net_pln') -or ($paperTradingText -match 'account_currency') -or ($mlRuntimeBridgeText -match 'net_pln')
$precheckModelsSlippage = $executionPrecheckText -match 'modeled_slippage_points'
$precheckModelsCommission = $executionPrecheckText -match 'modeled_commission_points'

$datasetRows = [int64](Get-OptionalNumber -Object (Get-OptionalValue -Object $metrics -Name "dataset" -Default $summary) -Names @("total_rows", "rows") -Default 0)
$expectedSymbols = @(
    Get-OptionalValue -Object $summary -Name "expected_symbols" -Default @()
)
$trainedVisibleSymbols = @(
    Get-OptionalValue -Object $summary -Name "symbols" -Default @()
)
$qdmCoverageRatio = if ($expectedSymbols.Count -gt 0) {
    [double]$trainedVisibleSymbols.Count / [double]$expectedSymbols.Count
}
else {
    Get-OptionalNumber -Object (Get-OptionalValue -Object $metrics -Name "dataset" -Default $null) -Names @("qdm_coverage.row_coverage_ratio", "row_coverage_ratio") -Default 0.0
}
$balancedAccuracy = Get-OptionalNumber -Object $metricValues -Names @("balanced_accuracy", "balanced_accuracy_median") -Default 0.0
$rocAuc = Get-OptionalNumber -Object $metricValues -Names @("roc_auc", "roc_auc_median") -Default 0.0
$qdmSummary = Get-OptionalValue -Object $qdmVisibilityRefresh -Name "summary" -Default $null
$learningSourceSummary = Get-OptionalValue -Object $learningSourceAudit -Name "summary" -Default $null
$currentVisibleCount = [int](Get-OptionalNumber -Object $qdmSummary -Names @("current_contract_qdm_visible_symbols_count") -Default 0)
$refreshRequiredCount = [int](Get-OptionalNumber -Object $qdmSummary -Names @("refresh_required_count") -Default 0)
$serverTailBridgeRequiredCount = [int](Get-OptionalNumber -Object $qdmSummary -Names @("server_tail_bridge_required_count") -Default 0)
$retrainRequiredCount = [int](Get-OptionalNumber -Object $qdmSummary -Names @("retrain_required_count") -Default 0)
$candidateGapCount = [int](Get-OptionalNumber -Object $learningSourceSummary -Names @("candidate_gap_count") -Default 0)
$runtimeWithoutOutcomeCount = [int](Get-OptionalNumber -Object $learningSourceSummary -Names @("runtime_without_outcome_count") -Default 0)

$strengths = New-Object System.Collections.Generic.List[string]
$limitations = New-Object System.Collections.Generic.List[string]
$recommendations = New-Object System.Collections.Generic.List[string]

if ($datasetRows -ge 1000000) {
    $strengths.Add("Model pracuje na bardzo duzym zbiorze i skaluje sie do milionow wierszy.") | Out-Null
}
if ($supportsSparseCategorical) {
    $strengths.Add("Model dobrze obsluguje mieszanke cech kategorycznych i liczbowych przy rzadkiej reprezentacji.") | Out-Null
}
if ($supportsOnnxExport) {
    $strengths.Add("Model mozna eksportowac do formatu wykorzystywanego przez srodowisko wykonawcze.") | Out-Null
}
if ($usesServerPing -and $usesServerLatency -and $usesRuntimeLatency) {
    $strengths.Add("Trening uwzglednia opoznienie wykonania i ping serwerowy zamiast lokalnych warunkow laptopa.") | Out-Null
}
if ($balancedAccuracy -gt 0.8 -and $rocAuc -gt 0.9) {
    $strengths.Add("Biezace metryki holdout pokazuja, ze model bazowy dobrze rozroznia sygnaly dodatnie i ujemne.") | Out-Null
}

if ($usesBrokerNetTarget) {
    $strengths.Add("Model trenuje juz na rachunkowym wyniku netto brokera zamiast na uproszczonym targetcie accepted.") | Out-Null
}
else {
    $limitations.Add("Model trenuje glownie target akceptacji decyzji, a nie jeszcze pelny wynik netto rachunku po brokerze.") | Out-Null
}
if ($qdmCoverageRatio -lt 0.5) {
    $limitations.Add(("Pokrycie danych kupionych w ostatnio przetrenowanym modelu jest nadal niskie ({0:P2})." -f $qdmCoverageRatio)) | Out-Null
}
if ($refreshRequiredCount -gt 0) {
    $limitations.Add("Czesc instrumentow ma dane kupione starsze niz okno aktualnych kandydatow, wiec model globalny widzi tylko fragment prawdy rynkowej.") | Out-Null
}
if ($serverTailBridgeRequiredCount -gt 0) {
    $limitations.Add("Czesc instrumentow ma juz prawie pelny ogon danych, ale wciaz brakuje biezacego ogona dnia z serwera lub brokera, wiec laptop nie jest jeszcze lustrzanym obrazem srodowiska wykonawczego.") | Out-Null
}
if ($candidateGapCount -gt 0) {
    $limitations.Add("Czesc instrumentow nadal nie produkuje kandydatow mimo gotowych danych historycznych.") | Out-Null
}
if ($runtimeWithoutOutcomeCount -gt 0) {
    $limitations.Add("Wiekszosc runtime malych modeli nadal nie ma domknietego wyniku rynku, przez co lokalna nauka nie zamyka pelnej petli.") | Out-Null
}
if (-not $paperTracksCommission -or -not $paperTracksSwap -or -not $paperTracksBrokerNetPnl) {
    $limitations.Add("Tor papierowy nie liczy jeszcze pelnego wyniku rachunkowego netto brokera w zlotowkach.") | Out-Null
}
if (-not $precheckModelsCommission -or -not $precheckModelsSlippage) {
    $limitations.Add("Kontrola wejscia nadal nie modeluje pelnego kosztu brokera z wymagana dokladnoscia.") | Out-Null
}

$recommendations.Add("Zostawic obecny model jako szybki model bramkujacy i nauczyciela bazowego dla calej floty.") | Out-Null
if ($refreshRequiredCount -gt 0 -or $serverTailBridgeRequiredCount -gt 0) {
    $recommendations.Add("Najpierw domknac brakujace lub niepelne okna danych kupionych, bo bez tego retrening globalny bylby polowiczny.") | Out-Null
}
if ($retrainRequiredCount -gt 0) {
    $recommendations.Add("Po domknieciu danych przetrenowac model globalny ponownie dla symboli, ktore kontrakt juz widzi, ale model jeszcze nie.") | Out-Null
}
if ($candidateGapCount -gt 0) {
    $recommendations.Add("Rozebrac strategie i progi dla symboli bez kandydatow, bo same dane historyczne nie przechodza tam jeszcze do nauki decyzyjnej.") | Out-Null
}
if ($runtimeWithoutOutcomeCount -gt 0) {
    $recommendations.Add("Domknac sprzezenie zwrotne outcome dla malych modeli, zeby lokalna nauka przestala byc tylko obserwacja.") | Out-Null
}
$recommendations.Add("Dodac rachunkowy wynik netto brokera w PLN jako docelowy sygnal nauki, zamiast opierac sie tylko na etykiecie accepted.") | Out-Null
$recommendations.Add("Dopiero po domknieciu kosztow brokera i sprzezenia zwrotnego outcome rozwazac drugi, bogatszy model rankingowy jako warstwe druga.") | Out-Null

$verdict = if (
    $modelFamily -eq "SGDClassifier" -and
    $supportsOnnxExport -and
    $supportsSparseCategorical -and
    $usesServerPing -and
    $usesServerLatency -and
    $usesRuntimeLatency
) {
    if (
        $qdmCoverageRatio -ge 0.5 -and
        $refreshRequiredCount -eq 0 -and
        $retrainRequiredCount -eq 0 -and
        $paperTracksCommission -and
        $paperTracksSwap -and
        $paperTracksBrokerNetPnl
    ) {
        "MODEL_BAZOWY_GOTOWY_DO_DALSZEGO_STROJENIA"
    }
    else {
        "DOBRY_MODEL_BAZOWY_ALE_NIE_DOCELOWY"
    }
}
else {
    "MODEL_WYMAGA_NAPRAWY_POD_SKALPING"
}

$dlategoZe = switch ($verdict) {
    "MODEL_BAZOWY_GOTOWY_DO_DALSZEGO_STROJENIA" {
        "Model bazowy jest zgodny z wymaganiami szybkiego skalpingu i ma juz domkniete najwazniejsze zaleznosci treningowe."
    }
    "DOBRY_MODEL_BAZOWY_ALE_NIE_DOCELOWY" {
        "Obecny model dobrze nadaje sie jako szybka bramka dla milionow wierszy i eksportu ONNX, ale nadal nie uczy sie jeszcze na pelnym wyniku netto brokera i nie ma domknietego outcome dla wiekszosci lokalnych modeli."
    }
    default {
        "Obecny model nie ma jeszcze kompletu cech potrzebnych do wiarygodnego treningu pod realne warunki skalpingowe."
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    research_root = $ResearchRoot
    verdict = $verdict
    dlatego_ze = $dlategoZe
    summary = [ordered]@{
        model_family = $modelFamily
        model_role = "SZYBKI_MODEL_BRAMKUJACY"
        training_target = if ($usesBrokerNetTarget) { "net_pln_broker" } elseif ($usesAcceptedTarget) { "accepted" } else { "unknown" }
        dataset_rows = $datasetRows
        balanced_accuracy = $balancedAccuracy
        roc_auc = $rocAuc
        qdm_coverage_ratio = $qdmCoverageRatio
        current_contract_qdm_visible_symbols_count = $currentVisibleCount
        trained_global_qdm_visible_symbols_count = $trainedVisibleSymbols.Count
        refresh_required_count = $refreshRequiredCount
        server_tail_bridge_required_count = $serverTailBridgeRequiredCount
        retrain_required_count = $retrainRequiredCount
        candidate_gap_count = $candidateGapCount
        runtime_without_outcome_count = $runtimeWithoutOutcomeCount
        uses_server_ping = $usesServerPing
        uses_server_latency = $usesServerLatency
        uses_runtime_latency = $usesRuntimeLatency
        supports_onnx_export = $supportsOnnxExport
        supports_sparse_categorical = $supportsSparseCategorical
        research_env_ready = $researchEnvReady
        paper_tracks_spread = $paperTracksSpread
        precheck_models_slippage = $precheckModelsSlippage
        precheck_models_commission = $precheckModelsCommission
        paper_tracks_commission = $paperTracksCommission
        paper_tracks_swap = $paperTracksSwap
        broker_net_pln_ready = ($paperTracksCommission -and $paperTracksSwap -and $paperTracksBrokerNetPnl)
    }
    strengths = @($strengths)
    limitations = @($limitations)
    recommendations = @($recommendations)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
