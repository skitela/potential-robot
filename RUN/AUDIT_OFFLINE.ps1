param(
    [string]$Root = "",
    [string]$Evidence = "",
    [switch]$PrintSummary,
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
    $Evidence = Join-Path $Root "EVIDENCE\dyrygent_smoke\$runId"
} elseif (-not [System.IO.Path]::IsPathRooted($Evidence)) {
    $Evidence = [System.IO.Path]::GetFullPath((Join-Path $Root $Evidence))
} else {
    $Evidence = [System.IO.Path]::GetFullPath($Evidence)
}

New-Item -ItemType Directory -Force -Path $Evidence | Out-Null

$env:DYRYGENT_ROOT = $Root
$env:DYRYGENT_EVIDENCE_DIR = $Evidence

$dyrygentPath = Join-Path $Root "DYRYGENT_EXTERNAL.py"
if (-not (Test-Path $dyrygentPath)) {
    Write-Error "DYRYGENT_EXTERNAL.py not found at $dyrygentPath"
}

$args = @(
    $dyrygentPath,
    "--dry-run",
    "--mode", "OFFLINE",
    "--root", $Root,
    "--evidence-dir", $Evidence
)

if ($PrintSummary) {
    $args += "--print-summary"
}

Write-Host "[AUDIT_OFFLINE] Root=$Root"
Write-Host "[AUDIT_OFFLINE] Evidence=$Evidence"
Write-Host "[AUDIT_OFFLINE] Mode=OFFLINE"

& python @args
$exitCode = $LASTEXITCODE

if (-not $NoSync) {
    $syncScript = Join-Path $PSScriptRoot "SYNC_EVIDENCE.ps1"
    $syncSource = Join-Path $Root "EVIDENCE"
    if (-not (Test-Path $syncScript)) {
        Write-Warning "[AUDIT_OFFLINE] Sync script missing: $syncScript"
        if ($exitCode -eq 0) {
            $exitCode = 91
        }
    } else {
        Write-Host "[AUDIT_OFFLINE] SyncSource=$syncSource"
        Write-Host "[AUDIT_OFFLINE] SyncTarget=$SyncTarget"
        powershell -ExecutionPolicy Bypass -File $syncScript -SourceEvidence $syncSource -TargetEvidence $SyncTarget
        $syncExit = $LASTEXITCODE
        Write-Host "[AUDIT_OFFLINE] SyncExitCode=$syncExit"
        if ($syncExit -ne 0 -and $exitCode -eq 0) {
            $exitCode = $syncExit
        }
    }
}

Write-Host "[AUDIT_OFFLINE] ExitCode=$exitCode"
exit $exitCode
