param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [int]$SyncReportMaxAgeSeconds = 900,
    [int]$ExportLagMaxAgeSeconds = 600,
    [int]$PendingSyncGraceSeconds = 120,
    [int]$ExportLagRefreshChunkThreshold = 24,
    [switch]$Apply
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

function New-DirectoryIfMissing {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-FileAgeSecondsOrNull {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return [int][Math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds)
}

function Get-RelativeChunkKey {
    param(
        [string]$RootPath,
        [string]$DataPath
    )

    $rootItem = Get-Item -LiteralPath $RootPath
    $dataItem = Get-Item -LiteralPath $DataPath
    $rootFull = [System.IO.Path]::GetFullPath($rootItem.FullName)
    $dataFull = [System.IO.Path]::GetFullPath($dataItem.FullName)

    if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $rootFull = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    }

    if ($dataFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $dataFull.Substring($rootFull.Length)
        return ($relative -replace '\\', '/')
    }

    $rootUri = New-Object System.Uri($rootFull)
    $dataUri = New-Object System.Uri($dataFull)
    $relativeUri = $rootUri.MakeRelativeUri($dataUri)
    $relative = [System.Uri]::UnescapeDataString($relativeUri.ToString())
    return ($relative -replace '\\', '/')
}

function Get-ChunkEntries {
    param([string]$RootPath)

    $entries = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $RootPath)) {
        return @()
    }

    $readyFiles = @(
        Get-ChildItem -LiteralPath $RootPath -Recurse -File -Filter *.ready -ErrorAction SilentlyContinue |
            Sort-Object FullName
    )

    foreach ($ready in $readyFiles) {
        $dataPath = $ready.FullName.Substring(0, $ready.FullName.Length - ".ready".Length)
        $manifestPath = "$dataPath.manifest.json"
        $chunkKey = Get-RelativeChunkKey -RootPath $RootPath -DataPath $dataPath
        $stream = ($chunkKey -split '/')[0]
        $dataExists = Test-Path -LiteralPath $dataPath
        $manifestExists = Test-Path -LiteralPath $manifestPath
        $sizeBytes = 0
        if ($dataExists) {
            $sizeBytes = [int64](Get-Item -LiteralPath $dataPath).Length
        }

        $entries.Add([pscustomobject]@{
                key = $chunkKey
                stream = $stream
                ready_path = $ready.FullName
                data_path = $dataPath
                manifest_path = $manifestPath
                ready_age_seconds = [int][Math]::Round(((Get-Date) - $ready.LastWriteTime).TotalSeconds)
                data_exists = $dataExists
                manifest_exists = $manifestExists
                size_bytes = $sizeBytes
            }) | Out-Null
    }

    return $entries.ToArray()
}

function Get-StateChunkEntries {
    param([object]$StateObject)

    $entries = New-Object System.Collections.Generic.List[object]
    if ($null -eq $StateObject -or -not ($StateObject.PSObject.Properties.Name -contains "chunks")) {
        return @()
    }

    foreach ($property in @($StateObject.chunks.PSObject.Properties)) {
        $chunkKey = [string]$property.Name
        $payload = $property.Value
        $sourcePath = [string]$payload.source_path
        $inboxPath = [string]$payload.inbox_path
        $stream = [string]$payload.stream
        if ([string]::IsNullOrWhiteSpace($stream)) {
            $stream = ($chunkKey -split '/')[0]
        }

        $entries.Add([pscustomobject]@{
                key = $chunkKey
                stream = $stream
                source_path = $sourcePath
                inbox_path = $inboxPath
                manifest_path = [string]$payload.manifest_path
                copied_at = [string]$payload.copied_at
                source_exists = (-not [string]::IsNullOrWhiteSpace($sourcePath) -and (Test-Path -LiteralPath $sourcePath))
                inbox_exists = (-not [string]::IsNullOrWhiteSpace($inboxPath) -and (Test-Path -LiteralPath $inboxPath))
            }) | Out-Null
    }

    return $entries.ToArray()
}

function New-EntryMap {
    param([object[]]$Entries)

    $map = @{}
    foreach ($entry in @($Entries)) {
        $map[[string]$entry.key] = $entry
    }

    return $map
}

