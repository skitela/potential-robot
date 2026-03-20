param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$QdmHistoryRoot = "C:\TRADING_TOOLS\QuantDataManager\user\data\History",
    [string]$QdmExportRoot = "C:\TRADING_DATA\QDM_EXPORT\MT5",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FileSizeBytes {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int64]0
    }

    return [int64](Get-Item -LiteralPath $Path).Length
}

function Get-DirSizeBytes {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int64]0
    }

    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) {
        return [int64]0
    }
    return [int64]$sum
}

function Get-MeasureSum {
    param([object[]]$Items)

    if ($null -eq $Items -or $Items.Count -eq 0) {
        return [int64]0
    }

    $sum = ($Items | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) {
        return [int64]0
    }

    return [int64]$sum
}

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

function Get-Stem {
    param([string]$Name)
    return [System.IO.Path]::GetFileNameWithoutExtension($Name)
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$datasetsDir = Join-Path $ResearchRoot "datasets"
$qdmCacheDir = Join-Path $ResearchRoot "qdm_cache\minute_bars"
$manifestPath = Join-Path $ResearchRoot "reports\research_export_manifest_latest.json"
$cacheManifestPath = Join-Path $ResearchRoot "reports\qdm_cache_manifest_latest.json"
$metricsPath = Join-Path $ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json"
$duckdbPath = Join-Path $ResearchRoot "microbot_research.duckdb"

$manifest = Read-JsonFile -Path $manifestPath
$cacheManifest = Read-JsonFile -Path $cacheManifestPath
$metrics = Read-JsonFile -Path $metricsPath

$qdmHistoryBytes = Get-DirSizeBytes -Path $QdmHistoryRoot
$qdmExportCsvFiles = @(Get-ChildItem -LiteralPath $QdmExportRoot -File -Filter "MB_*.csv" -ErrorAction SilentlyContinue)
$qdmExportCsvBytes = Get-MeasureSum -Items $qdmExportCsvFiles
$qdmCacheBytes = Get-DirSizeBytes -Path $qdmCacheDir
$qdmCacheFiles = @(Get-ChildItem -LiteralPath $qdmCacheDir -File -Filter "*.parquet" -ErrorAction SilentlyContinue)
$researchCsvFiles = @(Get-ChildItem -LiteralPath $datasetsDir -File -Filter "*.csv" -ErrorAction SilentlyContinue)
$researchParquetFiles = @(Get-ChildItem -LiteralPath $datasetsDir -File -Filter "*.parquet" -ErrorAction SilentlyContinue)
$researchCsvBytes = Get-MeasureSum -Items $researchCsvFiles
$researchParquetBytes = Get-MeasureSum -Items $researchParquetFiles
$duckdbBytes = Get-FileSizeBytes -Path $duckdbPath

$exportCacheMap = @{}
if ($null -ne $cacheManifest -and $cacheManifest.PSObject.Properties.Name -contains "files") {
    foreach ($prop in $cacheManifest.files.PSObject.Properties) {
        $exportCacheMap[$prop.Name] = $prop.Value
    }
}

$redundantQdmExports = New-Object System.Collections.Generic.List[object]
foreach ($csvFile in $qdmExportCsvFiles) {
    $stem = Get-Stem -Name $csvFile.Name
    if (-not $exportCacheMap.ContainsKey($stem)) {
        continue
    }
    $cacheEntry = $exportCacheMap[$stem]
    $cachePath = [string]$cacheEntry.minute_parquet_path
    if ([string]::IsNullOrWhiteSpace($cachePath) -or -not (Test-Path -LiteralPath $cachePath)) {
        continue
    }

    $redundantQdmExports.Add([pscustomobject]@{
        export_name = $stem
        csv_path = $csvFile.FullName
        csv_size_gb = [math]::Round(([int64]$csvFile.Length / 1GB), 3)
        cache_path = $cachePath
        cache_rows = [int64]$cacheEntry.minute_rows
    })
}

$redundantResearchCsv = New-Object System.Collections.Generic.List[object]
foreach ($csvFile in $researchCsvFiles) {
    $stem = Get-Stem -Name $csvFile.Name
    $parquetPath = Join-Path $datasetsDir ($stem + ".parquet")
    if (-not (Test-Path -LiteralPath $parquetPath)) {
        continue
    }

    $redundantResearchCsv.Add([pscustomobject]@{
        dataset = $stem
        csv_path = $csvFile.FullName
        csv_size_gb = [math]::Round(([int64]$csvFile.Length / 1GB), 3)
        parquet_path = $parquetPath
    })
}

$qdmCoverageRatio = 0.0
$qdmRowsWithCoverage = 0
$qdmSymbols = @()
$qdmFeaturesUsed = @()
if ($null -ne $metrics) {
    if ($metrics.dataset.PSObject.Properties.Name -contains "qdm_coverage") {
        $qdmCoverageRatio = [double]$metrics.dataset.qdm_coverage.row_coverage_ratio
        $qdmRowsWithCoverage = [int]$metrics.dataset.qdm_coverage.rows_with_qdm
        $qdmSymbols = @($metrics.dataset.qdm_coverage.symbols_with_qdm)
    }
    $featureNames = @()
    if ($metrics.PSObject.Properties.Name -contains "top_features") {
        $featureNames += @($metrics.top_features.positive | ForEach-Object { [string]$_.feature })
        $featureNames += @($metrics.top_features.negative | ForEach-Object { [string]$_.feature })
    }
    $qdmFeaturesUsed = @($featureNames | Where-Object { $_ -like "*qdm_*" } | Select-Object -Unique)
}

$learningUsesQdm = ($qdmRowsWithCoverage -gt 0 -or $qdmFeaturesUsed.Count -gt 0)
$learningVerdict = "NO_QDM_SIGNAL"
if ($learningUsesQdm -and $qdmCoverageRatio -ge 0.10) {
    $learningVerdict = "QDM_STRONGLY_ACTIVE"
}
elseif ($learningUsesQdm -and $qdmCoverageRatio -ge 0.02) {
    $learningVerdict = "QDM_PARTIALLY_ACTIVE"
}
elseif ($learningUsesQdm) {
    $learningVerdict = "QDM_LOW_COVERAGE_ACTIVE"
}

$redundantQdmExportsSorted = @($redundantQdmExports | Sort-Object csv_size_gb -Descending)
$redundantResearchCsvSorted = @($redundantResearchCsv | Sort-Object csv_size_gb -Descending)

$report = @{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    roots = @{
        qdm_history = $QdmHistoryRoot
        qdm_export = $QdmExportRoot
        qdm_cache = $qdmCacheDir
        research = $ResearchRoot
        datasets = $datasetsDir
        duckdb = $duckdbPath
    }
    storage = @{
        qdm_history_gb = [math]::Round(($qdmHistoryBytes / 1GB), 3)
        qdm_export_csv_gb = [math]::Round(($qdmExportCsvBytes / 1GB), 3)
        qdm_cache_gb = [math]::Round(($qdmCacheBytes / 1GB), 3)
        research_csv_gb = [math]::Round(($researchCsvBytes / 1GB), 3)
        research_parquet_gb = [math]::Round(($researchParquetBytes / 1GB), 3)
        research_duckdb_gb = [math]::Round(($duckdbBytes / 1GB), 3)
    }
    qdm = @{
        export_csv_file_count = $qdmExportCsvFiles.Count
        cache_file_count = $qdmCacheFiles.Count
        redundant_export_csv = @($redundantQdmExportsSorted)
    }
    research = @{
        csv_file_count = $researchCsvFiles.Count
        parquet_file_count = $researchParquetFiles.Count
        redundant_csv = @($redundantResearchCsvSorted)
        manifest_present = ($null -ne $manifest)
        cache_manifest_present = ($null -ne $cacheManifest)
    }
    learning = @{
        verdict = $learningVerdict
        qdm_rows_with_coverage = $qdmRowsWithCoverage
        qdm_coverage_ratio = [math]::Round($qdmCoverageRatio, 6)
        qdm_symbols_with_coverage = @($qdmSymbols)
        qdm_features_visible_in_model = @($qdmFeaturesUsed)
    }
    recommendation = @{
        canonical_download_layer = "QDM raw history"
        canonical_learning_layers = @("QDM cache parquet", "Research parquet", "Research duckdb")
        can_purge_qdm_export_csv = ($redundantQdmExports.Count -eq $qdmExportCsvFiles.Count -and $qdmExportCsvFiles.Count -gt 0)
        can_purge_large_research_csv = ($redundantResearchCsv.Count -gt 0)
    }
}

$jsonPath = Join-Path $OutputRoot "learning_stack_audit_latest.json"
$mdPath = Join-Path $OutputRoot "learning_stack_audit_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Learning Stack Audit")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- learning_verdict: {0}" -f $report.learning.verdict))
$lines.Add("")
$lines.Add("## Storage")
$lines.Add("")
$lines.Add(("- qdm_history_gb: {0}" -f $report.storage.qdm_history_gb))
$lines.Add(("- qdm_export_csv_gb: {0}" -f $report.storage.qdm_export_csv_gb))
$lines.Add(("- qdm_cache_gb: {0}" -f $report.storage.qdm_cache_gb))
$lines.Add(("- research_csv_gb: {0}" -f $report.storage.research_csv_gb))
$lines.Add(("- research_parquet_gb: {0}" -f $report.storage.research_parquet_gb))
$lines.Add(("- research_duckdb_gb: {0}" -f $report.storage.research_duckdb_gb))
$lines.Add("")
$lines.Add("## QDM -> Learning")
$lines.Add("")
$lines.Add(("- qdm_rows_with_coverage: {0}" -f $report.learning.qdm_rows_with_coverage))
$lines.Add(("- qdm_coverage_ratio: {0}" -f $report.learning.qdm_coverage_ratio))
$lines.Add(("- qdm_symbols_with_coverage: {0}" -f ($(if ($report.learning.qdm_symbols_with_coverage.Count -gt 0) { ($report.learning.qdm_symbols_with_coverage -join ", ") } else { "none" }))))
$lines.Add("")
$lines.Add("## Redundant Layers")
$lines.Add("")
$lines.Add(("- redundant_qdm_export_csv_count: {0}" -f $report.qdm.redundant_export_csv.Count))
$lines.Add(("- redundant_research_csv_count: {0}" -f $report.research.redundant_csv.Count))
$lines.Add("")
$lines.Add("## Recommendation")
$lines.Add("")
$lines.Add(("- canonical_download_layer: {0}" -f $report.recommendation.canonical_download_layer))
$lines.Add(("- canonical_learning_layers: {0}" -f ($report.recommendation.canonical_learning_layers -join ", ")))
$lines.Add(("- can_purge_qdm_export_csv: {0}" -f $report.recommendation.can_purge_qdm_export_csv))
$lines.Add(("- can_purge_large_research_csv: {0}" -f $report.recommendation.can_purge_large_research_csv))
$lines.Add("")

if ($report.qdm.redundant_export_csv.Count -gt 0) {
    $lines.Add("## Largest Redundant QDM Export CSV")
    $lines.Add("")
    foreach ($item in ($report.qdm.redundant_export_csv | Sort-Object csv_size_gb -Descending | Select-Object -First 10)) {
        $lines.Add(("- {0}: {1} GB" -f $item.export_name, $item.csv_size_gb))
    }
    $lines.Add("")
}

if ($report.research.redundant_csv.Count -gt 0) {
    $lines.Add("## Largest Redundant Research CSV")
    $lines.Add("")
    foreach ($item in ($report.research.redundant_csv | Sort-Object csv_size_gb -Descending | Select-Object -First 10)) {
        $lines.Add(("- {0}: {1} GB" -f $item.dataset, $item.csv_size_gb))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report
