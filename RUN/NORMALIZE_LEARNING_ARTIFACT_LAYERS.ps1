param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$QdmExportRoot = "C:\TRADING_DATA\QDM_EXPORT\MT5",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [int]$ResearchCsvPurgeThresholdMb = 50
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

function Get-QdmRefreshPreserveSet {
    param([string]$RefreshProfilePath)

    $preserve = @{}
    $refreshProfile = Read-JsonFile -Path $RefreshProfilePath
    if ($null -eq $refreshProfile -or $null -eq $refreshProfile.PSObject.Properties["refresh_required"]) {
        return $preserve
    }

    foreach ($item in @($refreshProfile.refresh_required)) {
        if ($null -eq $item) { continue }
        $name = [string]$item.mt5_export_name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $preserve[$name.Trim().ToUpperInvariant()] = $true
    }

    return $preserve
}

$datasetsDir = Join-Path $ResearchRoot "datasets"
$cacheManifestPath = Join-Path $ResearchRoot "reports\qdm_cache_manifest_latest.json"
$refreshProfilePath = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_visibility_refresh_profile_latest.json"
$cacheManifest = Read-JsonFile -Path $cacheManifestPath
$refreshPreserveSet = Get-QdmRefreshPreserveSet -RefreshProfilePath $refreshProfilePath
$cacheFiles = @{}

if ($null -ne $cacheManifest -and $cacheManifest.PSObject.Properties.Name -contains "files") {
    foreach ($prop in $cacheManifest.files.PSObject.Properties) {
        $cacheFiles[$prop.Name] = $prop.Value
    }
}

$deletedQdmExports = New-Object System.Collections.Generic.List[object]
$deletedResearchCsv = New-Object System.Collections.Generic.List[object]
$freedBytes = [int64]0

foreach ($csvFile in @(Get-ChildItem -LiteralPath $QdmExportRoot -File -Filter "MB_*.csv" -ErrorAction SilentlyContinue)) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($csvFile.Name)
    $stemKey = $stem.Trim().ToUpperInvariant()
    if ($refreshPreserveSet.ContainsKey($stemKey)) {
        continue
    }
    if (-not $cacheFiles.ContainsKey($stem)) {
        continue
    }

    $cachePath = [string]$cacheFiles[$stem].minute_parquet_path
    if ([string]::IsNullOrWhiteSpace($cachePath) -or -not (Test-Path -LiteralPath $cachePath)) {
        continue
    }

    $sizeBytes = [int64]$csvFile.Length
    Remove-Item -LiteralPath $csvFile.FullName -Force
    $freedBytes += $sizeBytes
    $deletedQdmExports.Add([pscustomobject]@{
        export_name = $stem
        path = $csvFile.FullName
        size_gb = [math]::Round(($sizeBytes / 1GB), 3)
    })
}

$thresholdBytes = [int64]$ResearchCsvPurgeThresholdMb * 1MB
foreach ($csvFile in @(Get-ChildItem -LiteralPath $datasetsDir -File -Filter "*.csv" -ErrorAction SilentlyContinue)) {
    $parquetPath = Join-Path $datasetsDir ([System.IO.Path]::GetFileNameWithoutExtension($csvFile.Name) + ".parquet")
    if (-not (Test-Path -LiteralPath $parquetPath)) {
        continue
    }
    if ($csvFile.Length -lt $thresholdBytes) {
        continue
    }

    $sizeBytes = [int64]$csvFile.Length
    Remove-Item -LiteralPath $csvFile.FullName -Force
    $freedBytes += $sizeBytes
    $deletedResearchCsv.Add([pscustomobject]@{
        dataset = [System.IO.Path]::GetFileNameWithoutExtension($csvFile.Name)
        path = $csvFile.FullName
        size_gb = [math]::Round(($sizeBytes / 1GB), 3)
    })
}

$deletedQdmExportRows = @($deletedQdmExports | Select-Object *)
$deletedResearchCsvRows = @($deletedResearchCsv | Select-Object *)

$report = @{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    qdm_export_deleted = @($deletedQdmExportRows)
    research_csv_deleted = @($deletedResearchCsvRows)
    freed_gb_total = [math]::Round(($freedBytes / 1GB), 3)
}

$outputRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$jsonPath = Join-Path $outputRoot "learning_artifact_cleanup_latest.json"
$mdPath = Join-Path $outputRoot "learning_artifact_cleanup_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Learning Artifact Cleanup")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- freed_gb_total: {0}" -f $report.freed_gb_total))
$lines.Add(("- qdm_export_deleted_count: {0}" -f $report.qdm_export_deleted.Count))
$lines.Add(("- research_csv_deleted_count: {0}" -f $report.research_csv_deleted.Count))
$lines.Add("")
if ($report.qdm_export_deleted.Count -gt 0) {
    $lines.Add("## Deleted QDM export CSV")
    $lines.Add("")
    foreach ($item in $report.qdm_export_deleted) {
        $lines.Add(("- {0}: {1} GB" -f $item.export_name, $item.size_gb))
    }
    $lines.Add("")
}
if ($report.research_csv_deleted.Count -gt 0) {
    $lines.Add("## Deleted research CSV")
    $lines.Add("")
    foreach ($item in $report.research_csv_deleted) {
        $lines.Add(("- {0}: {1} GB" -f $item.dataset, $item.size_gb))
    }
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report
