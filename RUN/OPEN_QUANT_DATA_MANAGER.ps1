param(
    [string]$InstallRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [switch]$StopExistingQdm = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-QdmProcesses {
    $names = @("qdmcli", "QDataManager_nocheck", "QuantDataManager_ui")
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $names -contains $_.ProcessName } |
        Stop-Process -Force
    Start-Sleep -Seconds 2
}

$exePath = Join-Path $InstallRoot "QuantDataManager.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "QuantDataManager.exe not found: $exePath"
}

if ($StopExistingQdm) {
    Stop-QdmProcesses
}

Start-Process -FilePath $exePath -WorkingDirectory $InstallRoot
