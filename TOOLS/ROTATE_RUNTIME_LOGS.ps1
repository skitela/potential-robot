param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [int]$MinAgeMinutes = 30,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$evidenceDir = Join-Path $ProjectRoot "EVIDENCE"
$jsonReport = Join-Path $evidenceDir "runtime_log_rotation_report.json"
$txtReport = Join-Path $evidenceDir "runtime_log_rotation_report.txt"
$logsRoot = Join-Path $CommonRoot "logs"

$thresholdByName = @{
    "incident_journal.jsonl"      = 8MB
    "decision_events.csv"         = 8MB
    "candidate_signals.csv"       = 8MB
    "execution_telemetry.csv"     = 12MB
    "latency_profile.csv"         = 16MB
    "trade_transactions.jsonl"    = 12MB
    "tuning_actions.csv"          = 4MB
    "tuning_deckhand.csv"         = 4MB
    "tuning_family_actions.csv"   = 4MB
    "tuning_coordinator_actions.csv" = 4MB
}

function New-PlaceholderFile {
    param([string]$Path)

    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $logsRoot)) {
    throw "Missing logs root: $logsRoot"
}

$cutoff = (Get-Date).AddMinutes(-1 * [Math]::Abs($MinAgeMinutes))
$candidates = New-Object System.Collections.Generic.List[object]
$rotated = New-Object System.Collections.Generic.List[object]

$files = Get-ChildItem -Path $logsRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch "\\archive\\"
}

foreach ($file in $files) {
    if (-not $thresholdByName.ContainsKey($file.Name)) {
        continue
    }

    $threshold = [long]$thresholdByName[$file.Name]
    if ($file.Length -lt $threshold) {
        continue
    }

    if ($file.LastWriteTime -gt $cutoff) {
        continue
    }

    $symbolDir = Split-Path -Path $file.FullName -Parent
    $archiveDir = Join-Path $symbolDir ("archive\{0}" -f (Get-Date).ToString("yyyyMMdd_HHmmss"))
    $archivePath = Join-Path $archiveDir $file.Name

    $entry = [ordered]@{
        path = $file.FullName
        name = $file.Name
        size_bytes = $file.Length
        size_mb = [math]::Round($file.Length / 1MB, 3)
        threshold_mb = [math]::Round($threshold / 1MB, 3)
        last_write_time = $file.LastWriteTime.ToString("o")
        archive_path = $archivePath
    }
    $candidates.Add([pscustomobject]$entry)

    if ($Apply) {
        New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
        Move-Item -LiteralPath $file.FullName -Destination $archivePath -Force
        New-PlaceholderFile -Path $file.FullName
        $rotated.Add([pscustomobject]$entry)
    }
}

$candidateItems = @($candidates.ToArray())
$rotatedItems = @($rotated.ToArray())

$report = [pscustomobject]@{
    schema_version = "1.1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    common_root = $CommonRoot
    apply_mode = [bool]$Apply
    min_age_minutes = [Math]::Abs($MinAgeMinutes)
    thresholds_mb = [pscustomobject]@{
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
    candidates = $candidateItems
    rotated = $rotatedItems
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReport -Encoding UTF8

$lines = @()
$lines += "Runtime log rotation"
$lines += "apply_mode=$([bool]$Apply)"
$lines += "min_age_minutes=$([Math]::Abs($MinAgeMinutes))"
$lines += ""
$lines += "candidates:"
if ($candidates.Count -eq 0) {
    $lines += "- none"
}
else {
    foreach ($item in $candidates) {
        $lines += ("- {0} size_mb={1} threshold_mb={2} archive={3}" -f $item.path,$item.size_mb,$item.threshold_mb,$item.archive_path)
    }
}
$lines += ""
$lines += "rotated:"
if ($rotated.Count -eq 0) {
    $lines += "- none"
}
else {
    foreach ($item in $rotated) {
        $lines += ("- {0}" -f $item.path)
    }
}
$lines | Set-Content -LiteralPath $txtReport -Encoding UTF8

$report | ConvertTo-Json -Depth 8
