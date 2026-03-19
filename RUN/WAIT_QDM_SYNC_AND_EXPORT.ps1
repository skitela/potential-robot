param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$PollSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$exportScript = Join-Path $ProjectRoot "RUN\EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1"
if (-not (Test-Path -LiteralPath $exportScript)) {
    throw "Export script not found: $exportScript"
}

Write-Host "Waiting for active QDM focus sync to finish..."

while ($true) {
    $syncWrappers = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "powershell.exe" -and
            ($_.CommandLine -like "*qdm_focus_sync_wrapper_*" -or
             $_.CommandLine -like "*SYNC_QDM_FOCUS_PACK.ps1*" -or
             $_.CommandLine -like "*RUN_QDM_FOCUS_PIPELINE.ps1*" -or
             $_.CommandLine -like "*qdm_focus_pipeline_wrapper_*")
        }

    $qdmWorkers = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -in @("qdmcli", "QDataManager_nocheck", "QuantDataManager_ui") }

    if (-not $syncWrappers -and -not $qdmWorkers) {
        break
    }

    $wrapperCount = @($syncWrappers).Count
    $workerCount = @($qdmWorkers).Count
    Write-Host "Still running: wrappers=$wrapperCount qdm_processes=$workerCount"
    Start-Sleep -Seconds $PollSeconds
}

Write-Host "QDM sync finished. Starting MT5 export..."
& $exportScript

Write-Host "QDM export after sync finished."
