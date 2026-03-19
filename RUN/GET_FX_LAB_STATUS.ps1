Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== FX LAB POWERSHELL WRAPPERS ==="
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        ($_.CommandLine -like "*fx_mt5_batch_wrapper_*" -or
         $_.CommandLine -like "*fx_qdm_pipeline_wrapper_*" -or
         $_.CommandLine -like "*refresh_and_train_ml_wrapper_*" -or
         $_.CommandLine -like "*qdm_focus_sync_wrapper_*" -or
         $_.CommandLine -like "*qdm_export_after_sync_wrapper_*")
    } |
    Select-Object ProcessId, CommandLine |
    Format-List

Write-Host ""
Write-Host "=== MT5 / QDM PROCESSES ==="
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -in @("terminal64", "metatester64", "qdmcli", "QDataManager_nocheck", "QuantDataManager_ui", "python") } |
    Select-Object ProcessName, Id, PriorityClass, WorkingSet64, Path |
    Format-Table -AutoSize
