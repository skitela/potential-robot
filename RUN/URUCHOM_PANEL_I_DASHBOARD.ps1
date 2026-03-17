param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = "Stop"

function Open-IfExists {
    param(
        [string]$Path,
        [switch]$AsPowerShell
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Nie znaleziono pliku: $Path"
        return
    }

    if ($AsPowerShell) {
        Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", $Path
        )
        return
    }

    Start-Process -FilePath $Path
}

$panelPath = Join-Path $ProjectRoot "RUN\PANEL_OPERATORA_PL.ps1"
$dailyDashboardPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\dashboard_dzienny_latest.html"
$eveningDashboardPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\dashboard_wieczorny_latest.html"

Open-IfExists -Path $panelPath -AsPowerShell
Start-Sleep -Milliseconds 300
Open-IfExists -Path $dailyDashboardPath
Start-Sleep -Milliseconds 300
Open-IfExists -Path $eveningDashboardPath
