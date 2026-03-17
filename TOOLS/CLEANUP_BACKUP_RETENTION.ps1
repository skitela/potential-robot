[CmdletBinding()]
param(
    [string]$ProjectBackupDir = "C:\MAKRO_I_MIKRO_BOT\BACKUP",
    [string]$SessionBackupDir = "C:\OANDA_MT5_SYSTEM\BACKUPS",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\BACKUP_RETENTION",
    [int]$KeepProjectFullBackups = 5,
    [int]$KeepProjectPartialSnapshots = 1,
    [int]$KeepProjectHandoffs = 3,
    [int]$KeepSessionBackups = 10,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-ZipInspection {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($File.FullName)
        try {
            $entries = $archive.Entries.Count
            $uncompressedBytes = (($archive.Entries | Measure-Object -Property Length -Sum).Sum)
        }
        finally {
            $archive.Dispose()
        }

        [pscustomobject]@{
            inspect_status      = "ok"
            entries             = $entries
            uncompressed_bytes  = [int64]$uncompressedBytes
        }
        return
    }
    catch {
        [pscustomobject]@{
            inspect_status      = "unreadable"
            entries             = $null
            uncompressed_bytes  = $null
        }
    }
}

function Get-Classification {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Inspection,
        [Parameter(Mandatory = $true)]
        [string]$ProjectBackupDir,
        [Parameter(Mandatory = $true)]
        [string]$SessionBackupDir
    )

    $fullName = [System.IO.Path]::GetFullPath($File.FullName)
    $projectRoot = [System.IO.Path]::GetFullPath($ProjectBackupDir)
    $sessionRoot = [System.IO.Path]::GetFullPath($SessionBackupDir)

    if($fullName.StartsWith($sessionRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
       $File.BaseName.StartsWith("session_", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "session_backup"
    }

    if($File.Name -match "HANDOFF") {
        return "handoff"
    }

    if($Inspection.inspect_status -ne "ok") {
        return "snapshot_czesciowy"
    }

    if($Inspection.entries -ge 500) {
        return "pelny_restore_point"
    }

    return "snapshot_czesciowy"
}

function Convert-ToHumanSize {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Bytes
    )

    if($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes / 1TB)) }
    if($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return ("{0:N0} B" -f $Bytes)
}

function Get-SafeSum {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Rows,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $items = @($Rows)
    if(-not $items -or $items.Count -eq 0) {
        return [int64]0
    }

    $measure = $items | Measure-Object -Property $PropertyName -Sum
    if($null -eq $measure -or $null -eq $measure.Sum) {
        return [int64]0
    }

    return [int64]$measure.Sum
}

function Get-TopRowsByCategory {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Rows,
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [int]$Count = 0,
        [string]$RootScope = $null
    )

    if($Count -le 0) {
        return @()
    }

    $items = @($Rows)
    $filtered = @(
        $items |
            Where-Object {
                $_.classification -eq $Category -and
                ($null -eq $RootScope -or $_.root_scope -eq $RootScope)
            } |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -First $Count
    )

    return $filtered
}

function New-ManifestSummary {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Rows,
        [Parameter(Mandatory = $true)]
        [string]$Stage
    )

    $items = @($Rows)
    $keptRows = @($items | Where-Object { $_.keep })
    $deleteRows = @($items | Where-Object { -not $_.keep })
    $deletedBytes = Get-SafeSum -Rows $deleteRows -PropertyName "length_bytes"
    $keptBytes = Get-SafeSum -Rows $keptRows -PropertyName "length_bytes"

    [pscustomobject]@{
        stage                          = $Stage
        generated_at                   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
        total_files                    = $Rows.Count
        kept_files                     = $keptRows.Count
        delete_files                   = $deleteRows.Count
        kept_bytes                     = [int64]$keptBytes
        delete_bytes                   = [int64]$deletedBytes
        kept_size_human                = Convert-ToHumanSize -Bytes $keptBytes
        delete_size_human              = Convert-ToHumanSize -Bytes $deletedBytes
        kept_by_classification         = ($keptRows | Group-Object classification | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                classification = $_.Name
                count          = $_.Count
            }
        })
        delete_by_classification       = ($deleteRows | Group-Object classification | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{
                classification = $_.Name
                count          = $_.Count
            }
        })
    }
}

if(-not (Test-Path -LiteralPath $ProjectBackupDir)) {
    throw "Project backup dir not found: $ProjectBackupDir"
}

if(-not (Test-Path -LiteralPath $SessionBackupDir)) {
    throw "Session backup dir not found: $SessionBackupDir"
}

[void](New-Item -ItemType Directory -Force -Path $EvidenceDir)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$allFiles = @(
    Get-ChildItem -LiteralPath $ProjectBackupDir -File -Filter *.zip
    Get-ChildItem -LiteralPath $SessionBackupDir -File -Filter *.zip
)

