param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_focus_pack.csv",
    [string]$OutputRoot = "C:\TRADING_DATA\QDM_EXPORT\MT5",
    [string]$StagingRoot = "C:\TRADING_DATA\QDM_EXPORT\MT5\_staging",
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

function Get-HistoryCandidates {
    param(
        [string]$HistoryRoot,
        [string]$Symbol,
        [string]$Datatype
    )

    $symbolDir = Join-Path $HistoryRoot $Symbol
    if (-not (Test-Path -LiteralPath $symbolDir)) {
        return @()
    }

    $baseName = "{0}_{1}.dat" -f $Symbol, $Datatype
    return @(
        Get-ChildItem -LiteralPath $symbolDir -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.PSIsContainer -and
                ($_.Name -eq $baseName -or $_.Name -eq ($baseName + ".copy"))
            } |
            Sort-Object LastWriteTime -Descending
    )
}

if ($StopExistingQdm) {
    Stop-QdmProcesses
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $StagingRoot | Out-Null

$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runStagingRoot = Join-Path $StagingRoot $runStamp
New-Item -ItemType Directory -Force -Path $runStagingRoot | Out-Null
$lockPath = Join-Path $StagingRoot "active_export.lock.json"

$rows = Import-Csv -LiteralPath $ProfilePath | Where-Object { $_.enabled -eq "1" }
$historyRoot = Join-Path $QdmRoot "user\data\History"
foreach ($row in $rows) {
    $symbol = $row.symbol.Trim()
    $exportName = $row.mt5_export_name.Trim()
    $datatype = if ([string]::IsNullOrWhiteSpace($row.datatype)) { "TICK" } else { $row.datatype.Trim() }
    $historyCandidates = @(Get-HistoryCandidates -HistoryRoot $historyRoot -Symbol $symbol -Datatype $datatype)

    if ($historyCandidates.Count -eq 0) {
        Write-Warning "Skipping export for $symbol - history file missing in $historyRoot"
        continue
    }

    $historyInfo = $historyCandidates[0]
    if ($historyInfo.Length -le 0) {
        Write-Warning "Skipping export for $symbol - history file is empty: $($historyInfo.FullName)"
        continue
    }

    $tempStem = "{0}__TMP_{1}" -f $exportName, $runStamp
    $tempFile = Join-Path $runStagingRoot ($tempStem + ".csv")
    $finalFile = Join-Path $OutputRoot ($exportName + ".csv")

    $lockPayload = [ordered]@{
        schema_version = "1.0"
        state = "EXPORTING"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        symbol = $symbol
        export_name = $exportName
        history_path = $historyInfo.FullName
        temp_file = $tempFile
        final_file = $finalFile
    }
    $lockPayload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $lockPath -Encoding UTF8

    $arguments = @(
        "-data",
        "action=exportToMT5",
        "symbol=$symbol",
        "timeframe=TICK",
        "outputdir=$runStagingRoot",
        "filename=$tempStem"
    )

    if (-not [string]::IsNullOrWhiteSpace($row.date_from)) {
        $arguments += "datefrom=$($row.date_from.Trim())"
    }
    if (-not [string]::IsNullOrWhiteSpace($row.date_to)) {
        $arguments += "dateto=$($row.date_to.Trim())"
    }

    Write-Host "Exporting to MT5 format: $symbol -> $exportName using $($historyInfo.Name)"
    try {
        & $qdmCli @arguments
        if (-not (Test-Path -LiteralPath $tempFile)) {
            throw "Temporary export file missing after qdmcli run: $tempFile"
        }

        $tempInfo = Get-Item -LiteralPath $tempFile -ErrorAction Stop
        if ($tempInfo.Length -le 0) {
            throw "Temporary export file is empty: $tempFile"
        }

        Move-Item -LiteralPath $tempFile -Destination $finalFile -Force
    }
    finally {
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
}
