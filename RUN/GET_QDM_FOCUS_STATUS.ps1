param(
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$dataDbPath = Join-Path $QdmRoot "user\data\data.db"
$qdmLogPath = Join-Path $QdmRoot "user\log\QuantDataManager\log_2026_03_19.log"

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

$latestSyncLog = Get-ChildItem -Path $LogRoot -Filter "qdm_focus_sync_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($latestSyncLog) {
    Write-Host ""
    Write-Host "=== LAST FOCUS SYNC LOG ==="
    Write-Host $latestSyncLog.FullName
    Get-Content -Path $latestSyncLog.FullName -Tail 40
}

if (Test-Path -LiteralPath $qdmLogPath) {
    Write-Host ""
    Write-Host "=== LAST QDM ENGINE LOG ==="
    Get-Content -Path $qdmLogPath -Tail 40
}
