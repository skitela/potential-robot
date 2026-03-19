param(
    [Parameter(Mandatory = $true)]
    [string]$SymbolAlias,
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TesterEvidenceRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\GOLDEN_BASELINES",
    [string]$Reason = "manual_freeze"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToDoubleOrNull {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $raw = [string]$Value
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq "null") { return $null }
    try { return [double]($raw -replace ',', '.') } catch { return $null }
}

function Normalize-Alias {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value.ToUpperInvariant()) -replace '[^A-Z0-9]+', '')
}

$aliasUpper = $SymbolAlias.ToUpperInvariant()
$aliasNorm = Normalize-Alias $SymbolAlias
$aliasToken = $aliasNorm
$expertPath = Join-Path $ProjectRoot ("MQL5\Experts\MicroBots\MicroBot_{0}.mq5" -f $aliasToken)
if (-not (Test-Path -LiteralPath $expertPath)) {
    throw ("Expert source not found for {0}: {1}" -f $aliasUpper, $expertPath)
}

$summaryFiles = @(Get-ChildItem -LiteralPath $TesterEvidenceRoot -Recurse -File -Filter "*summary.json" -ErrorAction SilentlyContinue)
$candidates = foreach ($file in $summaryFiles) {
    try {
        $summary = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        continue
    }

    if ((Normalize-Alias ([string]$summary.symbol_alias)) -ne $aliasNorm) {
        continue
    }

    $pnl = Convert-ToDoubleOrNull $summary.realized_pnl_lifetime
    if ($null -eq $pnl) {
        continue
    }

    [pscustomobject]@{
        pnl = $pnl
        path = $file.FullName
        summary = $summary
    }
}

if (@($candidates).Count -eq 0) {
    throw "No tester summary with PnL found for $aliasUpper."
}

$best = @($candidates | Sort-Object pnl -Descending | Select-Object -First 1)[0]

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$symbolRoot = Join-Path $OutputRoot $aliasUpper
New-Item -ItemType Directory -Force -Path $symbolRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$snapshotDir = Join-Path $symbolRoot $timestamp
New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null

$expertDest = Join-Path $snapshotDir (Split-Path -Leaf $expertPath)
$summaryDest = Join-Path $snapshotDir (Split-Path -Leaf $best.path)
Copy-Item -LiteralPath $expertPath -Destination $expertDest -Force
Copy-Item -LiteralPath $best.path -Destination $summaryDest -Force

$meta = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    symbol_alias = $aliasUpper
    reason = $Reason
    best_tester_pnl = $best.pnl
    best_tester_path = $best.path
    trust_state = [string]$best.summary.trust_state
    result_label = [string]$best.summary.result_label
    source_expert_path = $expertPath
    frozen_expert_path = $expertDest
    frozen_summary_path = $summaryDest
}

$metaPath = Join-Path $snapshotDir "golden_baseline_meta.json"
$meta | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metaPath -Encoding UTF8

$latestIndexPath = Join-Path $OutputRoot "golden_baselines_latest.json"
$index = @()
if (Test-Path -LiteralPath $latestIndexPath) {
    try {
        $index = @(Get-Content -LiteralPath $latestIndexPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        $index = @()
    }
}

$index = @($index | Where-Object { [string]$_.symbol_alias -ne $aliasUpper })
$index += [pscustomobject]$meta
$index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestIndexPath -Encoding UTF8

$latestMdPath = Join-Path $OutputRoot "golden_baselines_latest.md"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Golden Baselines Latest")
$lines.Add("")
foreach ($item in @($index | Sort-Object symbol_alias)) {
    $lines.Add(("- {0}: pnl={1}, trust={2}, frozen_expert={3}" -f $item.symbol_alias, $item.best_tester_pnl, $item.trust_state, $item.frozen_expert_path))
}
($lines -join "`r`n") | Set-Content -LiteralPath $latestMdPath -Encoding UTF8

[pscustomobject]$meta
