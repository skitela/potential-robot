param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$PollSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$startScript = Join-Path $ProjectRoot "RUN\START_QDM_FX_FULL_SYNC_BACKGROUND.ps1"
if (-not (Test-Path -LiteralPath $startScript)) {
    throw "FX full QDM start script not found: $startScript"
}

Write-Host "Waiting for active QDM workers to become idle before FX full sync..."

while ($true) {
    $qdmWorkers = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -in @("qdmcli", "QDataManager_nocheck", "QuantDataManager_ui") }

    if (-not $qdmWorkers) {
        break
    }

    Write-Host ("Still running: qdm_processes={0}" -f @($qdmWorkers).Count)
    Start-Sleep -Seconds $PollSeconds
}

Write-Host "QDM is idle. Starting FX full sync..."
& $startScript

Write-Host "FX full QDM sync watcher finished."
