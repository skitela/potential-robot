param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$summaryScript = Join-Path $ProjectRoot "RUN\GET_LOCAL_OPERATOR_SUMMARY.ps1"
$statusScript = Join-Path $ProjectRoot "RUN\GET_FX_LAB_STATUS.ps1"

foreach ($path in @($summaryScript, $statusScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonPath = Join-Path $OutputRoot ("local_operator_snapshot_{0}.json" -f $timestamp)
$mdPath = Join-Path $OutputRoot ("local_operator_snapshot_{0}.md" -f $timestamp)
$latestJson = Join-Path $OutputRoot "local_operator_snapshot_latest.json"
$latestMd = Join-Path $OutputRoot "local_operator_snapshot_latest.md"

$localSummary = (& $summaryScript | Out-String).Trim()
$fxLabStatus = (& $statusScript | Out-String).Trim()

$qdmHistoryRoot = "C:\TRADING_TOOLS\QuantDataManager\user\data\History"
$historyFiles = @()
if (Test-Path -LiteralPath $qdmHistoryRoot) {
    $historyFiles = @(Get-ChildItem $qdmHistoryRoot -Recurse -File -Filter "*_TICK.dat" -ErrorAction SilentlyContinue)
}

$historyTop = @(
    $historyFiles |
        Sort-Object Length -Descending |
        Select-Object -First 12 @{Name = "symbol"; Expression = { $_.Directory.Name } },
            @{Name = "file_name"; Expression = { $_.Name } },
            @{Name = "size_mb"; Expression = { [math]::Round($_.Length / 1MB, 2) } },
            LastWriteTime
)

$pagefiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue |
    Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage)

$snapshot = [ordered]@{
    generated_at = (Get-Date).ToString("s")
    local_summary = $localSummary
    fx_lab_status = $fxLabStatus
    qdm_history = [ordered]@{
        root = $qdmHistoryRoot
        file_count = @($historyFiles).Count
        total_size_gb = [math]::Round((@($historyFiles | Measure-Object Length -Sum).Sum / 1GB), 3)
        largest_files = $historyTop
    }
    pagefile = $pagefiles
}

$json = $snapshot | ConvertTo-Json -Depth 8
$json | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$json | Set-Content -LiteralPath $latestJson -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Local Operator Snapshot")
$lines.Add("")
$lines.Add(("Generated: {0}" -f $snapshot.generated_at))
$lines.Add("")
$lines.Add("## Local Summary")
$lines.Add("")
$lines.Add('```text')
$lines.Add($localSummary)
$lines.Add('```')
$lines.Add("")
$lines.Add("## FX Lab Status")
$lines.Add("")
$lines.Add('```text')
$lines.Add($fxLabStatus)
$lines.Add('```')
$lines.Add("")
$lines.Add("## QDM History Footprint")
$lines.Add("")
$lines.Add(("- file_count: {0}" -f $snapshot.qdm_history.file_count))
$lines.Add(("- total_size_gb: {0}" -f $snapshot.qdm_history.total_size_gb))
$lines.Add("")
if (@($historyTop).Count -gt 0) {
    $lines.Add("Largest history files:")
    foreach ($item in $historyTop) {
        $lines.Add(("- {0}: {1} MB ({2})" -f $item.symbol, $item.size_mb, $item.LastWriteTime))
    }
    $lines.Add("")
}
$lines.Add("## Pagefile")
$lines.Add("")
foreach ($pf in $pagefiles) {
    $lines.Add(("- {0}: allocated_mb={1} current_mb={2} peak_mb={3}" -f $pf.Name, $pf.AllocatedBaseSize, $pf.CurrentUsage, $pf.PeakUsage))
}

$md = $lines -join "`r`n"
$md | Set-Content -LiteralPath $mdPath -Encoding UTF8
$md | Set-Content -LiteralPath $latestMd -Encoding UTF8

$snapshot
