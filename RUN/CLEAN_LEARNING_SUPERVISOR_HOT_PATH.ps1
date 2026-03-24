param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [int]$HotCandidateSignalsThresholdMB = 24,
    [int]$ActiveGraceSeconds = 120,
    [int]$MaxFocusSymbols = 6,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-DirectoryIfMissing {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-SafeQueueSymbols {
    param(
        [string]$ResearchPlanPath,
        [int]$MaxCount
    )

    if (-not (Test-Path -LiteralPath $ResearchPlanPath)) {
        return @()
    }

    try {
        $plan = Get-Content -LiteralPath $ResearchPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($plan.tester_queue | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First $MaxCount)
    }
    catch {
        return @()
    }
}

function Get-SafeManifestState {
    param([string]$ManifestPath)

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return [pscustomobject]@{
            exists = $false
            age_seconds = $null
            threshold_seconds = 1800
            fresh = $false
        }
    }

    $item = Get-Item -LiteralPath $ManifestPath
    $ageSeconds = [int][Math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)
    return [pscustomobject]@{
        exists = $true
        age_seconds = $ageSeconds
        threshold_seconds = 1800
        fresh = ($ageSeconds -le 1800)
    }
}

New-DirectoryIfMissing -Path (Join-Path $ProjectRoot "EVIDENCE\OPS")

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$researchPlanPath = Join-Path $opsRoot "qdm_intensive_research_plan_latest.json"
$manifestPath = Join-Path $ResearchRoot "reports\research_export_manifest_latest.json"
$jsonPath = Join-Path $opsRoot "learning_hot_path_latest.json"
$mdPath = Join-Path $opsRoot "learning_hot_path_latest.md"
$logsRoot = Join-Path $CommonRoot "logs"
$thresholdBytes = [long]$HotCandidateSignalsThresholdMB * 1MB

$focusSymbols = New-Object System.Collections.Generic.List[string]
foreach ($symbol in (Get-SafeQueueSymbols -ResearchPlanPath $researchPlanPath -MaxCount $MaxFocusSymbols)) {
    if (-not [string]::IsNullOrWhiteSpace($symbol) -and -not $focusSymbols.Contains([string]$symbol)) {
        $focusSymbols.Add([string]$symbol) | Out-Null
    }
}
foreach ($symbol in @("GOLD", "SILVER", "US500")) {
    if (-not $focusSymbols.Contains($symbol)) {
        $focusSymbols.Add($symbol) | Out-Null
    }
}

$manifestState = Get-SafeManifestState -ManifestPath $manifestPath
$items = New-Object System.Collections.Generic.List[object]
$rotatedCount = 0
$waitingHotCount = 0

foreach ($symbol in $focusSymbols) {
    $path = Join-Path $logsRoot ("{0}\candidate_signals.csv" -f $symbol)
    if (-not (Test-Path -LiteralPath $path)) {
        $items.Add([pscustomobject]@{
            symbol = $symbol
            path = $path
            exists = $false
            size_mb = 0.0
            age_seconds = $null
            action = "MISSING"
            rotated = $false
            note = "candidate log not present"
        }) | Out-Null
        continue
    }

    $item = Get-Item -LiteralPath $path
    $sizeBytes = [long]$item.Length
    $ageSeconds = [int][Math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)
    $sizeMb = [math]::Round($sizeBytes / 1MB, 2)
    $action = "OK"
    $rotated = $false
    $note = "within threshold"

    if ($sizeBytes -ge $thresholdBytes) {
        if ($ageSeconds -lt $ActiveGraceSeconds) {
            $action = "HOT_ACTIVE_WAIT"
            $note = "file is oversized but still too hot for safe rotation"
            $waitingHotCount++
        }
        else {
            $action = "ROTATE"
            $note = "oversized candidate log safe for hot-path rotation"
            if ($Apply) {
                $archiveDir = Join-Path (Split-Path -Path $path -Parent) ("archive\learning_hot_path\{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
                New-DirectoryIfMissing -Path $archiveDir
                $archivePath = Join-Path $archiveDir "candidate_signals.csv"
                Move-Item -LiteralPath $path -Destination $archivePath -Force
                New-Item -ItemType File -Path $path -Force | Out-Null
                $rotated = $true
                $rotatedCount++
                $note = "rotated to archive and placeholder recreated"
            }
        }
    }

    $items.Add([pscustomobject]@{
        symbol = $symbol
        path = $path
        exists = $true
        size_mb = $sizeMb
        age_seconds = $ageSeconds
        action = $action
        rotated = $rotated
        note = $note
    }) | Out-Null
}

$itemArray = @($items.ToArray())
$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    common_root = $CommonRoot
    apply_mode = [bool]$Apply
    hot_candidate_signals_threshold_mb = $HotCandidateSignalsThresholdMB
    active_grace_seconds = $ActiveGraceSeconds
    manifest = $manifestState
    focus_symbols = @($focusSymbols.ToArray())
    items = $itemArray
    summary = [ordered]@{
        total_symbols = $itemArray.Count
        rotated_count = $rotatedCount
        waiting_hot_count = $waitingHotCount
        oversized_count = @($itemArray | Where-Object { $_.action -in @("HOT_ACTIVE_WAIT", "ROTATE") }).Count
    }
    verdict = if (@($itemArray | Where-Object { $_.action -eq "ROTATE" }).Count -gt 0) {
        "GORACY_SZLAK_WYMAGAL_CIECIA"
    }
    elseif ($waitingHotCount -gt 0) {
        "GORACY_SZLAK_AKTYWNY"
    }
    else {
        "GORACY_SZLAK_CZYSTY"
    }
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Goracy Szlak Uczenia")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- apply_mode: {0}" -f ([string]$report.apply_mode).ToLowerInvariant()))
$lines.Add(("- threshold_mb: {0}" -f $report.hot_candidate_signals_threshold_mb))
$lines.Add(("- active_grace_seconds: {0}" -f $report.active_grace_seconds))
$lines.Add("")
$lines.Add("## Manifest Research")
$lines.Add("")
$lines.Add(("- exists: {0}" -f $report.manifest.exists))
$lines.Add(("- fresh: {0}" -f $report.manifest.fresh))
$lines.Add(("- age_seconds: {0}" -f $report.manifest.age_seconds))
$lines.Add("")
$lines.Add("## Focus Symbols")
$lines.Add("")
foreach ($symbol in $report.focus_symbols) {
    $lines.Add(("- {0}" -f $symbol))
}
$lines.Add("")
$lines.Add("## Candidate Signals")
$lines.Add("")
foreach ($item in $itemArray) {
    $lines.Add(("- {0}: action={1}, size_mb={2}, age_seconds={3}, note={4}" -f
        $item.symbol,
        $item.action,
        $item.size_mb,
        $item.age_seconds,
        $item.note))
}
$lines.Add("")

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
