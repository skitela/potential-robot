param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_focus_pack.csv",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [switch]$StopExistingQdm = $true,
    [int]$IdleTimeoutSeconds = 14400,
    [int]$MinRefreshHours = 24,
    [switch]$ForceUpdate
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
if (-not (Test-Path -LiteralPath $ResearchPython)) {
    throw "Research python not found: $ResearchPython"
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
             $_.CommandLine -like "*START_QDM_FOCUS_SYNC_BACKGROUND.ps1*" -or
             $_.CommandLine -like "*START_QDM_FOCUS_PIPELINE_BACKGROUND.ps1*")
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Start-Sleep -Seconds 2
}

function Wait-QdmIdle {
    param(
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $running = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -in @("qdmcli", "QDataManager_nocheck", "QuantDataManager_ui") }

        if (-not $running) {
            return
        }

        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    $details = $running | Select-Object ProcessName, Id, Path | Format-Table -AutoSize | Out-String
    throw "QDM did not become idle within $TimeoutSeconds seconds.`n$details"
}

function Get-QdmExistingSymbols {
    param(
        [string]$DatabasePath,
        [string]$PythonExe
    )

    if (-not (Test-Path -LiteralPath $DatabasePath)) {
        return @()
    }

    $pythonCode = @'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT SYMBOL FROM DATA ORDER BY SYMBOL")
for row in cur.fetchall():
    print(row[0])
conn.close()
'@

    $symbols = $pythonCode | & $PythonExe - $DatabasePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read existing QDM symbols from $DatabasePath`n$($symbols | Out-String)"
    }
    return @($symbols)
}

function Get-QdmHistoryCandidates {
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
    Wait-QdmIdle -TimeoutSeconds 60
}

$dataDbPath = Join-Path $QdmRoot "user\data\data.db"
$historyRoot = Join-Path $QdmRoot "user\data\History"
$existingSymbols = @(Get-QdmExistingSymbols -DatabasePath $dataDbPath -PythonExe $ResearchPython)
$rows = @(Import-Csv -LiteralPath $ProfilePath | Where-Object { $_.enabled -eq "1" })
foreach ($row in $rows) {
    $symbol = $row.symbol.Trim()
    $datasource = $row.datasource.Trim()
    $datatype = $row.datatype.Trim()

    if ($existingSymbols -contains $symbol) {
        Write-Host "Symbol already exists in QDM, skipping add: $symbol"
    }
    else {
        Write-Host "Adding symbol definition: $symbol ($datasource/$datatype)"
        & $qdmCli -symbol action=add "symbols=$symbol" "datasource=$datasource" "datatype=$datatype"
        Wait-QdmIdle -TimeoutSeconds $IdleTimeoutSeconds
        $existingSymbols += $symbol
    }

    $historyCandidates = @(Get-QdmHistoryCandidates -HistoryRoot $historyRoot -Symbol $symbol -Datatype $datatype)
    if (-not $ForceUpdate -and $historyCandidates.Count -gt 0) {
        $latestHistory = $historyCandidates[0]
        $hoursSinceRefresh = ((Get-Date) - $latestHistory.LastWriteTime).TotalHours
        if ($hoursSinceRefresh -lt $MinRefreshHours) {
            Write-Host ("Skipping historical update: {0} (recent history file {1}, age {2:N1}h, threshold {3}h)" -f
                $symbol,
                $latestHistory.Name,
                $hoursSinceRefresh,
                $MinRefreshHours)
            continue
        }
    }

    # QDM CLI currently pulls broad source history on update for these symbols,
    # so we throttle updates here and keep fine date windows only on export.
    Write-Host "Updating historical data: $symbol"
    & $qdmCli -data action=update "symbols=$symbol"
    Wait-QdmIdle -TimeoutSeconds $IdleTimeoutSeconds
}