function Get-StreamCounts {
    param([object[]]$Entries)

    $counts = [ordered]@{}
    foreach ($group in @($Entries | Group-Object stream | Sort-Object Name)) {
        $counts[$group.Name] = $group.Count
    }

    return $counts
}

function Get-ManifestDatasetSpoolCounts {
    param([object]$ManifestObject)

    $counts = [ordered]@{
        candidate_signals = 0
        learning_observations_v2 = 0
        onnx_observations = 0
    }

    if ($null -eq $ManifestObject -or -not ($ManifestObject.PSObject.Properties.Name -contains "datasets")) {
        return $counts
    }

    foreach ($name in @($counts.Keys)) {
        if ($ManifestObject.datasets.PSObject.Properties.Name -contains $name) {
            $dataset = $ManifestObject.datasets.$name
            if ($dataset.PSObject.Properties.Name -contains "source_file_count_vps_spool") {
                $counts[$name] = [int]$dataset.source_file_count_vps_spool
            }
        }
    }

    return $counts
}

function Get-CountFromObject {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return 0
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return [int]$Object[$Name]
        }
        return 0
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return 0
    }

    return [int]$property.Value
}

function Test-PendingSyncIsMovingTail {
    param(
        [object]$Snapshot,
        [int]$SyncReportMaxAgeSeconds
    )

    if ($null -eq $Snapshot) {
        return $false
    }

    if ($Snapshot.pending_sync_count -le 0) {
        return $false
    }

    if ($Snapshot.pending_sync_count -gt 24) {
        return $false
    }

    if ($Snapshot.source_incomplete_count -gt 0 -or
        $Snapshot.inbox_incomplete_count -gt 0 -or
        $Snapshot.state_orphan_count -gt 0 -or
        $Snapshot.state_missing_inbox_count -gt 0) {
        return $false
    }

    if (-not $Snapshot.sync_report_exists -or $null -eq $Snapshot.sync_report_age_seconds) {
        return $false
    }

    if ($Snapshot.sync_report_age_seconds -gt [Math]::Max($SyncReportMaxAgeSeconds, 900)) {
        return $false
    }

    if ($null -eq $Snapshot.pending_sync_oldest_age_seconds -or $Snapshot.pending_sync_oldest_age_seconds -gt 1200) {
        return $false
    }

    if ($Snapshot.sync_report_copied_chunk_count -le 0) {
        return $false
    }

    return $true
}

function Test-ExportLagIsMovingTail {
    param(
        [object]$Snapshot
    )

    if ($null -eq $Snapshot) {
        return $false
    }

    if ($Snapshot.export_spool_lag_total -le 0) {
        return $false
    }

    if (-not $Snapshot.pending_sync_is_moving_tail) {
        return $false
    }

    if ($null -eq $Snapshot.export_manifest_age_seconds -or $Snapshot.export_manifest_age_seconds -gt 3600) {
        return $false
    }

    if ($Snapshot.export_spool_lag_total -gt 256) {
        return $false
    }

    $onnxLag = Get-CountFromObject -Object $Snapshot.export_spool_lag_by_stream -Name "onnx_observations"
    $nonOnnxLag = [Math]::Max(0, $Snapshot.export_spool_lag_total - $onnxLag)
    if ($onnxLag -le 0) {
        return $false
    }

    return ($nonOnnxLag -le 2)
}

