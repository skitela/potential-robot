param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [int]$KeepLatestRefreshLogs = 48,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-DirectoryIfMissing {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

New-DirectoryIfMissing -Path (Join-Path $ProjectRoot "EVIDENCE\OPS")

$reportsRoot = Join-Path $ResearchRoot "reports"
$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$jsonPath = Join-Path $opsRoot "learning_path_hygiene_latest.json"
$mdPath = Join-Path $opsRoot "learning_path_hygiene_latest.md"

$manifestPath = Join-Path $reportsRoot "research_export_manifest_latest.json"
$manifestExists = Test-Path -LiteralPath $manifestPath
$manifestItem = if ($manifestExists) { Get-Item -LiteralPath $manifestPath } else { $null }
$manifestFreshThresholdSeconds = 1800
$manifestAgeSeconds = if ($manifestExists) {
    [int][Math]::Round(((Get-Date) - $manifestItem.LastWriteTime).TotalSeconds)
}
else {
    $null
}
$manifestFresh = ($manifestExists -and $manifestAgeSeconds -le $manifestFreshThresholdSeconds)

$refreshLogs = @()
if (Test-Path -LiteralPath $reportsRoot) {
    $refreshLogs = @(
        Get-ChildItem -LiteralPath $reportsRoot -File -Filter "refresh_and_train_ml_*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
}

$keepCount = [Math]::Max(1, $KeepLatestRefreshLogs)
$retained = @($refreshLogs | Select-Object -First $keepCount)
$archiveCandidates = @()
if ($refreshLogs.Count -gt $keepCount) {
    $archiveCandidates = @($refreshLogs | Select-Object -Skip $keepCount)
}

$archived = New-Object System.Collections.Generic.List[object]
if ($Apply -and $archiveCandidates.Count -gt 0) {
    $archiveRoot = Join-Path $reportsRoot "archive\refresh_and_train_ml"
    New-DirectoryIfMissing -Path $archiveRoot

    foreach ($file in $archiveCandidates) {
        $dayDir = Join-Path $archiveRoot $file.LastWriteTime.ToString("yyyyMMdd")
        New-DirectoryIfMissing -Path $dayDir
        $targetPath = Join-Path $dayDir $file.Name
        Move-Item -LiteralPath $file.FullName -Destination $targetPath -Force

        $archived.Add([pscustomobject]@{
            source_path = $file.FullName
            archive_path = $targetPath
            size_kb = [math]::Round($file.Length / 1KB, 2)
            last_write_local = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }) | Out-Null
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    research_root = $ResearchRoot
    apply_mode = [bool]$Apply
    manifest = [ordered]@{
        path = $manifestPath
        exists = $manifestExists
        age_seconds = $manifestAgeSeconds
        threshold_seconds = $manifestFreshThresholdSeconds
        fresh = $manifestFresh
    }
    refresh_and_train_logs = [ordered]@{
        total_count = $refreshLogs.Count
        keep_latest_count = $keepCount
        archive_candidate_count = $archiveCandidates.Count
        archived_count = $archived.Count
        retained_latest = @($retained | Select-Object -First 10 | ForEach-Object {
            [pscustomobject]@{
                name = $_.Name
                size_kb = [math]::Round($_.Length / 1KB, 2)
                last_write_local = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        })
        archived = @($archived.ToArray())
    }
    verdict = if ($manifestFresh -and $archiveCandidates.Count -eq 0) {
        "CZYSTO"
    }
    elseif ($manifestFresh) {
        "WYMAGA_HIGIENY_LOGOW"
    }
    else {
        "WYMAGA_ODSWIEZENIA_MANIFESTU"
    }
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Higiena Sciezki Uczenia")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- apply_mode: {0}" -f ([string]$report.apply_mode).ToLowerInvariant()))
$lines.Add("")
$lines.Add("## Manifest")
$lines.Add("")
$lines.Add(("- exists: {0}" -f $report.manifest.exists))
$lines.Add(("- fresh: {0}" -f $report.manifest.fresh))
$lines.Add(("- age_seconds: {0}" -f $report.manifest.age_seconds))
$lines.Add(("- threshold_seconds: {0}" -f $report.manifest.threshold_seconds))
$lines.Add("")
$lines.Add("## Refresh And Train Logs")
$lines.Add("")
$lines.Add(("- total_count: {0}" -f $report.refresh_and_train_logs.total_count))
$lines.Add(("- keep_latest_count: {0}" -f $report.refresh_and_train_logs.keep_latest_count))
$lines.Add(("- archive_candidate_count: {0}" -f $report.refresh_and_train_logs.archive_candidate_count))
$lines.Add(("- archived_count: {0}" -f $report.refresh_and_train_logs.archived_count))
$lines.Add("")

if ($report.refresh_and_train_logs.retained_latest.Count -gt 0) {
    $lines.Add("## Latest Retained Logs")
    $lines.Add("")
    foreach ($item in $report.refresh_and_train_logs.retained_latest) {
        $lines.Add(("- {0} | {1} KB | {2}" -f $item.name, $item.size_kb, $item.last_write_local))
    }
    $lines.Add("")
}

if ($report.refresh_and_train_logs.archived.Count -gt 0) {
    $lines.Add("## Archived This Run")
    $lines.Add("")
    foreach ($item in $report.refresh_and_train_logs.archived) {
        $lines.Add(("- {0} -> {1}" -f $item.source_path, $item.archive_path))
    }
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
