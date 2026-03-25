param(
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$ToolboxTab = "Eksperci",
    [string]$VpsTab = "Eksperci",
    [switch]$OpenVpsPanel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$pythonScript = Join-Path $projectRoot "TOOLS\configure_mt5_operator_view.py"
$evidenceDir = Join-Path $projectRoot "EVIDENCE\OPS"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputJson = Join-Path $evidenceDir ("mt5_operator_view_{0}.json" -f $timestamp)
$latestJson = Join-Path $evidenceDir "mt5_operator_view_latest.json"
$latestMd = Join-Path $evidenceDir "mt5_operator_view_latest.md"

$process = Get-Process terminal64 -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $Mt5Exe } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1

if ($null -eq $process) {
    $report = [ordered]@{
        ok = $false
        reason = "terminal_not_running"
        mt5_exe = $Mt5Exe
        toolbox_tab = $ToolboxTab
        vps_tab = $VpsTab
        open_vps_panel = [bool]$OpenVpsPanel
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outputJson -Encoding UTF8
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $latestJson -Encoding UTF8
    @(
        "# Widok Operatora MT5",
        "",
        "- OK: False",
        "- Powod: terminal_not_running",
        ("- MT5: {0}" -f $Mt5Exe)
    ) | Set-Content -LiteralPath $latestMd -Encoding UTF8
    Write-Output ($report | ConvertTo-Json -Depth 6 -Compress)
    exit 1
}

$args = @(
    $pythonScript,
    "--process-id", [string]$process.Id,
    "--toolbox-tab", $ToolboxTab,
    "--vps-tab", $VpsTab,
    "--output-json", $outputJson,
    "--latest-json", $latestJson,
    "--latest-md", $latestMd
)
if ($OpenVpsPanel) {
    $args += "--open-vps-panel"
}

& python @args