function Get-BridgeSnapshot {
    param(
        [string]$SourceRoot,
        [string]$InboxRoot,
        [string]$SyncReportPath,
        [string]$StatePath,
        [string]$ExportManifestPath
    )

    $syncReport = Read-JsonSafe -Path $SyncReportPath
    $stateObject = Read-JsonSafe -Path $StatePath
    $exportManifest = Read-JsonSafe -Path $ExportManifestPath

    $sourceEntries = @(Get-ChunkEntries -RootPath $SourceRoot)
    $inboxEntries = @(Get-ChunkEntries -RootPath $InboxRoot)
    $stateEntries = @(Get-StateChunkEntries -StateObject $stateObject)

    $inboxMap = New-EntryMap -Entries $inboxEntries

    $sourceIncomplete = @($sourceEntries | Where-Object { -not $_.data_exists -or -not $_.manifest_exists })
    $inboxIncomplete = @($inboxEntries | Where-Object { -not $_.data_exists -or -not $_.manifest_exists })
    $pendingSync = @(
        $sourceEntries | Where-Object {
            $_.data_exists -and
            $_.manifest_exists -and
            (
                (-not $inboxMap.ContainsKey($_.key)) -or
                (-not $inboxMap[$_.key].data_exists) -or
                (-not $inboxMap[$_.key].manifest_exists)
            )
        }
    )
    $stateOrphans = @(
        $stateEntries | Where-Object {
            (-not $_.source_exists) -and (-not $_.inbox_exists)
        }
    )
    $stateMissingInbox = @(
        $stateEntries | Where-Object {
            $_.source_exists -and (-not $_.inbox_exists)
        }
    )

    $oldestPendingAge = $null
    if ($pendingSync.Count -gt 0) {
        $oldestPendingAge = [int](($pendingSync | Measure-Object -Property ready_age_seconds -Maximum).Maximum)
    }

    $sourceCounts = Get-StreamCounts -Entries $sourceEntries
    $inboxCounts = Get-StreamCounts -Entries $inboxEntries
    $manifestCounts = Get-ManifestDatasetSpoolCounts -ManifestObject $exportManifest

    $lagByStream = [ordered]@{}
    $lagTotal = 0
    foreach ($stream in @("candidate_signals", "learning_observations_v2", "onnx_observations")) {
        $inboxCount = if ($inboxCounts.Contains($stream)) { [int]$inboxCounts[$stream] } else { 0 }
        $manifestCount = [int]$manifestCounts[$stream]
        $lag = [Math]::Max(0, $inboxCount - $manifestCount)
        $lagByStream[$stream] = $lag
        $lagTotal += $lag
    }

    [pscustomobject]@{
        source_root_exists = (Test-Path -LiteralPath $SourceRoot)
        inbox_root_exists = (Test-Path -LiteralPath $InboxRoot)
        sync_report_exists = (Test-Path -LiteralPath $SyncReportPath)
        sync_report_age_seconds = Get-FileAgeSecondsOrNull -Path $SyncReportPath
        sync_report_copied_chunk_count = if ($null -ne $syncReport) { [int]$syncReport.copied_chunk_count } else { 0 }
        sync_report_reused_chunk_count = if ($null -ne $syncReport) { [int]$syncReport.reused_chunk_count } else { 0 }
        export_manifest_exists = (Test-Path -LiteralPath $ExportManifestPath)
        export_manifest_age_seconds = Get-FileAgeSecondsOrNull -Path $ExportManifestPath
        sync_report_missing_data_count = if ($null -ne $syncReport) { [int]$syncReport.missing_data_count } else { 0 }
        sync_report_missing_manifest_count = if ($null -ne $syncReport) { [int]$syncReport.missing_manifest_count } else { 0 }
        source_ready_file_count = $sourceEntries.Count
        inbox_ready_file_count = $inboxEntries.Count
        state_chunk_count = $stateEntries.Count
        source_incomplete_count = $sourceIncomplete.Count
        inbox_incomplete_count = $inboxIncomplete.Count
        pending_sync_count = $pendingSync.Count
        pending_sync_oldest_age_seconds = $oldestPendingAge
        state_orphan_count = $stateOrphans.Count
        state_missing_inbox_count = $stateMissingInbox.Count
        source_stream_counts = $sourceCounts
        inbox_stream_counts = $inboxCounts
        manifest_stream_counts = $manifestCounts
        export_spool_lag_by_stream = $lagByStream
        export_spool_lag_total = $lagTotal
        state_orphan_keys = @($stateOrphans | Select-Object -ExpandProperty key -First 50)
        pending_sync_keys = @($pendingSync | Select-Object -ExpandProperty key -First 50)
        source_incomplete_keys = @($sourceIncomplete | Select-Object -ExpandProperty key -First 50)
        inbox_incomplete_keys = @($inboxIncomplete | Select-Object -ExpandProperty key -First 50)
    }
}

