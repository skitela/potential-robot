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

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$metricsPath = Join-Path $ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json"
$learningSourceAuditPath = Join-Path $opsRoot "learning_source_audit_latest.json"
$qdmVisibilityRefreshPath = Join-Path $opsRoot "qdm_visibility_refresh_profile_latest.json"
$trainingScriptPath = Join-Path $ProjectRoot "TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py"
$paperTradingPath = Join-Path $ProjectRoot "MQL5\Include\Core\MbPaperTrading.mqh"
$executionPrecheckPath = Join-Path $ProjectRoot "MQL5\Include\Core\MbExecutionPrecheck.mqh"
$researchPythonPath = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
$jsonPath = Join-Path $opsRoot "ml_scalping_fit_audit_latest.json"

$metrics = Read-JsonSafe -Path $metricsPath
$learningSourceAudit = Read-JsonSafe -Path $learningSourceAuditPath
$qdmVisibilityRefresh = Read-JsonSafe -Path $qdmVisibilityRefreshPath
$trainingScriptText = Read-TextSafe -Path $trainingScriptPath
$paperTradingText = Read-TextSafe -Path $paperTradingPath
$executionPrecheckText = Read-TextSafe -Path $executionPrecheckPath

$modelFamily = if ($trainingScriptText -match "\bSGDClassifier\b") { "SGDClassifier" } else { "UNKNOWN" }
$usesAcceptedTarget = $trainingScriptText -match 'accepted'
$usesServerPing = $trainingScriptText -match 'server_operational_ping_ms'
$usesServerLatency = $trainingScriptText -match 'server_local_latency_us_avg' -and $trainingScriptText -match 'server_local_latency_us_max'
$usesRuntimeLatency = $trainingScriptText -match 'runtime_latency_us'
$supportsOnnxExport = $trainingScriptText -match 'convert_sklearn' -and $trainingScriptText -match 'export_onnx_model'
$supportsSparseCategorical = $trainingScriptText -match 'OneHotEncoder' -and $trainingScriptText -match 'StandardScaler'
$researchEnvReady = Test-Path -LiteralPath $researchPythonPath
$paperTracksSpread = $paperTradingText -match 'opened_spread_points'
$paperTracksCommission = $paperTradingText -match 'commission'
$paperTracksSwap = $paperTradingText -match 'swap'
$paperTracksBrokerNetPnl = $paperTradingText -match 'netto' -or $paperTradingText -match 'net_pnl' -or $paperTradingText -match 'account_currency'
$precheckModelsSlippage = $executionPrecheckText -match 'modeled_slippage_points'
$precheckModelsCommission = $executionPrecheckText -match 'modeled_commission_points'

$datasetRows = if ($null -ne $metrics) { [int64]$metrics.dataset.total_rows } else { 0 }
$qdmCoverageRatio = if ($null -ne $metrics) { [double]$metrics.dataset.qdm_coverage.row_coverage_ratio } else { 0.0 }
$balancedAccuracy = if ($null -ne $metrics) { [double]$metrics.metrics.balanced_accuracy } else { 0.0 }
$rocAuc = if ($null -ne $metrics) { [double]$metrics.metrics.roc_auc } else { 0.0 }
$trainedVisibleSymbols = if ($null -ne $metrics) { @($metrics.dataset.qdm_coverage.symbols_with_qdm) } else { @() }
$currentVisibleCount = if ($null -ne $qdmVisibilityRefresh) { [int]$qdmVisibilityRefresh.summary.current_contract_qdm_visible_symbols_count } else { 0 }
$refreshRequiredCount = if ($null -ne $qdmVisibilityRefresh) { [int]$qdmVisibilityRefresh.summary.refresh_required_count } else { 0 }
$retrainRequiredCount = if ($null -ne $qdmVisibilityRefresh) { [int]$qdmVisibilityRefresh.summary.retrain_required_count } else { 0 }
$candidateGapCount = if ($null -ne $learningSourceAudit) { [int]$learningSourceAudit.summary.candidate_gap_count } else { 0 }
$runtimeWithoutOutcomeCount = if ($null -ne $learningSourceAudit) { [int]$learningSourceAudit.summary.runtime_without_outcome_count } else { 0 }

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

if (-not $usesAcceptedTarget) {
    $limitations.Add("Model nie ma jawnego targetu akceptacji decyzji i wymaga sprawdzenia etykiet.") | Out-Null
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
$recommendations.Add("Najpierw domknac swiezy ogon danych kupionych dla GOLD, SILVER i US500, bo bez tego retrening globalny bylby polowiczny.") | Out-Null
$recommendations.Add("Po domknieciu danych przetrenowac model globalny ponownie dla symboli, ktore kontrakt juz widzi, ale model jeszcze nie.") | Out-Null
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
        "Obecny model dobrze nadaje sie jako szybka bramka dla milionow wierszy i eksportu ONNX, ale nadal nie widzi calego kupionego zestawu danych ani nie uczy sie jeszcze na pelnym wyniku netto brokera."
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
        training_target = if ($usesAcceptedTarget) { "accepted" } else { "unknown" }
        dataset_rows = $datasetRows
        balanced_accuracy = $balancedAccuracy
        roc_auc = $rocAuc
        qdm_coverage_ratio = $qdmCoverageRatio
        current_contract_qdm_visible_symbols_count = $currentVisibleCount
        trained_global_qdm_visible_symbols_count = $trainedVisibleSymbols.Count
        refresh_required_count = $refreshRequiredCount
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
