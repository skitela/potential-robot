param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$evidenceDir = Join-Path $ProjectRoot "EVIDENCE"
$jsonReport = Join-Path $evidenceDir "runtime_persistence_audit_report.json"
$txtReport = Join-Path $evidenceDir "runtime_persistence_audit_report.txt"

$snapshotNames = @(
    "runtime_state.csv",
    "paper_position.csv",
    "runtime_status.json",
    "execution_summary.json",
    "informational_policy.json",
    "broker_profile.json",
    "heartbeat.txt",
    "runtime_control.csv",
    "tuning_policy.csv",
    "tuning_policy_effective.csv",
    "tuning_policy_stable.csv",
    "session_capital_state.csv",
    "session_capital_coordinator.csv",
    "core_capital_contract.csv",
    "tuning_family_policy.csv",
    "tuning_coordinator_state.csv",
    "tester_telemetry_latest.json",
    "tester_pass_summary.csv"
)

$rotatableThresholds = [ordered]@{
    "incident_journal.jsonl" = 8MB
    "decision_events.csv" = 8MB
    "candidate_signals.csv" = 8MB
    "execution_telemetry.csv" = 12MB
    "latency_profile.csv" = 16MB
    "trade_transactions.jsonl" = 12MB
    "tuning_actions.csv" = 4MB
    "tuning_deckhand.csv" = 4MB
    "tuning_family_actions.csv" = 4MB
    "tuning_coordinator_actions.csv" = 4MB
}

$preservedLearningNames = @(
    "learning_observations_v2.csv",
    "learning_bucket_summary_v1.csv"
)

$preservedTuningNames = @(
    "tuning_reasoning.csv",
    "tuning_experiments.csv"
)

$legacyCandidates = @(
    "learning_observations.csv"
)

function New-CategoryBucket {
    param([string]$Name)
    return [ordered]@{
        category = $Name
        file_count = 0
        total_bytes = 0L
        top_files = @()
    }
}

function Add-FileToBucket {
    param(
        [hashtable]$Buckets,
        [string]$BucketName,
        [System.IO.FileInfo]$File,
        [long]$Threshold = 0
    )

    if (-not $Buckets.ContainsKey($BucketName)) {
        $Buckets[$BucketName] = New-CategoryBucket -Name $BucketName
    }

    $bucket = $Buckets[$BucketName]
    $bucket.file_count++
    $bucket.total_bytes += $File.Length

    $entry = [ordered]@{
        path = $File.FullName
        name = $File.Name
        size_bytes = [long]$File.Length
        size_mb = [math]::Round($File.Length / 1MB, 3)
        last_write_time = $File.LastWriteTime.ToString("o")
    }
    if ($Threshold -gt 0) {
        $entry.threshold_mb = [math]::Round($Threshold / 1MB, 3)
        $entry.over_threshold = ($File.Length -ge $Threshold)
    }

    $bucket.top_files = @($bucket.top_files + [pscustomobject]$entry | Sort-Object size_bytes -Descending | Select-Object -First 15)
    $Buckets[$BucketName] = $bucket
}

if (-not (Test-Path -LiteralPath $CommonRoot)) {
    throw "Missing Common root: $CommonRoot"
}

$allFiles = Get-ChildItem -Path $CommonRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch "\\archive\\"
}

$buckets = @{}
$unclassified = New-Object System.Collections.Generic.List[object]

foreach ($file in $allFiles) {
    $name = $file.Name
    if ($file.FullName -match "\\key\\") {
        Add-FileToBucket -Buckets $buckets -BucketName "key_material" -File $file
        continue
    }

    if ($file.FullName -match "\\qdm_import\\") {
        Add-FileToBucket -Buckets $buckets -BucketName "qdm_import_staging" -File $file
        continue
    }

    if ($snapshotNames -contains $name) {
        Add-FileToBucket -Buckets $buckets -BucketName "snapshot_overwrite" -File $file
        continue
    }

    if ($rotatableThresholds.Contains($name)) {
        Add-FileToBucket -Buckets $buckets -BucketName "rotatable_journal" -File $file -Threshold ([long]$rotatableThresholds[$name])
        continue
    }

    if ($preservedLearningNames -contains $name) {
        Add-FileToBucket -Buckets $buckets -BucketName "preserved_learning_memory" -File $file
        continue
    }

    if ($preservedTuningNames -contains $name) {
        Add-FileToBucket -Buckets $buckets -BucketName "preserved_tuning_memory" -File $file
        continue
    }

    if ($legacyCandidates -contains $name) {
        Add-FileToBucket -Buckets $buckets -BucketName "legacy_cleanup_candidate" -File $file
        continue
    }

    $unclassified.Add([pscustomobject]@{
        path = $file.FullName
        name = $file.Name
        size_bytes = [long]$file.Length
        size_mb = [math]::Round($file.Length / 1MB, 3)
        last_write_time = $file.LastWriteTime.ToString("o")
    })
}

$unclassifiedItems = @($unclassified.ToArray() | Sort-Object size_bytes -Descending)
$recommendations = @(
    "Snapshots should stay overwrite-only; they are current state, not history.",
    "Rotatable journals may be archived aggressively because they are operational telemetry, not the system's durable learning memory.",
    "learning_observations_v2.csv and learning_bucket_summary_v1.csv stay preserved because tuning agents read them as local memory.",
    "tuning_reasoning.csv and tuning_experiments.csv are preserved tuning memory; treat them as durable learning context, not runtime trash.",
    "learning_observations.csv is treated as a legacy cleanup candidate and should not keep growing in the new architecture."
)

$result = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    common_root = $CommonRoot
    buckets = @($buckets.Values)
    unclassified_count = $unclassifiedItems.Count
    unclassified_top = @($unclassifiedItems | Select-Object -First 25)
    rotation_thresholds_mb = [ordered]@{
        incident_journal_jsonl = 8
        decision_events_csv = 8
        candidate_signals_csv = 8
        execution_telemetry_csv = 12
        latency_profile_csv = 16
        trade_transactions_jsonl = 12
        tuning_actions_csv = 4
        tuning_deckhand_csv = 4
        tuning_family_actions_csv = 4
        tuning_coordinator_actions_csv = 4
    }
    recommendations = $recommendations
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReport -Encoding UTF8

$lines = @()
$lines += "Runtime persistence audit"
$lines += ""
foreach ($bucket in $result.buckets) {
    $lines += ("[{0}] files={1} total_mb={2}" -f $bucket.category,$bucket.file_count,[math]::Round(($bucket.total_bytes / 1MB),3))
    if ($bucket.top_files.Count -eq 0) {
        $lines += "- none"
    } else {
        foreach ($item in $bucket.top_files) {
            $suffix = ""
            if ($item.PSObject.Properties["threshold_mb"]) {
                $suffix = (" threshold_mb={0} over_threshold={1}" -f $item.threshold_mb,$item.over_threshold)
            }
            $lines += ("- {0} size_mb={1}{2}" -f $item.path,$item.size_mb,$suffix)
        }
    }
    $lines += ""
}

$lines += ("[unclassified] count={0}" -f $result.unclassified_count)
foreach ($item in $result.unclassified_top) {
    $lines += ("- {0} size_mb={1}" -f $item.path,$item.size_mb)
}
$lines += ""
$lines += "recommendations:"
foreach ($item in $recommendations) {
    $lines += ("- {0}" -f $item)
}
$lines | Set-Content -LiteralPath $txtReport -Encoding UTF8

$result | ConvertTo-Json -Depth 8
