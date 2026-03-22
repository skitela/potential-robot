param(
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$dataDbPath = Join-Path $QdmRoot "user\data\data.db"
$qdmLogDir = Join-Path $QdmRoot "user\log\QuantDataManager"
$qdmLogPath = $null
if (Test-Path -LiteralPath $qdmLogDir) {
    $qdmLogPath = Get-ChildItem -LiteralPath $qdmLogDir -File -Filter "log_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

Write-Host "=== QDM STATUS ==="
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -in @("QuantDataManager_ui", "QDataManager_nocheck", "qdmcli") } |
    Select-Object ProcessName, Id, Path |
    Format-Table -AutoSize

if (Test-Path -LiteralPath $dataDbPath) {
    $pythonCode = @'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT SYMBOL, COUNT(*) FROM DATA GROUP BY SYMBOL ORDER BY SYMBOL")
for symbol, cnt in cur.fetchall():
    print(f"{symbol}|{cnt}")
conn.close()
'@

    Write-Host ""
    Write-Host "=== SYMBOLS IN DATA.DB ==="
    $symbolLines = $pythonCode | & $ResearchPython - $dataDbPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read QDM symbol status from $dataDbPath`n$($symbolLines | Out-String)"
    }
    $symbolLines
}

$latestSyncLog = Get-ChildItem -Path $LogRoot -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "qdm_focus_sync_*.log" -or
        $_.Name -like "qdm_missing_supported_sync_*.log"
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($latestSyncLog) {
    Write-Host ""
    Write-Host "=== LAST FOCUS SYNC LOG ==="
    Write-Host $latestSyncLog.FullName
    Get-Content -Path $latestSyncLog.FullName -Tail 40
}

if (-not [string]::IsNullOrWhiteSpace($qdmLogPath) -and (Test-Path -LiteralPath $qdmLogPath)) {
    Write-Host ""
    Write-Host "=== LAST QDM ENGINE LOG ==="
    Write-Host $qdmLogPath
    Get-Content -Path $qdmLogPath -Tail 40
}
