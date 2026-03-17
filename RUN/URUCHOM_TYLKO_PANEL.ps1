param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$panelPath = Join-Path $ProjectRoot "RUN\PANEL_OPERATORA_PL.ps1"

if (-not (Test-Path -LiteralPath $panelPath)) {
    Write-Warning "Nie znaleziono pliku: $panelPath"
    exit 1
}

Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-ExecutionPolicy", "Bypass",
    "-File", $panelPath
)
