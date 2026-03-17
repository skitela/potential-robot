param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$dashboardPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\dashboard_dzienny_latest.html"

if (-not (Test-Path -LiteralPath $dashboardPath)) {
    Write-Warning "Nie znaleziono pliku: $dashboardPath"
    exit 1
}

Start-Process -FilePath $dashboardPath
