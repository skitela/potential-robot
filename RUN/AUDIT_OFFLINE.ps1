param(
    [string]$Root = "",
    [string]$Evidence = "",
    [switch]$PrintSummary,
    [string]$SyncTarget = "C:\agentkotweight\EVIDENCE",
    [switch]$NoSync,
    [switch]$SkipHousekeeping
)

$ErrorActionPreference = "Stop"

function Resolve-PythonExe {
    param([string]$RuntimeRoot)
    $candidates = @(
        (Join-Path $RuntimeRoot ".venv\Scripts\python.exe"),
        "C:\OANDA_VENV\.venv\Scripts\python.exe",
        "C:\Program Files\Python312\python.exe"
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
    }
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
        return $cmd.Source
    }
    throw "Python executable not found for AUDIT_OFFLINE."
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}
$pythonExe = Resolve-PythonExe -RuntimeRoot $Root

if ([string]::IsNullOrWhiteSpace($Evidence)) {
    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $Evidence = Join-Path $Root "EVIDENCE\dyrygent_smoke\$runId"
} elseif (-not [System.IO.Path]::IsPathRooted($Evidence)) {
    $Evidence = [System.IO.Path]::GetFullPath((Join-Path $Root $Evidence))
} else {
    $Evidence = [System.IO.Path]::GetFullPath($Evidence)
}

New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
$runId = Split-Path $Evidence -Leaf
$runLog = Join-Path $Evidence "runlog.jsonl"

function Append-RunLog {
    param(
        [string]$Event,
        [hashtable]$Fields = @{}
    )
    $record = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        event = $Event
        run_id = $runId
    }
    foreach ($k in $Fields.Keys) {
        $record[$k] = $Fields[$k]
    }
    ($record | ConvertTo-Json -Compress) | Add-Content -Encoding UTF8 $runLog
}

$env:DYRYGENT_ROOT = $Root
$env:DYRYGENT_EVIDENCE_DIR = $Evidence
$env:DYRYGENT_RUN_LOG = $runLog

$dyrygentPath = Join-Path $Root "DYRYGENT_EXTERNAL.py"
if (-not (Test-Path $dyrygentPath)) {
    Write-Error "DYRYGENT_EXTERNAL.py not found at $dyrygentPath"
}

$args = @(
    $dyrygentPath,
    "--dry-run",
    "--mode", "OFFLINE",
    "--root", $Root,
    "--evidence-dir", $Evidence,
    "--run-log", $runLog
)

if ($PrintSummary) {
    $args += "--print-summary"
}

Write-Host "[AUDIT_OFFLINE] Root=$Root"
Write-Host "[AUDIT_OFFLINE] Evidence=$Evidence"
Write-Host "[AUDIT_OFFLINE] Mode=OFFLINE"
Write-Host "[AUDIT_OFFLINE] Python=$pythonExe"
Append-RunLog -Event "audit_offline_start" -Fields @{
    root = $Root
    evidence = $Evidence
    mode = "OFFLINE"
    python = $pythonExe
}

if (-not $SkipHousekeeping) {
    $housekeepingReport = Join-Path $Evidence "housekeeping_report.json"
    & $pythonExe (Join-Path $Root "TOOLS\runtime_housekeeping.py") --root $Root --evidence $housekeepingReport --apply --keep-runs 10 --keep-audit-v12-runs 8 --keep-gates 200 --max-single-log-mb 8
    $hkExit = $LASTEXITCODE
    Append-RunLog -Event "housekeeping_done" -Fields @{ exit_code = $hkExit; report = $housekeepingReport }
    if ($hkExit -ne 0) {
        Write-Warning "[AUDIT_OFFLINE] Housekeeping failed with exit code $hkExit"
    }
}

& $pythonExe @args
$exitCode = $LASTEXITCODE
Append-RunLog -Event "dyrygent_finished" -Fields @{ exit_code = $exitCode }

if (-not $NoSync) {
    $syncScript = Join-Path $PSScriptRoot "SYNC_EVIDENCE.ps1"
    $syncSource = Join-Path $Root "EVIDENCE"
    if (-not (Test-Path $syncScript)) {
        Write-Warning "[AUDIT_OFFLINE] Sync script missing: $syncScript"
        Append-RunLog -Event "sync_missing" -Fields @{ script = $syncScript }
        if ($exitCode -eq 0) {
            $exitCode = 91
        }
    } else {
        Write-Host "[AUDIT_OFFLINE] SyncSource=$syncSource"
        Write-Host "[AUDIT_OFFLINE] SyncTarget=$SyncTarget"
        powershell -ExecutionPolicy Bypass -File $syncScript -SourceEvidence $syncSource -TargetEvidence $SyncTarget
        $syncExit = $LASTEXITCODE
        Write-Host "[AUDIT_OFFLINE] SyncExitCode=$syncExit"
        Append-RunLog -Event "sync_finished" -Fields @{ exit_code = $syncExit; target = $SyncTarget }
        if ($syncExit -ne 0 -and $exitCode -eq 0) {
            $exitCode = $syncExit
        }
    }
}

Write-Host "[AUDIT_OFFLINE] ExitCode=$exitCode"
Append-RunLog -Event "audit_offline_end" -Fields @{ exit_code = $exitCode }
exit $exitCode
