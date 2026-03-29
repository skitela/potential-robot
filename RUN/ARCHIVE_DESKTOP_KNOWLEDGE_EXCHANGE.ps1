[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$BaseDir = "C:\Users\skite\Desktop\strojenie agenta",
    [int]$KeepLastDays = 1,
    [string]$ArchiveRootName = "ARCHIWUM_WIEDZY",
    [string[]]$ExcludeNames = @("orchestrator_mailbox", "ARCHIWUM_WIEDZY"),
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $Payload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $BaseDir)) {
    throw "Missing desktop exchange directory: $BaseDir"
}

$resolvedBaseDir = (Resolve-Path -LiteralPath $BaseDir).Path
$archiveRoot = Join-Path $resolvedBaseDir $ArchiveRootName
Ensure-Directory -Path $archiveRoot

$cutoff = (Get-Date).AddDays(-1 * $KeepLastDays)
$sessionName = Get-Date -Format "yyyyMMdd_HHmmss"
$archiveSessionDir = Join-Path $archiveRoot $sessionName

$allItems = @(
    Get-ChildItem -LiteralPath $resolvedBaseDir -Force |
        Where-Object { $ExcludeNames -notcontains $_.Name }
)

$archiveCandidates = @(
    $allItems | Where-Object { $_.LastWriteTime -lt $cutoff }
)

$keptItems = @(
    $allItems | Where-Object { $_.LastWriteTime -ge $cutoff }
)

$movedRows = @()
if (@($archiveCandidates).Count -gt 0) {
    Ensure-Directory -Path $archiveSessionDir
}

foreach ($item in $archiveCandidates) {
    $destination = Join-Path $archiveSessionDir $item.Name
    if ($PSCmdlet.ShouldProcess($item.FullName, "Move to archive session $archiveSessionDir")) {
        Move-Item -LiteralPath $item.FullName -Destination $destination -Force
        $movedRows += [pscustomobject]@{
            name = $item.Name
            source_path = $item.FullName
            destination_path = $destination
            item_type = if ($item.PSIsContainer) { "directory" } else { "file" }
            last_write_time = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

$archiveSessionDirValue = ""
if (@($archiveCandidates).Count -gt 0) {
    $archiveSessionDirValue = $archiveSessionDir
}

$excludeNamesList = @($ExcludeNames)
$movedItemsList = @($movedRows)
$movedCount = @($movedRows).Count
$keptRecentCount = @($keptItems).Count

$report = [ordered]@{
    schema_version = "1.0"
    kind = "desktop_knowledge_archive"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    base_dir = $resolvedBaseDir
    archive_root = $archiveRoot
    archive_session_dir = $archiveSessionDirValue
    keep_last_days = $KeepLastDays
    cutoff_local = $cutoff.ToString("yyyy-MM-dd HH:mm:ss")
    exclude_names = $excludeNamesList
    moved_count = $movedCount
    kept_recent_count = $keptRecentCount
    moved_items = $movedItemsList
}

$jsonPath = Join-Path $resolvedBaseDir "desktop_knowledge_archive_latest.json"
$mdPath = Join-Path $resolvedBaseDir "desktop_knowledge_archive_latest.md"
Write-JsonFile -Path $jsonPath -Payload $report

$mdLines = New-Object System.Collections.Generic.List[string]
$mdLines.Add("# Archiwum wiedzy z pulpitu")
$mdLines.Add("")
$mdLines.Add(("Wygenerowano: {0}" -f $report.generated_at_local))
$mdLines.Add(("Katalog bazowy: {0}" -f $resolvedBaseDir))
$mdLines.Add(("Archiwum: {0}" -f $archiveRoot))
$mdLines.Add(("Sesja archiwum: {0}" -f $(if ([string]::IsNullOrWhiteSpace([string]$report.archive_session_dir)) { "brak ruchu" } else { [string]$report.archive_session_dir })))
$mdLines.Add(("Okno pozostawienia: ostatnie {0} dni" -f $KeepLastDays))
$mdLines.Add(("Granica czasu: {0}" -f $report.cutoff_local))
$mdLines.Add(("Wykluczenia: {0}" -f ($ExcludeNames -join ", ")))
$mdLines.Add(("Przeniesiono: {0}" -f $report.moved_count))
$mdLines.Add(("Pozostawiono jako swieze: {0}" -f $report.kept_recent_count))
$mdLines.Add("")
$mdLines.Add("## Przeniesione elementy")
if (@($movedRows).Count -eq 0) {
    $mdLines.Add("- brak")
}
else {
    foreach ($row in @($movedRows)) {
        $mdLines.Add(("- {0} -> {1}" -f [string]$row.source_path, [string]$row.destination_path))
    }
}
$mdLines | Set-Content -LiteralPath $mdPath -Encoding UTF8

if ($AsJson) {
    $report | ConvertTo-Json -Depth 30
    return
}

[pscustomobject]@{
    base_dir = $resolvedBaseDir
    archive_session_dir = $report.archive_session_dir
    moved_count = $report.moved_count
    kept_recent_count = $report.kept_recent_count
    json_report = $jsonPath
    md_report = $mdPath
} | Format-List
