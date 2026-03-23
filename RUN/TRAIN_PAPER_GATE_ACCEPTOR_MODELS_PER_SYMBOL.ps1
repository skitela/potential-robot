param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$TrainerScript = "C:\MAKRO_I_MIKRO_BOT\RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1",
    [string]$CandidateParquetPath = "C:\TRADING_DATA\RESEARCH\datasets\candidate_signals_latest.parquet",
    [string]$QdmParquetPath = "C:\TRADING_DATA\RESEARCH\datasets\qdm_minute_bars_latest.parquet",
    [string]$TeacherModelPath = "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_latest.joblib",
    [string]$OutputRoot = "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor_by_symbol",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$MinRows = 30000,
    [int]$MinPositiveRows = 1000,
    [int]$MinNegativeRows = 1000,
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "ConcurrentLab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SafeObjectValue {
    param(
        [object]$Object,
        [string]$PropertyName,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    throw "Registry not found: $RegistryPath"
}
if (-not (Test-Path -LiteralPath $TrainerScript)) {
    throw "Trainer not found: $TrainerScript"
}
if (-not (Test-Path -LiteralPath $CandidateParquetPath)) {
    throw "Candidate parquet not found: $CandidateParquetPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$symbols = @($registry.symbols | Where-Object { [string](Get-SafeObjectValue -Object $_ -PropertyName 'status' -Default '') -eq 'compiled_verified' })

$items = New-Object System.Collections.Generic.List[object]

foreach ($entry in $symbols) {
    $symbol = [string]$entry.symbol
    $sessionProfile = [string]$entry.session_profile
    $symbolOutputRoot = Join-Path $OutputRoot $symbol
    $artifactStem = "paper_gate_acceptor_{0}_latest" -f ($symbol -replace '[^A-Za-z0-9]+', '_')

    $status = "GLOBAL_FALLBACK"
    $reason = ""
    $metricsPath = Join-Path $symbolOutputRoot ("{0}_metrics.json" -f $artifactStem)
    $onnxPath = Join-Path $symbolOutputRoot ("{0}.onnx" -f $artifactStem)

    try {
        $null = & $TrainerScript `
            -CandidateParquetPath $CandidateParquetPath `
            -QdmParquetPath $QdmParquetPath `
            -OutputRoot $symbolOutputRoot `
            -SymbolFilter $symbol `
            -ArtifactStem $artifactStem `
            -TeacherModelPath $TeacherModelPath `
            -MinRows $MinRows `
            -MinPositiveRows $MinPositiveRows `
            -MinNegativeRows $MinNegativeRows `
            -PerfProfile $PerfProfile

        if ((Test-Path -LiteralPath $metricsPath) -and (Test-Path -LiteralPath $onnxPath)) {
            $metrics = Get-Content -LiteralPath $metricsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $status = "MODEL_PER_SYMBOL_READY"
            $reason = if ((Get-SafeObjectValue -Object $metrics.teacher -PropertyName 'enabled' -Default $false)) { "trained_with_global_teacher" } else { "trained" }
            $items.Add([pscustomobject]@{
                symbol = $symbol
                session_profile = $sessionProfile
                status = $status
                fallback_scope = ""
                reason = $reason
                rows_total = [int](Get-SafeObjectValue -Object $metrics.dataset -PropertyName 'total_rows' -Default 0)
                positive_rows = [int](Get-SafeObjectValue -Object $metrics.dataset -PropertyName 'positive_rows' -Default 0)
                negative_rows = [int](Get-SafeObjectValue -Object $metrics.dataset -PropertyName 'negative_rows' -Default 0)
                roc_auc = [double](Get-SafeObjectValue -Object $metrics.metrics -PropertyName 'roc_auc' -Default 0.0)
                balanced_accuracy = [double](Get-SafeObjectValue -Object $metrics.metrics -PropertyName 'balanced_accuracy' -Default 0.0)
                teacher_enabled = [bool](Get-SafeObjectValue -Object $metrics.teacher -PropertyName 'enabled' -Default $false)
                data_source = [string](Get-SafeObjectValue -Object $metrics.dataset -PropertyName 'source_kind' -Default '')
                onnx_path = $onnxPath
                metrics_path = $metricsPath
            })
            continue
        }

        $reason = "training_finished_without_artifacts"
    }
    catch {
        $reason = $_.Exception.Message
    }

    $items.Add([pscustomobject]@{
        symbol = $symbol
        session_profile = $sessionProfile
        status = $status
        fallback_scope = "GLOBAL_MODEL"
        reason = $reason
        rows_total = 0
        positive_rows = 0
        negative_rows = 0
        roc_auc = 0.0
        balanced_accuracy = 0.0
        teacher_enabled = $false
        data_source = ""
        onnx_path = $null
        metrics_path = $null
    })
}

$readyItems = @($items | Where-Object { $_.status -eq 'MODEL_PER_SYMBOL_READY' })
$fallbackItems = @($items | Where-Object { $_.status -ne 'MODEL_PER_SYMBOL_READY' })
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$itemArray = $items.ToArray()
$totalSymbols = $items.Count

$report = @{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    total_symbols = $totalSymbols
    ready_count = $readyItems.Count
    fallback_count = $fallbackItems.Count
    min_rows = $MinRows
    min_positive_rows = $MinPositiveRows
    min_negative_rows = $MinNegativeRows
    items = $itemArray
}

$jsonLatest = Join-Path $EvidenceDir "onnx_symbol_registry_latest.json"
$jsonStamped = Join-Path $EvidenceDir ("onnx_symbol_registry_{0}.json" -f $timestamp)
$mdLatest = Join-Path $EvidenceDir "onnx_symbol_registry_latest.md"
$mdStamped = Join-Path $EvidenceDir ("onnx_symbol_registry_{0}.md" -f $timestamp)

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Rejestr ONNX per instrument")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- liczba instrumentow: {0}" -f $report.total_symbols))
$lines.Add(("- gotowe modele per instrument: {0}" -f $report.ready_count))
$lines.Add(("- fallback do modelu globalnego: {0}" -f $report.fallback_count))
$lines.Add("")

foreach ($item in $items) {
    $lines.Add(("## {0}" -f $item.symbol))
    $lines.Add("")
    $lines.Add(("- status: {0}" -f $item.status))
    if ($item.fallback_scope) {
        $lines.Add(("- fallback: {0}" -f $item.fallback_scope))
    }
    $lines.Add(("- profil sesji: {0}" -f $item.session_profile))
    $lines.Add(("- wiersze: {0}" -f $item.rows_total))
    $lines.Add(("- dodatnie wiersze: {0}" -f $item.positive_rows))
    $lines.Add(("- ujemne wiersze: {0}" -f $item.negative_rows))
    if ([double]$item.roc_auc -gt 0.0) {
        $lines.Add(("- pole pod krzywa ROC: {0:N4}" -f ([double]$item.roc_auc)))
        $lines.Add(("- trafnosc zbalansowana: {0:N4}" -f ([double]$item.balanced_accuracy)))
        $lines.Add(("- nauczyciel globalny: {0}" -f $(if ($item.teacher_enabled) { "tak" } else { "nie" })))
        if (-not [string]::IsNullOrWhiteSpace([string]$item.data_source)) {
            $lines.Add(("- zrodlo danych: {0}" -f $item.data_source))
        }
        $lines.Add(("- onnx_path: {0}" -f $item.onnx_path))
    }
    $lines.Add(("- powod: {0}" -f $item.reason))
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdStamped -Encoding UTF8

$report
