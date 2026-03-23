param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Symbol = "EURUSD",
    [string]$TrainerScript = "C:\MAKRO_I_MIKRO_BOT\RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1",
    [string]$OutputRoot = "C:\TRADING_DATA\RESEARCH\models\runtime_onnx",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "Light"
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

function Join-StringArray {
    param(
        [object[]]$Values
    )

    return (@($Values | ForEach-Object { [string]$_ }) -join '|')
}

function Convert-RuntimeManifestToContractLines {
    param(
        [object]$Manifest
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("type,key,value")
    $lines.Add(("meta,schema_version,{0}" -f ([string](Get-SafeObjectValue -Object $Manifest -PropertyName 'schema_version' -Default '1.0'))))
    $lines.Add(("meta,symbol,{0}" -f ([string](Get-SafeObjectValue -Object $Manifest -PropertyName 'symbol' -Default 'UNKNOWN'))))
    $lines.Add(("meta,feature_count,{0}" -f (@(Get-SafeObjectValue -Object $Manifest -PropertyName 'feature_names' -Default @()).Count)))
    $lines.Add(("meta,teacher_feature_enabled,{0}" -f $(if ([bool](Get-SafeObjectValue -Object $Manifest -PropertyName 'teacher_feature_enabled' -Default $false)) { "1" } else { "0" })))
    $lines.Add(("list,feature_names,{0}" -f (Join-StringArray -Values @(Get-SafeObjectValue -Object $Manifest -PropertyName 'feature_names' -Default @()))))
    $lines.Add(("list,categorical_features,{0}" -f (Join-StringArray -Values @(Get-SafeObjectValue -Object $Manifest -PropertyName 'categorical_features' -Default @()))))
    $lines.Add(("list,numeric_float_features,{0}" -f (Join-StringArray -Values @(Get-SafeObjectValue -Object $Manifest -PropertyName 'numeric_float_features' -Default @()))))
    $lines.Add(("list,numeric_int_features,{0}" -f (Join-StringArray -Values @(Get-SafeObjectValue -Object $Manifest -PropertyName 'numeric_int_features' -Default @()))))

    $categoryMaps = Get-SafeObjectValue -Object $Manifest -PropertyName 'category_maps' -Default $null
    if ($null -ne $categoryMaps) {
        foreach ($property in $categoryMaps.PSObject.Properties) {
            $pairs = New-Object System.Collections.Generic.List[string]
            foreach ($categoryProperty in $property.Value.PSObject.Properties) {
                $pairs.Add(("{0}={1}" -f [string]$categoryProperty.Name, [string]$categoryProperty.Value))
            }
            $lines.Add(("map,{0},{1}" -f [string]$property.Name, ($pairs -join '|')))
        }
    }

    return $lines
}

function Write-RuntimeContractCsv {
    param(
        [string]$ManifestPath,
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Runtime manifest not found for contract export: $ManifestPath"
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lines = Convert-RuntimeManifestToContractLines -Manifest $manifest
    ($lines -join "`r`n") | Set-Content -LiteralPath $TargetPath -Encoding ASCII
}

$symbolKey = $Symbol.Trim().ToUpperInvariant()
$artifactToken = ($symbolKey -replace '[^A-Za-z0-9]+', '_')
$symbolOutputRoot = Join-Path $OutputRoot $symbolKey
$artifactStem = "paper_gate_acceptor_{0}_latest" -f $artifactToken
$runtimeArtifactStem = "paper_gate_acceptor_{0}_runtime_latest" -f $artifactToken
$globalOutputRoot = Join-Path $OutputRoot "_GLOBAL"
$globalArtifactStem = "paper_gate_acceptor_global_latest"
$globalRuntimeArtifactStem = "paper_gate_acceptor_global_runtime_latest"

New-Item -ItemType Directory -Force -Path $symbolOutputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $globalOutputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$null = & $TrainerScript `
    -OutputRoot $globalOutputRoot `
    -ArtifactStem $globalArtifactStem `
    -ExportRuntimeNumeric `
    -RuntimeOutputRoot $globalOutputRoot `
    -RuntimeArtifactStem $globalRuntimeArtifactStem `
    -PerfProfile $PerfProfile

$null = & $TrainerScript `
    -OutputRoot $symbolOutputRoot `
    -SymbolFilter $symbolKey `
    -ArtifactStem $artifactStem `
    -TeacherModelPath (Join-Path $globalOutputRoot ("{0}.joblib" -f $globalArtifactStem)) `
    -ExportRuntimeNumeric `
    -RuntimeOutputRoot $symbolOutputRoot `
    -RuntimeArtifactStem $runtimeArtifactStem `
    -PerfProfile $PerfProfile

$metricsPath = Join-Path $symbolOutputRoot ("{0}_metrics.json" -f $artifactStem)
if (-not (Test-Path -LiteralPath $metricsPath)) {
    throw "Training metrics not found: $metricsPath"
}

$metrics = Get-Content -LiteralPath $metricsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = Get-SafeObjectValue -Object $metrics -PropertyName 'runtime_numeric' -Default $null
if ($null -eq $runtime -or -not [bool](Get-SafeObjectValue -Object $runtime -PropertyName 'enabled' -Default $false)) {
    throw "Runtime numeric ONNX was not generated for $symbolKey"
}

$targetKeyDir = Join-Path (Join-Path $CommonRoot "key") $symbolKey
New-Item -ItemType Directory -Force -Path $targetKeyDir | Out-Null

$runtimeOnnxSource = [string](Get-SafeObjectValue -Object $runtime -PropertyName 'onnx_path' -Default '')
$runtimeManifestSource = [string](Get-SafeObjectValue -Object $runtime -PropertyName 'manifest_path' -Default '')
$runtimeMetricsSource = [string](Get-SafeObjectValue -Object $runtime -PropertyName 'metrics_path' -Default '')

if (-not (Test-Path -LiteralPath $runtimeOnnxSource)) {
    throw "Runtime ONNX not found: $runtimeOnnxSource"
}
if (-not (Test-Path -LiteralPath $runtimeManifestSource)) {
    throw "Runtime manifest not found: $runtimeManifestSource"
}
if (-not (Test-Path -LiteralPath $runtimeMetricsSource)) {
    throw "Runtime metrics not found: $runtimeMetricsSource"
}

$runtimeOnnxTarget = Join-Path $targetKeyDir "paper_gate_acceptor_runtime_latest.onnx"
$runtimeManifestTarget = Join-Path $targetKeyDir "paper_gate_acceptor_runtime_manifest_latest.json"
$runtimeMetricsTarget = Join-Path $targetKeyDir "paper_gate_acceptor_runtime_metrics_latest.json"
$runtimeContractTarget = Join-Path $targetKeyDir "paper_gate_acceptor_runtime_contract_latest.csv"

Copy-Item -LiteralPath $runtimeOnnxSource -Destination $runtimeOnnxTarget -Force
Copy-Item -LiteralPath $runtimeManifestSource -Destination $runtimeManifestTarget -Force
Copy-Item -LiteralPath $runtimeMetricsSource -Destination $runtimeMetricsTarget -Force
Write-RuntimeContractCsv -ManifestPath $runtimeManifestTarget -TargetPath $runtimeContractTarget

$globalTargetKeyDir = Join-Path (Join-Path $CommonRoot "key") "_GLOBAL"
New-Item -ItemType Directory -Force -Path $globalTargetKeyDir | Out-Null
$globalMetricsPath = Join-Path $globalOutputRoot ("{0}_metrics.json" -f $globalArtifactStem)
if (-not (Test-Path -LiteralPath $globalMetricsPath)) {
    throw "Global training metrics not found: $globalMetricsPath"
}
$globalMetrics = Get-Content -LiteralPath $globalMetricsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$globalRuntime = Get-SafeObjectValue -Object $globalMetrics -PropertyName 'runtime_numeric' -Default $null
if ($null -eq $globalRuntime -or -not [bool](Get-SafeObjectValue -Object $globalRuntime -PropertyName 'enabled' -Default $false)) {
    throw "Global runtime numeric ONNX was not generated"
}

$globalRuntimeOnnxSource = [string](Get-SafeObjectValue -Object $globalRuntime -PropertyName 'onnx_path' -Default '')
$globalRuntimeManifestSource = [string](Get-SafeObjectValue -Object $globalRuntime -PropertyName 'manifest_path' -Default '')
$globalRuntimeMetricsSource = [string](Get-SafeObjectValue -Object $globalRuntime -PropertyName 'metrics_path' -Default '')

$globalRuntimeOnnxTarget = Join-Path $globalTargetKeyDir "paper_gate_acceptor_runtime_latest.onnx"
$globalRuntimeManifestTarget = Join-Path $globalTargetKeyDir "paper_gate_acceptor_runtime_manifest_latest.json"
$globalRuntimeMetricsTarget = Join-Path $globalTargetKeyDir "paper_gate_acceptor_runtime_metrics_latest.json"
$globalRuntimeContractTarget = Join-Path $globalTargetKeyDir "paper_gate_acceptor_runtime_contract_latest.csv"

Copy-Item -LiteralPath $globalRuntimeOnnxSource -Destination $globalRuntimeOnnxTarget -Force
Copy-Item -LiteralPath $globalRuntimeManifestSource -Destination $globalRuntimeManifestTarget -Force
Copy-Item -LiteralPath $globalRuntimeMetricsSource -Destination $globalRuntimeMetricsTarget -Force
Write-RuntimeContractCsv -ManifestPath $globalRuntimeManifestTarget -TargetPath $globalRuntimeContractTarget

$report = [pscustomobject]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    symbol = $symbolKey
    status = "RUNTIME_ONNX_PILOT_READY"
    common_key_dir = $targetKeyDir
    runtime_onnx_target = $runtimeOnnxTarget
    runtime_manifest_target = $runtimeManifestTarget
    runtime_metrics_target = $runtimeMetricsTarget
    runtime_contract_target = $runtimeContractTarget
    global_key_dir = $globalTargetKeyDir
    global_runtime_onnx_target = $globalRuntimeOnnxTarget
    global_runtime_manifest_target = $globalRuntimeManifestTarget
    global_runtime_metrics_target = $globalRuntimeMetricsTarget
    global_runtime_contract_target = $globalRuntimeContractTarget
    feature_count = [int](Get-SafeObjectValue -Object $runtime -PropertyName 'feature_count' -Default 0)
    runtime_roc_auc = [double](Get-SafeObjectValue -Object (Get-SafeObjectValue -Object $runtime -PropertyName 'metrics' -Default $null) -PropertyName 'roc_auc' -Default 0.0)
    runtime_balanced_accuracy = [double](Get-SafeObjectValue -Object (Get-SafeObjectValue -Object $runtime -PropertyName 'metrics' -Default $null) -PropertyName 'balanced_accuracy' -Default 0.0)
}

$jsonLatest = Join-Path $EvidenceDir "runtime_onnx_pilot_latest.json"
$mdLatest = Join-Path $EvidenceDir "runtime_onnx_pilot_latest.md"
$jsonSymbolLatest = Join-Path $EvidenceDir ("runtime_onnx_pilot_{0}_latest.json" -f $artifactToken)
$mdSymbolLatest = Join-Path $EvidenceDir ("runtime_onnx_pilot_{0}_latest.md" -f $artifactToken)

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonSymbolLatest -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Runtime ONNX Pilot")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- symbol: {0}" -f $report.symbol))
$lines.Add(("- status: {0}" -f $report.status))
$lines.Add(("- liczba cech: {0}" -f $report.feature_count))
$lines.Add(("- pole pod krzywa ROC: {0:N4}" -f $report.runtime_roc_auc))
$lines.Add(("- trafnosc zbalansowana: {0:N4}" -f $report.runtime_balanced_accuracy))
$lines.Add(("- katalog klucza: {0}" -f $report.common_key_dir))
$lines.Add(("- onnx: {0}" -f $report.runtime_onnx_target))
$lines.Add(("- manifest: {0}" -f $report.runtime_manifest_target))
$lines.Add(("- metryki: {0}" -f $report.runtime_metrics_target))
$lines.Add(("- kontrakt: {0}" -f $report.runtime_contract_target))
$lines.Add(("- nauczyciel globalny onnx: {0}" -f $report.global_runtime_onnx_target))
$lines.Add(("- nauczyciel globalny kontrakt: {0}" -f $report.global_runtime_contract_target))
($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdSymbolLatest -Encoding UTF8

$report