function Remove-OrphanedStateEntries {
    param(
        [string]$StatePath,
        [object]$StateObject,
        [string[]]$KeysToRemove
    )

    if ($KeysToRemove.Count -le 0 -or $null -eq $StateObject -or -not ($StateObject.PSObject.Properties.Name -contains "chunks")) {
        return 0
    }

    $chunks = [ordered]@{}
    foreach ($property in @($StateObject.chunks.PSObject.Properties | Sort-Object Name)) {
        if ($KeysToRemove -contains [string]$property.Name) {
            continue
        }
        $chunks[[string]$property.Name] = $property.Value
    }

    $payload = [ordered]@{
        schema_version = if ($StateObject.PSObject.Properties.Name -contains "schema_version") { [string]$StateObject.schema_version } else { "1.0" }
        ts_local = (Get-Date).ToString("o")
        source_root = if ($StateObject.PSObject.Properties.Name -contains "source_root") { [string]$StateObject.source_root } else { "" }
        inbox_root = if ($StateObject.PSObject.Properties.Name -contains "inbox_root") { [string]$StateObject.inbox_root } else { "" }
        chunks = $chunks
    }

    $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    return $KeysToRemove.Count
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$syncReportPath = Join-Path $opsRoot "vps_spool_sync_latest.json"
$jsonPath = Join-Path $opsRoot "vps_spool_wellbeing_latest.json"
$mdPath = Join-Path $opsRoot "vps_spool_wellbeing_latest.md"
$statePath = Join-Path $ResearchRoot "reports\vps_spool_sync_state_latest.json"
$exportManifestPath = Join-Path $ResearchRoot "reports\research_export_manifest_latest.json"
$inboxRoot = Join-Path $ResearchRoot "vps_spool_inbox"
$sourceRoot = Join-Path $CommonRoot "spool"
$syncScript = Join-Path $ProjectRoot "RUN\SYNC_VPS_SPOOL_BACKLOG.ps1"
$researchContractScript = Join-Path $ProjectRoot "RUN\BUILD_RESEARCH_DATA_CONTRACT.ps1"

foreach ($path in @($syncScript, $researchContractScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-DirectoryIfMissing -Path $opsRoot
New-DirectoryIfMissing -Path (Split-Path -Parent $statePath)

$initialStateObject = Read-JsonSafe -Path $statePath
$repairActions = New-Object System.Collections.Generic.List[object]
$initialSnapshot = Get-BridgeSnapshot `
    -SourceRoot $sourceRoot `
    -InboxRoot $inboxRoot `
    -SyncReportPath $syncReportPath `
    -StatePath $statePath `
    -ExportManifestPath $exportManifestPath

if ($Apply) {
    if ($initialSnapshot.state_orphan_count -gt 0) {
        $removed = Remove-OrphanedStateEntries -StatePath $statePath -StateObject $initialStateObject -KeysToRemove @($initialSnapshot.state_orphan_keys)
        if ($removed -gt 0) {
            $repairActions.Add([pscustomobject]@{
                    action = "prune_state_orphans"
                    removed_count = $removed
            }) | Out-Null
        }
    }

    $postRepairSnapshot = Get-BridgeSnapshot `
        -SourceRoot $sourceRoot `
        -InboxRoot $inboxRoot `
        -SyncReportPath $syncReportPath `
        -StatePath $statePath `
        -ExportManifestPath $exportManifestPath

    $needsSync = (
        (-not $postRepairSnapshot.sync_report_exists) -or
        ($null -eq $postRepairSnapshot.sync_report_age_seconds) -or
        ($postRepairSnapshot.sync_report_age_seconds -gt $SyncReportMaxAgeSeconds) -or
        (
            $postRepairSnapshot.pending_sync_count -gt 0 -and
            $null -ne $postRepairSnapshot.pending_sync_oldest_age_seconds -and
            $postRepairSnapshot.pending_sync_oldest_age_seconds -gt $PendingSyncGraceSeconds
        ) -or
        ($postRepairSnapshot.state_missing_inbox_count -gt 0) -or
        ($postRepairSnapshot.sync_report_missing_data_count -gt 0) -or
        ($postRepairSnapshot.sync_report_missing_manifest_count -gt 0)
    )

    if ($needsSync) {
        & $syncScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -SourceRoot $sourceRoot | Out-Null
        $repairActions.Add([pscustomobject]@{
                action = "sync_vps_spool_backlog"
                reason = "stale_or_pending_bridge"
            }) | Out-Null
    }

    $postSyncSnapshot = Get-BridgeSnapshot `
        -SourceRoot $sourceRoot `
        -InboxRoot $inboxRoot `
        -SyncReportPath $syncReportPath `
        -StatePath $statePath `
        -ExportManifestPath $exportManifestPath

    $needsExportRefresh = (
        ($postSyncSnapshot.export_spool_lag_total -gt 0) -and
        (
            ($null -eq $postSyncSnapshot.export_manifest_age_seconds) -or
            (
                $postSyncSnapshot.export_manifest_age_seconds -gt $ExportLagMaxAgeSeconds -and
                $postSyncSnapshot.export_spool_lag_total -ge $ExportLagRefreshChunkThreshold
            )
        )
    )

    if ($needsExportRefresh) {
        $refreshOutput = @(
            & $researchContractScript `
                -ProjectRoot $ProjectRoot `
                -ResearchRoot $ResearchRoot `
                -FreshContractThresholdSeconds ([Math]::Max(120, [Math]::Min($ExportLagMaxAgeSeconds, 900))) 2>&1
        ) | ForEach-Object { [string]$_ }
        $refreshOutputText = ($refreshOutput -join " ").Trim()
        $refreshOutputSummary = if ([string]::IsNullOrWhiteSpace($refreshOutputText)) {
            "no_stdout"
        }
        elseif ($refreshOutputText -like "*Research export runner already active*") {
            "export_runner_active_deferred"
        }
        elseif ($refreshOutputText -like '*"research_manifest_refreshed": true*') {
            "research_manifest_refreshed"
        }
        elseif ($refreshOutputText -like '*"contract_only": true*') {
            "contract_rebuilt"
        }
        elseif ($refreshOutputText -like "*Traceback*" -or $refreshOutputText -like "*IO Error*") {
            "refresh_attempt_emitted_error"
        }
        else {
            if ($refreshOutputText.Length -gt 160) {
                $refreshOutputText.Substring(0, 160)
            }
            else {
                $refreshOutputText
            }
        }

        $repairActions.Add([pscustomobject]@{
                action = "refresh_research_contract"
                reason = "export_lag_exceeded"
                lag_total_before = $postSyncSnapshot.export_spool_lag_total
                manifest_age_seconds_before = $postSyncSnapshot.export_manifest_age_seconds
                output_summary = $refreshOutputSummary
            }) | Out-Null
    }
}

