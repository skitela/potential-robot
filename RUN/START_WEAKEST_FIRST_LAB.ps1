param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$priorityScript = Join-Path $ProjectRoot "RUN\BUILD_TUNING_PRIORITY_REPORT.ps1"
$opsArchiver = Join-Path $ProjectRoot "RUN\START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1"
$mt5Batch = Join-Path $ProjectRoot "RUN\START_WEAKEST_MT5_BATCH_BACKGROUND.ps1"
$qdmBatch = Join-Path $ProjectRoot "RUN\START_QDM_WEAKEST_SYNC_BACKGROUND.ps1"

foreach ($path in @($priorityScript, $opsArchiver, $mt5Batch, $qdmBatch)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

Write-Host "Building fresh weakest-first priority report..."
& $priorityScript | Out-Null

Write-Host "Starting local operator archiver..."
& $opsArchiver

Write-Host "Starting weakest-first MT5 batch..."
& $mt5Batch

$qdmRunning = (Get-Process -Name qdmcli -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
if ($qdmRunning) {
    Write-Host "QDM is already running. Skipping second weakest sync launch."
}
else {
    Write-Host "Starting weakest-first QDM sync..."
    & $qdmBatch
}

Write-Host "Weakest-first lab launch finished."
