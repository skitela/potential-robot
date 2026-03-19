param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tuningScript = Join-Path $ProjectRoot "RUN\APPLY_WORKSTATION_PERF_TUNING.ps1"
$primaryMt5 = Join-Path $ProjectRoot "RUN\START_FX_MT5_BATCH_BACKGROUND.ps1"
$secondaryMt5 = Join-Path $ProjectRoot "RUN\START_FX_MT5_SECONDARY_BATCH_BACKGROUND.ps1"
$ml = Join-Path $ProjectRoot "RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1"
$qdm = Join-Path $ProjectRoot "RUN\START_QDM_EXPORT_AFTER_SYNC_BACKGROUND.ps1"

foreach ($path in @($tuningScript, $primaryMt5, $secondaryMt5, $ml, $qdm)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

Write-Host "Applying workstation tuning for 90% lab..."
& $tuningScript -ThrottleInteractiveApps -MlPerfProfile "ConcurrentLab" | Out-Host

Write-Host "Starting lane 1/4: OANDA MT5 broker-faithful batch..."
& $primaryMt5

Write-Host "Starting lane 2/4: secondary MT5 offline/custom-ready batch..."
& $secondaryMt5

$qdmWatcherRunning = (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        $_.CommandLine -like "*qdm_export_after_sync_wrapper_*"
    } |
    Measure-Object).Count -gt 0

if ($qdmWatcherRunning) {
    Write-Host "Lane 3/4: QDM export-after-sync watcher is already active."
} else {
    Write-Host "Starting lane 3/4: QDM export-after-sync watcher..."
    & $qdm
}

Write-Host "Starting lane 4/4: research ML refresh+train..."
& $ml

Write-Host "Parallel 90% lab launch finished."
