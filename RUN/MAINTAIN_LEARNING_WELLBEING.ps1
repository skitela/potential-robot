param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [int]$OpsSnapshotKeepCount = 288,
    [int]$OpsStatusKeepCount = 192,
    [int]$OpsLogKeepCount = 8,
    [int]$OpsRetentionDays = 3,
    [int]$RuntimeArchiveRetentionDays = 4,
    [int]$RuntimeArchiveKeepRecentPerKind = 2,
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

function Get-ManifestState {
    param([string]$ManifestPath)

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return [pscustomobject]@{
            exists = $false
            age_seconds = $null
            threshold_seconds = 1800
            fresh = $false
        }
    }

    $item = Get-Item -LiteralPath $ManifestPath
    $ageSeconds = [int][Math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)
    return [pscustomobject]@{
        exists = $true
        age_seconds = $ageSeconds
        threshold_seconds = 1800
        fresh = ($ageSeconds -le 1800)
    }
}

function Get-NormalizedArchiveLeafName {
    param([string]$Name)

    if ($Name -match '^\d+_(.+)$') {
        return $Matches[1]
    }

    return $Name
}

function Get-SymbolFromArchivePath {
    param(
        [string]$LogsRoot,
        [string]$FullName
    )

    $escaped = [regex]::Escape($LogsRoot.TrimEnd('\'))
    if ($FullName -match ("^{0}\\([^\\]+)\\archive\\" -f $escaped)) {
        return $Matches[1]
    }

    return ""
}

function Remove-EmptyDirectories {
    param([string]$RootPath)

    $removed = 0
    if (-not (Test-Path -LiteralPath $RootPath)) {
        return $removed
    }

    $dirs = @(
        Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending
    )
    foreach ($dir in $dirs) {
        $children = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)
        if ($children.Count -eq 0) {
            Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }

    return $removed
}

function Invoke-JsonScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    return (& $ScriptPath @Parameters)
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$logsRoot = Join-Path $CommonRoot "logs"
$reportsRoot = Join-Path $ResearchRoot "reports"
$manifestPath = Join-Path $reportsRoot "research_export_manifest_latest.json"
$pathHygienePath = Join-Path $opsRoot "learning_path_hygiene_latest.json"
$hotPathPath = Join-Path $opsRoot "learning_hot_path_latest.json"
$normalizeScript = Join-Path $ProjectRoot "RUN\NORMALIZE_LEARNING_ARTIFACT_LAYERS.ps1"
$vpsSpoolWellbeingScript = Join-Path $ProjectRoot "RUN\BUILD_VPS_SPOOL_WELLBEING_AUDIT.ps1"
$qdmMissingProfileScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_MISSING_ONLY_PROFILE.ps1"
$instrumentDataReadinessScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_DATA_READINESS_REPORT.ps1"
$instrumentTrainingReadinessScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_TRAINING_READINESS_REPORT.ps1"
$qdmMissingSyncStarterScript = Join-Path $ProjectRoot "RUN\START_QDM_MISSING_SUPPORTED_SYNC_BACKGROUND.ps1"
$qdmMissingSyncStatusPath = Join-Path $opsRoot "qdm_missing_supported_sync_latest.json"
$jsonPath = Join-Path $opsRoot "learning_wellbeing_latest.json"
$mdPath = Join-Path $opsRoot "learning_wellbeing_latest.md"

foreach ($path in @($normalizeScript, $vpsSpoolWellbeingScript, $qdmMissingProfileScript, $instrumentDataReadinessScript, $instrumentTrainingReadinessScript, $qdmMissingSyncStarterScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-DirectoryIfMissing -Path $opsRoot

$pathHygiene = Read-JsonSafe -Path $pathHygienePath
$hotPath = Read-JsonSafe -Path $hotPathPath
$manifestState = Get-ManifestState -ManifestPath $manifestPath
$null = & $qdmMissingProfileScript
$artifactCleanup = Invoke-JsonScript -ScriptPath $normalizeScript -Parameters @{
    ProjectRoot = $ProjectRoot
    ResearchRoot = $ResearchRoot
}
$vpsSpoolBridge = Invoke-JsonScript -ScriptPath $vpsSpoolWellbeingScript -Parameters @{
    ProjectRoot = $ProjectRoot
    ResearchRoot = $ResearchRoot
    CommonRoot = $CommonRoot
    Apply = [bool]$Apply
} | ConvertFrom-Json
$instrumentDataReadiness = (& $instrumentDataReadinessScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$instrumentTrainingReadiness = (& $instrumentTrainingReadinessScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$qdmMissingProfile = Read-JsonSafe -Path (Join-Path $opsRoot "qdm_missing_only_profile_latest.json")
$qdmMissingSyncStatus = Read-JsonSafe -Path $qdmMissingSyncStatusPath
$qdmRepairAction = ""

if ($Apply -and $null -ne $qdmMissingProfile) {
    $qdmMissingCount = [int]$qdmMissingProfile.qdm_missing_count
    $syncState = if ($null -ne $qdmMissingSyncStatus) { [string]$qdmMissingSyncStatus.state } else { "" }
    if ($qdmMissingCount -gt 0 -and $syncState -notin @("running", "export_in_progress")) {
        & $qdmMissingSyncStarterScript | Out-Null
        $qdmRepairAction = "started_qdm_missing_supported_sync_background"
        $qdmMissingSyncStatus = Read-JsonSafe -Path $qdmMissingSyncStatusPath
    }
}

$opsRules = @(
    [pscustomobject]@{ name = "local_operator_snapshot"; regex = '^local_operator_snapshot_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsSnapshotKeepCount; age_days = 2 },
    [pscustomobject]@{ name = "qdm_weakest_profile"; regex = '^qdm_weakest_profile_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "tuning_priority"; regex = '^tuning_priority_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "ml_tuning_hints"; regex = '^ml_tuning_hints_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "qdm_intensive_research_plan"; regex = '^qdm_intensive_research_plan_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "mt5_retest_queue"; regex = '^mt5_retest_queue_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "qdm_missing_only_profile"; regex = '^qdm_missing_only_profile_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "autonomous_90p_supervisor"; regex = '^autonomous_90p_supervisor_\d{8}_\d{6}\.log$'; keep_count = $OpsLogKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "audit_supervisor"; regex = '^audit_supervisor_\d{8}_\d{6}\.log$'; keep_count = $OpsLogKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "local_operator_archiver"; regex = '^local_operator_archiver_\d{8}_\d{6}\.log$'; keep_count = [Math]::Max(4, [int]($OpsLogKeepCount / 2)); age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "mt5_tester_status_watcher"; regex = '^mt5_tester_status_watcher_\d{8}_\d{6}\.log$'; keep_count = [Math]::Max(4, [int]($OpsLogKeepCount / 2)); age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "mt5_risk_popup_guard"; regex = '^mt5_risk_popup_guard_\d{8}_\d{6}\.log$'; keep_count = [Math]::Max(4, [int]($OpsLogKeepCount / 2)); age_days = $OpsRetentionDays }
)

$opsDeleted = New-Object System.Collections.Generic.List[object]
$opsPending = New-Object System.Collections.Generic.List[object]
$opsFreedBytes = [int64]0

$opsFiles = @()
if (Test-Path -LiteralPath $opsRoot) {
    $opsFiles = @(Get-ChildItem -LiteralPath $opsRoot -File -ErrorAction SilentlyContinue)
}

foreach ($rule in $opsRules) {
    $cutoff = (Get-Date).AddDays(-1 * [Math]::Abs([int]$rule.age_days))
    $files = @($opsFiles | Where-Object { $_.Name -match $rule.regex } | Sort-Object LastWriteTime -Descending)
    if ($files.Count -le $rule.keep_count) {
        continue
    }

    $candidates = @($files | Select-Object -Skip $rule.keep_count | Where-Object { $_.LastWriteTime -lt $cutoff })
    foreach ($file in $candidates) {
        $row = [pscustomobject]@{
            rule = $rule.name
            path = $file.FullName
            size_mb = [math]::Round($file.Length / 1MB, 2)
            last_write_local = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        if ($Apply) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $opsDeleted.Add($row) | Out-Null
            $opsFreedBytes += [int64]$file.Length
        }
        else {
            $opsPending.Add($row) | Out-Null
        }
    }
}

$runtimeAllowedLeafNames = @(
    "incident_journal.jsonl",
    "decision_events.csv",
    "candidate_signals.csv",
    "execution_telemetry.csv",
    "latency_profile.csv",
    "trade_transactions.jsonl",
    "tuning_actions.csv",
    "tuning_deckhand.csv",
    "tuning_family_actions.csv",
    "tuning_coordinator_actions.csv"
)

$runtimeDeleted = New-Object System.Collections.Generic.List[object]
$runtimePending = New-Object System.Collections.Generic.List[object]
$runtimeFreedBytes = [int64]0
$runtimeEmptyDirsRemoved = 0
$runtimeArchiveSkippedReason = ""

if (-not $manifestState.fresh) {
    $runtimeArchiveSkippedReason = "research_manifest_not_fresh"
}
elseif (Test-Path -LiteralPath $logsRoot) {
    $archiveFiles = @(
        Get-ChildItem -LiteralPath $logsRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\archive\\' } |
            ForEach-Object {
                $normalizedLeaf = Get-NormalizedArchiveLeafName -Name $_.Name
                if ($runtimeAllowedLeafNames -notcontains $normalizedLeaf) {
                    return
                }

                [pscustomobject]@{
                    file = $_
                    symbol = Get-SymbolFromArchivePath -LogsRoot $logsRoot -FullName $_.FullName
                    normalized_leaf = $normalizedLeaf
                }
            } |
            Where-Object { $null -ne $_ }
    )

    $cutoff = (Get-Date).AddDays(-1 * [Math]::Abs($RuntimeArchiveRetentionDays))
    $groups = $archiveFiles | Group-Object { "{0}|{1}" -f $_.symbol, $_.normalized_leaf }
    foreach ($group in $groups) {
        $sorted = @($group.Group | Sort-Object { $_.file.LastWriteTime } -Descending)
        if ($sorted.Count -le $RuntimeArchiveKeepRecentPerKind) {
            continue
        }

        $candidates = @($sorted | Select-Object -Skip $RuntimeArchiveKeepRecentPerKind | Where-Object { $_.file.LastWriteTime -lt $cutoff })
        foreach ($entry in $candidates) {
            $file = $entry.file
            $row = [pscustomobject]@{
                symbol = $entry.symbol
                log_name = $entry.normalized_leaf
                path = $file.FullName
                size_mb = [math]::Round($file.Length / 1MB, 2)
                last_write_local = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }

            if ($Apply) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                $runtimeDeleted.Add($row) | Out-Null
                $runtimeFreedBytes += [int64]$file.Length
            }
            else {
                $runtimePending.Add($row) | Out-Null
            }
        }
    }

    if ($Apply) {
        foreach ($archiveRoot in @(Get-ChildItem -LiteralPath $logsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName "archive" })) {
            $runtimeEmptyDirsRemoved += (Remove-EmptyDirectories -RootPath $archiveRoot)
        }
    }
}

$totalFreedGb = [math]::Round((($opsFreedBytes + $runtimeFreedBytes) / 1GB) + [double]$artifactCleanup.freed_gb_total, 3)
$dataReadinessSummary = if ($null -ne $instrumentDataReadiness) { $instrumentDataReadiness.summary } else { $null }
$trainingReadinessSummary = if ($null -ne $instrumentTrainingReadiness) { $instrumentTrainingReadiness.summary } else { $null }
$exportPendingCount = if ($null -ne $dataReadinessSummary) { [int]$dataReadinessSummary.export_pending_count } else { 0 }
$contractPendingCount = if ($null -ne $dataReadinessSummary) { [int]$dataReadinessSummary.contract_pending_count } else { 0 }
$localTrainingReadyCount = if ($null -ne $trainingReadinessSummary) { [int]$trainingReadinessSummary.local_training_ready_count } else { 0 }
$localTrainingLimitedCount = if ($null -ne $trainingReadinessSummary) { [int]$trainingReadinessSummary.local_training_limited_count } else { 0 }
$verdict = if (
    ($pathHygiene -ne $null -and [string]$pathHygiene.verdict -eq "CZYSTO") -and
    ($hotPath -ne $null -and [string]$hotPath.verdict -eq "GORACY_SZLAK_CZYSTY") -and
    ($null -ne $vpsSpoolBridge -and [string]$vpsSpoolBridge.verdict -in @("MOST_STABILNY", "MOST_UTWARDZONY")) -and
    $contractPendingCount -eq 0 -and
    $opsPending.Count -eq 0 -and
    $runtimePending.Count -eq 0 -and
    $runtimeArchiveSkippedReason -eq ""
) {
    if ($totalFreedGb -gt 0 -or $opsDeleted.Count -gt 0 -or $runtimeDeleted.Count -gt 0 -or $runtimeEmptyDirsRemoved -gt 0) {
        "DOBROSTAN_UTWARDZONY"
    }
    else {
        "DOBROSTAN_STABILNY"
    }
}
else {
    "WYMAGA_DALSZEJ_HIGIENY"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    research_root = $ResearchRoot
    common_root = $CommonRoot
    apply_mode = [bool]$Apply
    manifest = $manifestState
    learning_path_hygiene = if ($null -ne $pathHygiene) { [pscustomobject]@{ verdict = [string]$pathHygiene.verdict } } else { $null }
    learning_hot_path = if ($null -ne $hotPath) { [pscustomobject]@{ verdict = [string]$hotPath.verdict } } else { $null }
    vps_spool_bridge = $vpsSpoolBridge
    qdm_missing_supported_sync = $qdmMissingSyncStatus
    instrument_data_readiness = $instrumentDataReadiness
    instrument_training_readiness = $instrumentTrainingReadiness
    artifact_layers = [ordered]@{
        freed_gb_total = [double]$artifactCleanup.freed_gb_total
        qdm_export_deleted_count = @($artifactCleanup.qdm_export_deleted).Count
        research_csv_deleted_count = @($artifactCleanup.research_csv_deleted).Count
    }
    ops_retention = [ordered]@{
        deleted_count = $opsDeleted.Count
        pending_count = $opsPending.Count
        freed_gb = [math]::Round($opsFreedBytes / 1GB, 3)
        deleted = @($opsDeleted | Select-Object -First 50)
        pending = @($opsPending | Select-Object -First 50)
    }
    runtime_archive_prune = [ordered]@{
        skipped_reason = $runtimeArchiveSkippedReason
        deleted_count = $runtimeDeleted.Count
        pending_count = $runtimePending.Count
        empty_dirs_removed = $runtimeEmptyDirsRemoved
        freed_gb = [math]::Round($runtimeFreedBytes / 1GB, 3)
        deleted = @($runtimeDeleted | Select-Object -First 50)
        pending = @($runtimePending | Select-Object -First 50)
    }
    summary = [ordered]@{
        total_freed_gb = $totalFreedGb
        ops_deleted_count = $opsDeleted.Count
        ops_pending_count = $opsPending.Count
        runtime_archive_deleted_count = $runtimeDeleted.Count
        runtime_archive_pending_count = $runtimePending.Count
        runtime_empty_dirs_removed = $runtimeEmptyDirsRemoved
        qdm_export_pending_count = $exportPendingCount
        qdm_contract_pending_count = $contractPendingCount
        local_training_ready_count = $localTrainingReadyCount
        local_training_limited_count = $localTrainingLimitedCount
        vps_bridge_pending_sync_count = if ($null -ne $vpsSpoolBridge) { [int]$vpsSpoolBridge.summary.pending_sync_count } else { 0 }
        vps_bridge_repair_actions_count = if ($null -ne $vpsSpoolBridge) { [int]$vpsSpoolBridge.summary.repair_actions_count } else { 0 }
        vps_bridge_export_lag_total = if ($null -ne $vpsSpoolBridge) { [int]$vpsSpoolBridge.summary.export_spool_lag_total } else { 0 }
        qdm_repair_action = $qdmRepairAction
    }
    verdict = $verdict
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Learning Wellbeing")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- apply_mode: {0}" -f ([string]$report.apply_mode).ToLowerInvariant()))
$lines.Add(("- total_freed_gb: {0}" -f $report.summary.total_freed_gb))
$lines.Add("")
$lines.Add("## Wejscie")
$lines.Add("")
$lines.Add(("- manifest_fresh: {0}" -f $report.manifest.fresh))
$lines.Add(("- learning_path_hygiene: {0}" -f $(if ($null -ne $report.learning_path_hygiene) { $report.learning_path_hygiene.verdict } else { "BRAK" })))
$lines.Add(("- learning_hot_path: {0}" -f $(if ($null -ne $report.learning_hot_path) { $report.learning_hot_path.verdict } else { "BRAK" })))
$lines.Add(("- vps_spool_bridge: {0}" -f $(if ($null -ne $report.vps_spool_bridge) { $report.vps_spool_bridge.verdict } else { "BRAK" })))
$lines.Add(("- qdm_export_pending_count: {0}" -f $report.summary.qdm_export_pending_count))
$lines.Add(("- qdm_contract_pending_count: {0}" -f $report.summary.qdm_contract_pending_count))
$lines.Add(("- local_training_ready_count: {0}" -f $report.summary.local_training_ready_count))
$lines.Add(("- local_training_limited_count: {0}" -f $report.summary.local_training_limited_count))
$lines.Add("")
$lines.Add("## Akcje")
$lines.Add("")
$lines.Add(("- artifact_layers.freed_gb_total: {0}" -f $report.artifact_layers.freed_gb_total))
$lines.Add(("- ops_retention.deleted_count: {0}" -f $report.ops_retention.deleted_count))
$lines.Add(("- runtime_archive_prune.deleted_count: {0}" -f $report.runtime_archive_prune.deleted_count))
$lines.Add(("- runtime_archive_prune.empty_dirs_removed: {0}" -f $report.runtime_archive_prune.empty_dirs_removed))
$lines.Add(("- qdm_repair_action: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.qdm_repair_action)) { "none" } else { $report.summary.qdm_repair_action })))
$lines.Add(("- vps_spool_bridge.pending_sync_count: {0}" -f $report.summary.vps_bridge_pending_sync_count))
$lines.Add(("- vps_spool_bridge.repair_actions_count: {0}" -f $report.summary.vps_bridge_repair_actions_count))
$lines.Add(("- vps_spool_bridge.export_spool_lag_total: {0}" -f $report.summary.vps_bridge_export_lag_total))
if (-not [string]::IsNullOrWhiteSpace($report.runtime_archive_prune.skipped_reason)) {
    $lines.Add(("- runtime_archive_prune.skipped_reason: {0}" -f $report.runtime_archive_prune.skipped_reason))
}
$lines.Add("")

if ($report.ops_retention.deleted.Count -gt 0) {
    $lines.Add("## OPS Deleted")
    $lines.Add("")
    foreach ($item in $report.ops_retention.deleted) {
        $lines.Add(("- {0} | {1} MB | {2}" -f $item.rule, $item.size_mb, $item.path))
    }
    $lines.Add("")
}

if ($report.runtime_archive_prune.deleted.Count -gt 0) {
    $lines.Add("## Runtime Archive Deleted")
    $lines.Add("")
    foreach ($item in $report.runtime_archive_prune.deleted) {
        $lines.Add(("- {0} {1} | {2} MB | {3}" -f $item.symbol, $item.log_name, $item.size_mb, $item.path))
    }
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
