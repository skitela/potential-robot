param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$toolPath = Join-Path $ProjectRoot "TOOLS\RUN_OVERNIGHT_TUNING_SUPERVISOR.ps1"
if (-not (Test-Path -LiteralPath $toolPath)) {
    throw "Brak supervisora nocnego: $toolPath"
}

Get-CimInstance Win32_Process |
    Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*RUN_OVERNIGHT_TUNING_SUPERVISOR.ps1*' } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

Start-Process powershell -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $toolPath,
    "-ProjectRoot", $ProjectRoot
) | Out-Null

Start-Sleep -Seconds 2

$screenPath = Join-Path $ProjectRoot "EVIDENCE\overnight_tuning_supervisor_screen.txt"
if (Test-Path -LiteralPath $screenPath) {
    Get-Content -LiteralPath $screenPath -Raw -Encoding UTF8
}

$operatorTablePath = Join-Path $ProjectRoot "EVIDENCE\overnight_tuning_supervisor_operator_table.txt"
if (Test-Path -LiteralPath $operatorTablePath) {
    ""
    Get-Content -LiteralPath $operatorTablePath -Raw -Encoding UTF8
}