$rows = New-Object System.Collections.ArrayList
$rowIndex = 0

foreach($file in $allFiles | Sort-Object FullName) {
    $inspection = Get-ZipInspection -File $file
    $classification = Get-Classification -File $file -Inspection $inspection -ProjectBackupDir $ProjectBackupDir -SessionBackupDir $SessionBackupDir
    $rootScope = if($file.FullName.StartsWith($ProjectBackupDir, [System.StringComparison]::OrdinalIgnoreCase)) { "project_backup" } else { "session_backup" }

    $rows.Add([pscustomobject]@{
        row_index               = $rowIndex
        name                    = $file.Name
        full_path               = $file.FullName
        root_scope              = $rootScope
        classification          = $classification
        inspect_status          = $inspection.inspect_status
        entries                 = $inspection.entries
        uncompressed_bytes      = $inspection.uncompressed_bytes
        length_bytes            = [int64]$file.Length
        size_human              = Convert-ToHumanSize -Bytes $file.Length
        last_write_time         = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        LastWriteTime           = $file.LastWriteTime
        keep                    = $false
        keep_reason             = $null
        delete_reason           = $null
    }) | Out-Null
    $rowIndex += 1
}

$keepIndexes = New-Object System.Collections.Generic.HashSet[int]
$allRows = @($rows.ToArray())

$projectFullRows = @(
    $allRows |
        Where-Object { $_.root_scope -eq "project_backup" -and $_.classification -eq "pelny_restore_point" } |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First $KeepProjectFullBackups
)
$projectPartialRows = @(
    $allRows |
        Where-Object { $_.root_scope -eq "project_backup" -and $_.classification -eq "snapshot_czesciowy" } |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First $KeepProjectPartialSnapshots
)
$projectHandoffRows = @(
    $allRows |
        Where-Object { $_.root_scope -eq "project_backup" -and $_.classification -eq "handoff" } |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First $KeepProjectHandoffs
)
$sessionRows = @(
    $allRows |
        Where-Object { $_.root_scope -eq "session_backup" -and $_.classification -eq "session_backup" } |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First $KeepSessionBackups
)

foreach($row in $projectFullRows) {
    [void]$keepIndexes.Add([int]$row.row_index)
}
foreach($row in $projectPartialRows) {
    [void]$keepIndexes.Add([int]$row.row_index)
}
foreach($row in $projectHandoffRows) {
    [void]$keepIndexes.Add([int]$row.row_index)
}
foreach($row in $sessionRows) {
    [void]$keepIndexes.Add([int]$row.row_index)
}

foreach($row in $rows) {
    if($row.inspect_status -ne "ok" -and $row.root_scope -eq "project_backup") {
        [void]$keepIndexes.Add($row.row_index)
    }
}

foreach($row in $rows) {
    if($keepIndexes.Contains($row.row_index)) {
        $row.keep = $true
        switch($row.classification) {
            "pelny_restore_point" { $row.keep_reason = "retained_full_restore_point" }
            "snapshot_czesciowy" {
                if($row.inspect_status -ne "ok") {
                    $row.keep_reason = "retained_unreadable_protected"
                }
                else {
                    $row.keep_reason = "retained_latest_partial_snapshot"
                }
            }
            "handoff" { $row.keep_reason = "retained_recent_handoff" }
            "session_backup" { $row.keep_reason = "retained_recent_session_tail" }
        }
    }
    else {
        $row.delete_reason = "outside_retention_window"
    }
}

$preSummary = New-ManifestSummary -Rows $rows -Stage "pre_cleanup"
$keepRows = @(
    $rows |
        Where-Object { $_.keep } |
        Sort-Object -Property "root_scope", "classification", @{ Expression = "LastWriteTime"; Descending = $true }
)
$deleteRows = @(
    $rows |
        Where-Object { -not $_.keep } |
        Sort-Object -Property "root_scope", "classification", @{ Expression = "LastWriteTime"; Descending = $true }
)

$preManifest = [pscustomobject]@{
    policy = [pscustomobject]@{
        keep_project_full_backups     = $KeepProjectFullBackups
        keep_project_partial_snapshots= $KeepProjectPartialSnapshots
        keep_project_handoffs         = $KeepProjectHandoffs
        keep_session_backups          = $KeepSessionBackups
        full_restore_threshold_entries= 500
    }
    summary = $preSummary
    keep    = $keepRows
    delete  = $deleteRows
}

$preJsonPath = Join-Path $EvidenceDir ("backup_retention_manifest_{0}.json" -f $timestamp)
$preJsonLatestPath = Join-Path $EvidenceDir "backup_retention_manifest_latest.json"
$preMdPath = Join-Path $EvidenceDir ("backup_retention_manifest_{0}.md" -f $timestamp)
$preMdLatestPath = Join-Path $EvidenceDir "backup_retention_manifest_latest.md"

$preManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $preJsonPath -Encoding UTF8
$preManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $preJsonLatestPath -Encoding UTF8

$preMd = @"
# Manifest retencji backupow

Data wygenerowania: $($preSummary.generated_at)

## Podsumowanie przed usuwaniem
- Wszystkich archiwow: $($preSummary.total_files)
- Zostaje: $($preSummary.kept_files)
- Do usuniecia: $($preSummary.delete_files)
- Odzysk miejsca po usunieciu: $($preSummary.delete_size_human)

## Zachowane pelne restore pointy
$(
    ($keepRows | Where-Object { $_.classification -eq "pelny_restore_point" } | ForEach-Object {
        "- $($_.name) | $($_.size_human) | $($_.last_write_time)"
    }) -join "`n"
)

## Zachowane snapshoty czesciowe
$(
    ($keepRows | Where-Object { $_.classification -eq "snapshot_czesciowy" } | ForEach-Object {
        "- $($_.name) | $($_.size_human) | $($_.last_write_time)"
    }) -join "`n"
)

## Zachowane handoffy
$(
    ($keepRows | Where-Object { $_.classification -eq "handoff" } | ForEach-Object {
        "- $($_.name) | $($_.size_human) | $($_.last_write_time)"
    }) -join "`n"
)

## Zachowany ogon sesyjny
$(
    ($keepRows | Where-Object { $_.classification -eq "session_backup" } | ForEach-Object {
        "- $($_.name) | $($_.size_human) | $($_.last_write_time)"
    }) -join "`n"
)

## Archiwa do usuniecia
$(
    ($deleteRows | ForEach-Object {
        "- $($_.name) | $($_.classification) | $($_.size_human) | $($_.last_write_time)"
    }) -join "`n"
)
"@

$preMd | Set-Content -LiteralPath $preMdPath -Encoding UTF8
$preMd | Set-Content -LiteralPath $preMdLatestPath -Encoding UTF8

$deletedFiles = New-Object System.Collections.ArrayList

if($Apply) {
    foreach($row in $deleteRows) {
        Remove-Item -LiteralPath $row.full_path -Force
        $deletedFiles.Add([pscustomobject]@{
            name         = $row.name
            full_path    = $row.full_path
            size_human   = $row.size_human
            length_bytes = $row.length_bytes
        }) | Out-Null
    }
}

$postSummary = [pscustomobject]@{
    generated_at              = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    apply_requested           = [bool]$Apply
    deleted_files             = $deletedFiles.Count
    deleted_bytes             = Get-SafeSum -Rows @($deletedFiles) -PropertyName "length_bytes"
    deleted_size_human        = Convert-ToHumanSize -Bytes (Get-SafeSum -Rows @($deletedFiles) -PropertyName "length_bytes")
    retained_reference_files  = @(
        $keepRows |
            Select-Object name, classification, size_human, last_write_time, keep_reason
    )
}

$postResult = [pscustomobject]@{
    policy = $preManifest.policy
    pre_cleanup_summary = $preSummary
    post_cleanup_summary = $postSummary
    deleted = @($deletedFiles)
}

$postJsonPath = Join-Path $EvidenceDir ("backup_retention_result_{0}.json" -f $timestamp)
$postJsonLatestPath = Join-Path $EvidenceDir "backup_retention_result_latest.json"
$postMdPath = Join-Path $EvidenceDir ("backup_retention_result_{0}.md" -f $timestamp)
$postMdLatestPath = Join-Path $EvidenceDir "backup_retention_result_latest.md"

$postResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $postJsonPath -Encoding UTF8
$postResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $postJsonLatestPath -Encoding UTF8

$postMd = @"
# Wynik retencji backupow

Data wykonania: $($postSummary.generated_at)

## Wynik
- Tryb usuwania: $([string]([bool]$Apply))
- Usuniete archiwa: $($postSummary.deleted_files)
- Odzyskane miejsce: $($postSummary.deleted_size_human)

## Zachowane referencyjne backupy
$(
    ($postSummary.retained_reference_files | ForEach-Object {
        "- $($_.name) | $($_.classification) | $($_.size_human) | $($_.last_write_time) | $($_.keep_reason)"
    }) -join "`n"
)

## Usuniete archiwa
$(
    ($deletedFiles | ForEach-Object {
        "- $($_.name) | $($_.size_human)"
    }) -join "`n"
)
"@

$postMd | Set-Content -LiteralPath $postMdPath -Encoding UTF8
$postMd | Set-Content -LiteralPath $postMdLatestPath -Encoding UTF8

Write-Output ("manifest_json={0}" -f $preJsonPath)
Write-Output ("result_json={0}" -f $postJsonPath)
Write-Output ("deleted_files={0}" -f $postSummary.deleted_files)
Write-Output ("deleted_size_human={0}" -f $postSummary.deleted_size_human)
