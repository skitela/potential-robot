param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_focus_pack.csv",
    [string]$OutputRoot = "C:\TRADING_DATA\QDM_EXPORT\MT5",
    [switch]$StopExistingQdm = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$qdmCli = Join-Path $QdmRoot "qdmcli.exe"
if (-not (Test-Path -LiteralPath $qdmCli)) {
    throw "QDM CLI not found: $qdmCli"
}
if (-not (Test-Path -LiteralPath $ProfilePath)) {
    throw "QDM profile not found: $ProfilePath"
}

function Stop-QdmProcesses {
    $names = @("qdmcli", "QDataManager_nocheck", "QuantDataManager_ui")
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $names -contains $_.ProcessName } |
        Stop-Process -Force

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "powershell.exe" -and
            $_.ProcessId -ne $PID -and
            ($_.CommandLine -like "*qdm_focus_sync_wrapper_*" -or
             $_.CommandLine -like "*qdm_focus_pipeline_wrapper_*" -or
             $_.CommandLine -like "*SYNC_QDM_FOCUS_PACK.ps1*" -or
             $_.CommandLine -like "*RUN_QDM_FOCUS_PIPELINE.ps1*" -or
             $_.CommandLine -like "*EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1*" -or
             $_.CommandLine -like "*START_QDM_FOCUS_PIPELINE_BACKGROUND.ps1*")
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Start-Sleep -Seconds 2
}

if ($StopExistingQdm) {
    Stop-QdmProcesses
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$rows = Import-Csv -LiteralPath $ProfilePath | Where-Object { $_.enabled -eq "1" }
foreach ($row in $rows) {
    $symbol = $row.symbol.Trim()
    $exportName = $row.mt5_export_name.Trim()
    $historyFile = Join-Path $QdmRoot ("user\data\History\{0}\{0}_TICK.dat" -f $symbol)

    if (-not (Test-Path -LiteralPath $historyFile)) {
        Write-Warning "Skipping export for $symbol - history file missing: $historyFile"
        continue
    }

    $historyInfo = Get-Item -LiteralPath $historyFile -ErrorAction Stop
    if ($historyInfo.Length -le 0) {
        Write-Warning "Skipping export for $symbol - history file is empty: $historyFile"
        continue
    }

    $arguments = @(
        "-data",
        "action=exportToMT5",
        "symbol=$symbol",
        "timeframe=TICK",
        "outputdir=$OutputRoot",
        "filename=$exportName"
    )

    if (-not [string]::IsNullOrWhiteSpace($row.date_from)) {
        $arguments += "datefrom=$($row.date_from.Trim())"
    }
    if (-not [string]::IsNullOrWhiteSpace($row.date_to)) {
        $arguments += "dateto=$($row.date_to.Trim())"
    }

    Write-Host "Exporting to MT5 format: $symbol -> $exportName"
    & $qdmCli @arguments
}
