param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_focus_pack.csv",
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [string]$ExportRoot = "C:\TRADING_DATA\QDM_EXPORT\MT5",
    [string]$ReportRoot = "C:\TRADING_DATA\QDM_EXPORT\reports"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ProfilePath)) {
    throw "QDM profile not found: $ProfilePath"
}

New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

function Get-HistoryCandidates {
    param(
        [string]$HistoryRoot,
        [string]$Symbol,
        [string]$Datatype
    )

    $symbolDir = Join-Path $HistoryRoot $Symbol
    if (-not (Test-Path -LiteralPath $symbolDir)) {
        return @()
    }

    $baseName = "{0}_{1}.dat" -f $Symbol, $Datatype
    return @(
        Get-ChildItem -LiteralPath $symbolDir -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.PSIsContainer -and
                ($_.Name -eq $baseName -or $_.Name -eq ($baseName + ".copy"))
            } |
            Sort-Object LastWriteTime -Descending
    )
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonPath = Join-Path $ReportRoot ("qdm_history_coverage_{0}.json" -f $timestamp)
$mdPath = Join-Path $ReportRoot ("qdm_history_coverage_{0}.md" -f $timestamp)
$latestJson = Join-Path $ReportRoot "qdm_history_coverage_latest.json"
$latestMd = Join-Path $ReportRoot "qdm_history_coverage_latest.md"

$rows = Import-Csv -LiteralPath $ProfilePath | Where-Object { $_.enabled -eq "1" }
$historyRoot = Join-Path $QdmRoot "user\data\History"
$entries = foreach ($row in $rows) {
    $symbol = $row.symbol.Trim()
    $datatype = if ([string]::IsNullOrWhiteSpace($row.datatype)) { "TICK" } else { $row.datatype.Trim() }
    $exportName = $row.mt5_export_name.Trim()
    $historyCandidates = @(Get-HistoryCandidates -HistoryRoot $historyRoot -Symbol $symbol -Datatype $datatype)
    $historyFile = if ($historyCandidates.Count -gt 0) { $historyCandidates[0].FullName } else { Join-Path $historyRoot ("{0}\{0}_{1}.dat" -f $symbol, $datatype) }
    $exportFile = Join-Path $ExportRoot ("{0}.csv" -f $exportName)

    $historyExists = ($historyCandidates.Count -gt 0)
    $historySizeMb = 0.0
    if ($historyExists) {
        $historySizeMb = [math]::Round($historyCandidates[0].Length / 1MB, 2)
    }

    $exportExists = Test-Path -LiteralPath $exportFile
    $exportSizeMb = 0.0
    if ($exportExists) {
        $exportSizeMb = [math]::Round((Get-Item -LiteralPath $exportFile).Length / 1MB, 2)
    }

    $status =
        if ($exportExists -and $exportSizeMb -gt 0) { "exported" }
        elseif ($historyExists -and $historySizeMb -gt 0) { "history_ready_export_pending" }
        elseif ($historyExists) { "history_empty" }
        else { "history_missing" }

    [pscustomobject]@{
        symbol = $symbol
        export_name = $exportName
        status = $status
        history_file = $historyFile
        history_size_mb = $historySizeMb
        export_file = $exportFile
        export_size_mb = $exportSizeMb
        notes = $row.notes
    }
}

$coverage = [ordered]@{
    generated_at = (Get-Date).ToString("s")
    profile = $ProfilePath
    summary = [ordered]@{
        exported = @($entries | Where-Object { $_.status -eq "exported" }).Count
        history_ready_export_pending = @($entries | Where-Object { $_.status -eq "history_ready_export_pending" }).Count
        history_empty = @($entries | Where-Object { $_.status -eq "history_empty" }).Count
        history_missing = @($entries | Where-Object { $_.status -eq "history_missing" }).Count
    }
    items = $entries
}

$json = $coverage | ConvertTo-Json -Depth 6
$json | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$json | Set-Content -LiteralPath $latestJson -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# QDM History Coverage")
$lines.Add("")
$lines.Add(("Generated: {0}" -f $coverage.generated_at))
$lines.Add(("Profile: {0}" -f $ProfilePath))
$lines.Add("")
$lines.Add("## Summary")
$lines.Add("")
$lines.Add(("- exported: {0}" -f $coverage.summary.exported))
$lines.Add(("- history_ready_export_pending: {0}" -f $coverage.summary.history_ready_export_pending))
$lines.Add(("- history_empty: {0}" -f $coverage.summary.history_empty))
$lines.Add(("- history_missing: {0}" -f $coverage.summary.history_missing))
$lines.Add("")
$lines.Add("## Items")
$lines.Add("")
foreach ($item in $entries) {
    $lines.Add(("- {0}: {1} | history_mb={2} | export_mb={3} | {4}" -f
        $item.symbol, $item.status, $item.history_size_mb, $item.export_size_mb, $item.notes))
}

$md = $lines -join "`r`n"
$md | Set-Content -LiteralPath $mdPath -Encoding UTF8
$md | Set-Content -LiteralPath $latestMd -Encoding UTF8

$coverage
