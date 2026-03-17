param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

function Open-IfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Nie znaleziono pliku: $Path"
        return
    }
    Start-Process -FilePath $Path
}

$dailyDashboardPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\dashboard_dzienny_latest.html"
$eveningDashboardPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\dashboard_wieczorny_latest.html"

Open-IfExists -Path $dailyDashboardPath
Start-Sleep -Milliseconds 300
Open-IfExists -Path $eveningDashboardPath
