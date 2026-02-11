param(
    [string]$Root = "",
    [Parameter(Mandatory = $true)]
    [string]$SnapshotDir,
    [string]$Evidence = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

if (-not [System.IO.Path]::IsPathRooted($SnapshotDir)) {
    $SnapshotDir = [System.IO.Path]::GetFullPath((Join-Path $Root $SnapshotDir))
}
if (-not (Test-Path $SnapshotDir)) {
    Write-Error "Snapshot directory not found: $SnapshotDir"
}

if ([string]::IsNullOrWhiteSpace($Evidence)) {
    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $Evidence = Join-Path $Root "EVIDENCE\tooling_rollback\$runId"
} elseif (-not [System.IO.Path]::IsPathRooted($Evidence)) {
    $Evidence = [System.IO.Path]::GetFullPath((Join-Path $Root $Evidence))
}
New-Item -ItemType Directory -Force -Path $Evidence | Out-Null

$restoreLog = Join-Path $Evidence "restore_log.txt"
"ROLLBACK_START_UTC=$((Get-Date).ToUniversalTime().ToString('o'))" | Set-Content -Encoding UTF8 $restoreLog
"SNAPSHOT=$SnapshotDir" | Add-Content -Encoding UTF8 $restoreLog

$items = Get-ChildItem -Path $SnapshotDir -Recurse -Force
foreach ($item in $items) {
    if ($item.PSIsContainer) { continue }
    $rel = $item.FullName.Substring($SnapshotDir.Length).TrimStart([char]'\', [char]'/')
    $dest = Join-Path $Root $rel
    $destParent = Split-Path $dest -Parent
    if ($destParent) {
        New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    }
    Copy-Item -Path $item.FullName -Destination $dest -Force
    "RESTORED $rel" | Add-Content -Encoding UTF8 $restoreLog
}

"ROLLBACK_STATUS=PASS" | Add-Content -Encoding UTF8 $restoreLog
Write-Host "[ROLLBACK_TOOLING] PASS"
exit 0

