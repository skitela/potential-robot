param(
    [string]$Root = "",
    [string]$Evidence = "",
    [string]$SnapshotDir = "",
    [switch]$AutoRollbackOnFail,
    [string]$SyncTarget = "C:\agentkotweight\EVIDENCE",
    [switch]$NoSync
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

if ([string]::IsNullOrWhiteSpace($Evidence)) {
    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $Evidence = Join-Path $Root "EVIDENCE\tooling_canary\$runId"
} elseif (-not [System.IO.Path]::IsPathRooted($Evidence)) {
    $Evidence = [System.IO.Path]::GetFullPath((Join-Path $Root $Evidence))
} else {
    $Evidence = [System.IO.Path]::GetFullPath($Evidence)
}

New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
if ([string]::IsNullOrWhiteSpace($SnapshotDir)) {
    $SnapshotDir = Join-Path $Evidence "snapshot"
} elseif (-not [System.IO.Path]::IsPathRooted($SnapshotDir)) {
    $SnapshotDir = [System.IO.Path]::GetFullPath((Join-Path $Root $SnapshotDir))
}
New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null

$targets = @(
    "DYRYGENT_EXTERNAL.py",
    "RUN\\AUDIT_OFFLINE.ps1",
    "RUN\\AUDIT_TRAINING_OFFLINE.ps1",
    "RUN\\PREFLIGHT_SAFE.ps1",
    "RUN\\SYNC_EVIDENCE.ps1",
    "TOOLS",
    "SCHEMAS\\api_contracts_v1.json",
    "tests\\test_api_contracts.py",
    "tests\\test_offline_network_guard.py",
    "tests\\test_runtime_housekeeping.py"
)

$snapshotLog = Join-Path $Evidence "snapshot.txt"
"SNAPSHOT_START_UTC=$((Get-Date).ToUniversalTime().ToString('o'))" | Set-Content -Encoding UTF8 $snapshotLog

foreach ($rel in $targets) {
    $src = Join-Path $Root $rel
    if (-not (Test-Path $src)) {
        "SKIP_MISSING $rel" | Add-Content -Encoding UTF8 $snapshotLog
        continue
    }
    $dst = Join-Path $SnapshotDir $rel
    $dstParent = Split-Path $dst -Parent
    if ($dstParent) {
        New-Item -ItemType Directory -Force -Path $dstParent | Out-Null
    }
    Copy-Item -Path $src -Destination $dst -Recurse -Force
    "SNAPSHOT_OK $rel" | Add-Content -Encoding UTF8 $snapshotLog
}

$preflightEvidence = Join-Path $Evidence "preflight"
powershell -ExecutionPolicy Bypass -File (Join-Path $Root "RUN\\PREFLIGHT_SAFE.ps1") -Root $Root -Evidence $preflightEvidence -Loops 1 -NoSync
$preflightExit = $LASTEXITCODE

$verdictPath = Join-Path $Evidence "canary_verdict.txt"
"PREFLIGHT_EXIT=$preflightExit" | Set-Content -Encoding UTF8 $verdictPath

if ($preflightExit -ne 0 -and $AutoRollbackOnFail) {
    powershell -ExecutionPolicy Bypass -File (Join-Path $Root "RUN\\ROLLBACK_TOOLING.ps1") -Root $Root -SnapshotDir $SnapshotDir -Evidence (Join-Path $Evidence "rollback")
    $rollbackExit = $LASTEXITCODE
    "ROLLBACK_EXIT=$rollbackExit" | Add-Content -Encoding UTF8 $verdictPath
}

if (-not $NoSync) {
    powershell -ExecutionPolicy Bypass -File (Join-Path $Root "RUN\\SYNC_EVIDENCE.ps1") -SourceEvidence (Join-Path $Root "EVIDENCE") -TargetEvidence $SyncTarget
    "SYNC_EXIT=$LASTEXITCODE" | Add-Content -Encoding UTF8 $verdictPath
}

if ($preflightExit -eq 0) {
    "STATUS=PASS" | Add-Content -Encoding UTF8 $verdictPath
    exit 0
}

"STATUS=FAIL" | Add-Content -Encoding UTF8 $verdictPath
exit $preflightExit
