Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        ($_.CommandLine -like "*qdm_focus_sync_wrapper_*" -or
         $_.CommandLine -like "*SYNC_QDM_FOCUS_PACK.ps1*" -or
         $_.CommandLine -like "*START_QDM_FOCUS_SYNC_BACKGROUND.ps1*")
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -in @("qdmcli", "QDataManager_nocheck", "QuantDataManager_ui") } |
    Stop-Process -Force

Start-Sleep -Seconds 2

Write-Host "QDM focus sync stopped."
