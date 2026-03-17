param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$launcherPath = Join-Path $ProjectRoot "RUN\URUCHOM_PANEL_I_DASHBOARD.ps1"
$mt5Path = Join-Path $ProjectRoot "RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1"

if (Test-Path -LiteralPath $mt5Path) {
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-ExecutionPolicy", "Bypass",
        "-File", $mt5Path
    ) -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

if (-not (Test-Path -LiteralPath $launcherPath)) {
    Write-Warning "Nie znaleziono pliku: $launcherPath"
    exit 1
}

Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-ExecutionPolicy", "Bypass",
    "-File", $launcherPath
)
