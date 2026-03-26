param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$TrainerScript = "C:\MAKRO_I_MIKRO_BOT\RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1",
    [string]$CandidateParquetPath = "C:\TRADING_DATA\RESEARCH\datasets\candidate_signals_latest.parquet",
    [string]$QdmParquetPath = "C:\TRADING_DATA\RESEARCH\datasets\qdm_minute_bars_latest.parquet",
    [string]$TeacherModelPath = "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_latest.joblib",
    [string]$OutputRoot = "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor_by_symbol",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$TrainingReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_training_readiness_latest.json",
    [string]$ExistingRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string[]]$AllowedTrainingStates = @(),
    [string[]]$SymbolAllowList = @(),
    [int]$MaxSymbols = 0,
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

function Normalize-Symbol {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return $Value.Trim().ToUpperInvariant()
}

function New-MapBySymbol {
    param(
        [object[]]$Items,
        [string[]]$Keys = @("symbol", "symbol_alias")
    )

    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        foreach ($keyName in $Keys) {
            $property = $item.PSObject.Properties[$keyName]
            if ($null -eq $property) {
                continue
            }

            $symbol = Normalize-Symbol -Value ([string]$property.Value)
            if ([string]::IsNullOrWhiteSpace($symbol)) {
                continue
            }

            if (-not $map.ContainsKey($symbol)) {
                $map[$symbol] = $item
            }
        }
    }

    return $map
}

function Get-TrainingStateRank {
    param([string]$State)

    switch ($State) {
        "LOCAL_TRAINING_READY" { return 0 }
        "LOCAL_TRAINING_LIMITED" { return 1 }
        "TRAINING_SHADOW_READY" { return 2 }
        "CONTRACT_PENDING" { return 3 }
        "EXPORT_PENDING" { return 4 }
        "FALLBACK_ONLY" { return 5 }
        default { return 6 }
    }
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
$trainingReadiness = Read-JsonSafe -Path $TrainingReadinessPath
$trainingReadinessMap = if ($null -ne $trainingReadiness) { New-MapBySymbol -Items @($trainingReadiness.items) } else { @{} }
$existingRegistry = Read-JsonSafe -Path $ExistingRegistryPath
$existingRegistryMap = if ($null -ne $existingRegistry) { New-MapBySymbol -Items @($existingRegistry.items) } else { @{} }

$symbolAllowMap = @{}
foreach ($symbol in @($SymbolAllowList)) {
    $normalized = Normalize-Symbol -Value ([string]$symbol)
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        $symbolAllowMap[$normalized] = $true
    }
}

$allowedStateMap = @{}
foreach ($state in @($AllowedTrainingStates)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$state)) {
        $allowedStateMap[[string]$state] = $true
    }
}

$selectedEntries = New-Object System.Collections.Generic.List[object]
foreach ($entry in $symbols) {
    $symbol = Normalize-Symbol -Value ([string]$entry.symbol)
    if ($symbolAllowMap.Count -gt 0 -and -not $symbolAllowMap.ContainsKey($symbol)) {
        continue
    }

    if ($allowedStateMap.Count -gt 0) {
        if (-not $trainingReadinessMap.ContainsKey($symbol)) {
            continue
        }

        $trainingState = [string](Get-SafeObjectValue -Object $trainingReadinessMap[$symbol] -PropertyName 'training_readiness_state' -Default '')
        if (-not $allowedStateMap.ContainsKey($trainingState)) {
            continue
        }
    }

    $selectedEntries.Add($entry) | Out-Null
}

$selectedEntries = @(
    $selectedEntries.ToArray() |
        Sort-Object `
            @{ Expression = {
                $symbol = Normalize-Symbol -Value ([string]$_.symbol)
                if ($trainingReadinessMap.ContainsKey($symbol)) {
                    return Get-TrainingStateRank -State ([string](Get-SafeObjectValue -Object $trainingReadinessMap[$symbol] -PropertyName 'training_readiness_state' -Default ''))
                }
                return 99
            }; Ascending = $true }, `
            symbol
)

if ($MaxSymbols -gt 0) {
    $selectedEntries = @($selectedEntries | Select-Object -First $MaxSymbols)
}

$selectedSymbolMap = @{}
foreach ($entry in @($selectedEntries)) {
    $selectedSymbolMap[(Normalize-Symbol -Value ([string]$entry.symbol))] = $true
}

$items = New-Object System.Collections.Generic.List[object]
$trainedNow = New-Object System.Collections.Generic.List[string]
$fallbackNow = New-Object System.Collections.Generic.List[string]

foreach ($entry in @($selectedEntries)) {
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
            }) | Out-Null
            $trainedNow.Add($symbol) | Out-Null
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
    }) | Out-Null
    $fallbackNow.Add($symbol) | Out-Null
}

foreach ($entry in $symbols) {
    $symbol = Normalize-Symbol -Value ([string]$entry.symbol)
    if ($selectedSymbolMap.ContainsKey($symbol)) {
        continue
    }

    if ($existingRegistryMap.ContainsKey($symbol)) {
        $items.Add($existingRegistryMap[$symbol]) | Out-Null
        continue
    }

    $trainingState = if ($trainingReadinessMap.ContainsKey($symbol)) {
        [string](Get-SafeObjectValue -Object $trainingReadinessMap[$symbol] -PropertyName 'training_readiness_state' -Default '')
    }
    else {
        ""
    }

    $reason = if (-not [string]::IsNullOrWhiteSpace($trainingState)) {
        "not_selected_for_current_cycle:$trainingState"
    }
    else {
        "not_selected_for_current_cycle"
    }

    $items.Add([pscustomobject]@{
        symbol = [string]$entry.symbol
        session_profile = [string]$entry.session_profile
        status = "GLOBAL_FALLBACK"
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
    }) | Out-Null
}

$itemArray = @($items.ToArray() | Sort-Object symbol)
$readyItems = @($itemArray | Where-Object { $_.status -eq 'MODEL_PER_SYMBOL_READY' })
$fallbackItems = @($itemArray | Where-Object { $_.status -ne 'MODEL_PER_SYMBOL_READY' })
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$totalSymbols = $itemArray.Count

$report = @{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    total_symbols = $totalSymbols
    ready_count = $readyItems.Count
    fallback_count = $fallbackItems.Count
    selected_count = @($selectedEntries).Count
    selected_symbols = @($selectedEntries | ForEach-Object { [string]$_.symbol })
    trained_now_count = $trainedNow.Count
    trained_now_symbols = @($trainedNow.ToArray())
    fallback_now_count = $fallbackNow.Count
    fallback_now_symbols = @($fallbackNow.ToArray())
    allowed_training_states = @($allowedStateMap.Keys | Sort-Object)
    min_rows = $MinRows
    min_positive_rows = $MinPositiveRows
    min_negative_rows = $MinNegativeRows
    selection_mode = if ($selectedSymbolMap.Count -gt 0 -or $allowedStateMap.Count -gt 0 -or $MaxSymbols -gt 0) { "LIMITED_GUARDED" } else { "FULL_FLEET" }
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
$lines.Add(("- selection_mode: {0}" -f $report.selection_mode))
$lines.Add(("- selected_count: {0}" -f $report.selected_count))
$lines.Add(("- trained_now_count: {0}" -f $report.trained_now_count))
$lines.Add(("- fallback_now_count: {0}" -f $report.fallback_now_count))
if (@($report.allowed_training_states).Count -gt 0) {
    $lines.Add(("- allowed_training_states: {0}" -f (@($report.allowed_training_states) -join ", ")))
}
$lines.Add("")

foreach ($item in $itemArray) {
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