$finalSnapshot = Get-BridgeSnapshot `
    -SourceRoot $sourceRoot `
    -InboxRoot $inboxRoot `
    -SyncReportPath $syncReportPath `
    -StatePath $statePath `
    -ExportManifestPath $exportManifestPath

$finalSnapshot | Add-Member -NotePropertyName pending_sync_is_moving_tail -NotePropertyValue (Test-PendingSyncIsMovingTail -Snapshot $finalSnapshot -SyncReportMaxAgeSeconds $SyncReportMaxAgeSeconds)
$finalSnapshot | Add-Member -NotePropertyName export_lag_is_moving_tail -NotePropertyValue (Test-ExportLagIsMovingTail -Snapshot $finalSnapshot)

$findings = New-Object System.Collections.Generic.List[object]

if (-not $finalSnapshot.source_root_exists) {
    $findings.Add([pscustomobject]@{
            severity = "high"
            component = "vps_spool_source_missing"
            message = "Katalog spoola VPS nie istnieje."
            context = @{ source_root = $sourceRoot }
        }) | Out-Null
}

if (-not $finalSnapshot.sync_report_exists) {
    $findings.Add([pscustomobject]@{
            severity = "high"
            component = "vps_spool_sync_report_missing"
            message = "Brakuje raportu synchronizacji VPS spool."
            context = @{ path = $syncReportPath }
        }) | Out-Null
}
elseif ($null -ne $finalSnapshot.sync_report_age_seconds -and $finalSnapshot.sync_report_age_seconds -gt $SyncReportMaxAgeSeconds) {
    $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "vps_spool_sync_report_stale"
            message = "Raport synchronizacji VPS spool jest przeterminowany."
            context = @{
                age_seconds = $finalSnapshot.sync_report_age_seconds
                threshold_seconds = $SyncReportMaxAgeSeconds
            }
        }) | Out-Null
}

if ($finalSnapshot.source_incomplete_count -gt 0) {
    $findings.Add([pscustomobject]@{
            severity = "high"
            component = "vps_spool_source_incomplete"
            message = "Czesc chunkow w spoolu nie ma kompletu danych albo manifestu."
            context = @{
                source_incomplete_count = $finalSnapshot.source_incomplete_count
                sample_keys = @($finalSnapshot.source_incomplete_keys | Select-Object -First 10)
            }
        }) | Out-Null
}

if ($finalSnapshot.inbox_incomplete_count -gt 0) {
    $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "vps_spool_inbox_incomplete"
            message = "Lokalny inbox ma niekompletne chunki po synchronizacji."
            context = @{
                inbox_incomplete_count = $finalSnapshot.inbox_incomplete_count
                sample_keys = @($finalSnapshot.inbox_incomplete_keys | Select-Object -First 10)
            }
        }) | Out-Null
}

if (
    $finalSnapshot.pending_sync_count -gt 0 -and
    $null -ne $finalSnapshot.pending_sync_oldest_age_seconds -and
    $finalSnapshot.pending_sync_oldest_age_seconds -gt $PendingSyncGraceSeconds -and
    -not $finalSnapshot.pending_sync_is_moving_tail
) {
    $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "vps_spool_pending_sync"
            message = "Sa gotowe chunki na VPS, ktore nie trafily jeszcze do lokalnego inboxu."
            context = @{
                pending_sync_count = $finalSnapshot.pending_sync_count
                oldest_age_seconds = $finalSnapshot.pending_sync_oldest_age_seconds
                grace_seconds = $PendingSyncGraceSeconds
                sample_keys = @($finalSnapshot.pending_sync_keys | Select-Object -First 10)
            }
        }) | Out-Null
}

if ($finalSnapshot.state_orphan_count -gt 0) {
    $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "vps_spool_state_orphans"
            message = "Stan synchronizacji zawiera osierocone wpisy bez danych zrodlowych i bez inboxu."
            context = @{
                state_orphan_count = $finalSnapshot.state_orphan_count
                sample_keys = @($finalSnapshot.state_orphan_keys | Select-Object -First 10)
            }
        }) | Out-Null
}

if ($finalSnapshot.state_missing_inbox_count -gt 0) {
    $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "vps_spool_state_missing_inbox"
            message = "Stan synchronizacji wskazuje chunki z VPS, ktore nadal nie maja lokalnej kopii w inboxie."
            context = @{
                state_missing_inbox_count = $finalSnapshot.state_missing_inbox_count
            }
        }) | Out-Null
}

if (
    $finalSnapshot.export_spool_lag_total -gt 0 -and
    $null -ne $finalSnapshot.export_manifest_age_seconds -and
    $finalSnapshot.export_manifest_age_seconds -gt $ExportLagMaxAgeSeconds -and
    -not $finalSnapshot.export_lag_is_moving_tail
) {
    $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "vps_spool_export_lag"
            message = "Inbox ma juz chunki spoola, ale research export jeszcze ich w pelni nie widzi."
            context = @{
                export_spool_lag_total = $finalSnapshot.export_spool_lag_total
                export_manifest_age_seconds = $finalSnapshot.export_manifest_age_seconds
                lag_by_stream = $finalSnapshot.export_spool_lag_by_stream
            }
        }) | Out-Null
}

$verdict = "MOST_STABILNY"
if ($findings.Count -gt 0) {
    $hasHigh = @($findings | Where-Object { $_.severity -eq "high" }).Count -gt 0
    if ($hasHigh) {
        $verdict = "MOST_WYMAGA_DALSZEJ_NAPRAWY"
    }
    else {
        $verdict = "MOST_WYMAGA_NAPRAWY"
    }
}
elseif ($repairActions.Count -gt 0) {
    $verdict = "MOST_UTWARDZONY"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    research_root = $ResearchRoot
    common_root = $CommonRoot
    apply_mode = [bool]$Apply
    verdict = $verdict
    summary = [ordered]@{
        source_ready_file_count = $finalSnapshot.source_ready_file_count
        inbox_ready_file_count = $finalSnapshot.inbox_ready_file_count
        state_chunk_count = $finalSnapshot.state_chunk_count
        pending_sync_count = $finalSnapshot.pending_sync_count
        pending_sync_oldest_age_seconds = $finalSnapshot.pending_sync_oldest_age_seconds
        pending_sync_is_moving_tail = [bool]$finalSnapshot.pending_sync_is_moving_tail
        source_incomplete_count = $finalSnapshot.source_incomplete_count
        inbox_incomplete_count = $finalSnapshot.inbox_incomplete_count
        state_orphan_count = $finalSnapshot.state_orphan_count
        state_missing_inbox_count = $finalSnapshot.state_missing_inbox_count
        export_spool_lag_total = $finalSnapshot.export_spool_lag_total
        export_lag_is_moving_tail = [bool]$finalSnapshot.export_lag_is_moving_tail
        sync_report_age_seconds = $finalSnapshot.sync_report_age_seconds
        sync_report_copied_chunk_count = $finalSnapshot.sync_report_copied_chunk_count
        sync_report_reused_chunk_count = $finalSnapshot.sync_report_reused_chunk_count
        export_manifest_age_seconds = $finalSnapshot.export_manifest_age_seconds
        repair_actions_count = $repairActions.Count
        findings_total = $findings.Count
    }
    source_stream_counts = $finalSnapshot.source_stream_counts
    inbox_stream_counts = $finalSnapshot.inbox_stream_counts
    manifest_stream_counts = $finalSnapshot.manifest_stream_counts
    export_spool_lag_by_stream = $finalSnapshot.export_spool_lag_by_stream
    repair_actions = $repairActions.ToArray()
    findings = $findings.ToArray()
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# VPS Spool Wellbeing")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- source_ready_file_count: {0}" -f $report.summary.source_ready_file_count))
$lines.Add(("- inbox_ready_file_count: {0}" -f $report.summary.inbox_ready_file_count))
$lines.Add(("- pending_sync_count: {0}" -f $report.summary.pending_sync_count))
$lines.Add(("- state_orphan_count: {0}" -f $report.summary.state_orphan_count))
$lines.Add(("- export_spool_lag_total: {0}" -f $report.summary.export_spool_lag_total))
$lines.Add("")
$lines.Add("## Strumienie")
$lines.Add("")
foreach ($stream in @("candidate_signals", "learning_observations_v2", "onnx_observations")) {
    $src = if ($report.source_stream_counts.Contains($stream)) { $report.source_stream_counts[$stream] } else { 0 }
    $inbox = if ($report.inbox_stream_counts.Contains($stream)) { $report.inbox_stream_counts[$stream] } else { 0 }
    $manifest = if ($report.manifest_stream_counts.Contains($stream)) { $report.manifest_stream_counts[$stream] } else { 0 }
    $lag = if ($report.export_spool_lag_by_stream.Contains($stream)) { $report.export_spool_lag_by_stream[$stream] } else { 0 }
    $lines.Add(("- {0}: source={1}, inbox={2}, manifest={3}, lag={4}" -f $stream, $src, $inbox, $manifest, $lag))
}

if ($repairActions.Count -gt 0) {
    $lines.Add("")
    $lines.Add("## Naprawy")
    $lines.Add("")
    foreach ($action in $repairActions) {
        $summary = [string]$action.action
        if ($action.PSObject.Properties.Name -contains "removed_count") {
            $summary += (" removed={0}" -f $action.removed_count)
        }
        if ($action.PSObject.Properties.Name -contains "reason") {
            $summary += (" reason={0}" -f $action.reason)
        }
        $lines.Add(("- {0}" -f $summary))
    }
}

if ($findings.Count -gt 0) {
    $lines.Add("")
    $lines.Add("## Findings")
    $lines.Add("")
    foreach ($finding in $findings) {
        $lines.Add(("- [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message))
    }
}

$lines -join [Environment]::NewLine | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 10
