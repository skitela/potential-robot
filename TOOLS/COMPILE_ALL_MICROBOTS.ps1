param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ServerName = "OANDATMS-MT5",
    [switch]$CopySourcesToTerminal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$registryPath = Join-Path $ProjectRoot "CONFIG\\microbots_registry.json"
$registry = Get-Content -LiteralPath $registryPath -Encoding UTF8 | ConvertFrom-Json

$results = @()
foreach ($item in $registry.symbols) {
    $expert = [string]$item.expert
    $scriptPath = Join-Path $ProjectRoot "TOOLS\\COMPILE_MICROBOT.ps1"
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $scriptPath,
        "-ProjectRoot", $ProjectRoot,
        "-ServerName", $ServerName,
        "-ExpertName", $expert
    )
    if ($CopySourcesToTerminal) {
        $argList += "-CopySourcesToTerminal"
    }

    $json = & powershell @argList
    $parsed = $json | ConvertFrom-Json
    $results += $parsed
}

$reportPath = Join-Path $ProjectRoot "EVIDENCE\\compile_all_microbots_report.json"
$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$results | Format-Table expert,compile_ok,compile_log -AutoSize
