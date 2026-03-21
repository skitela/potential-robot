param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchPlanPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_intensive_research_plan_latest.json",
    [string]$Mt5StatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_tester_status_latest.json",
    [string]$OpsEvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$BatchReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\weakest_lab\primary\weakest_mt5_batch_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Read-JsonOrNull {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-FileAgeSecondsOrNull {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return [int][math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds)
}

function Get-Registry {
    param([string]$RegistryPath)

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        throw "Registry not found: $RegistryPath"
    }

    return (Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Normalize-RegistryAlias {
    param(
        [object]$Registry,
        [string]$Alias
    )

    if ([string]::IsNullOrWhiteSpace($Alias)) {
        return ""
    }

    $entry = Find-RegistryEntryByAlias -Registry $Registry -Alias $Alias.Trim()
    if ($null -ne $entry) {
        return [string](Get-RegistryCanonicalSymbol -RegistryItem $entry)
    }

    return $Alias.Trim()
}

New-Item -ItemType Directory -Force -Path $OpsEvidenceDir | Out-Null
$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$registry = Get-Registry -RegistryPath $registryPath

$researchPlan = Read-JsonOrNull -Path $ResearchPlanPath
$mt5Status = Read-JsonOrNull -Path $Mt5StatusPath
$batchReport = Read-JsonOrNull -Path $BatchReportPath

$queueSymbols = @()
if ($null -ne $researchPlan) {
    $queueSymbols = @(
        $researchPlan.tester_queue |
            ForEach-Object { Normalize-RegistryAlias -Registry $registry -Alias ([string]$_) } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

$confirmedCompleted = New-Object System.Collections.Generic.List[string]
if ($null -ne $batchReport) {
    foreach ($run in @($batchReport.runs)) {
        $symbolAlias = Normalize-RegistryAlias -Registry $registry -Alias ([string]$run.symbol_alias)
        if ([string]::IsNullOrWhiteSpace($symbolAlias)) {
            continue
        }

        $resultLabel = [string]$run.result_label
        if ($resultLabel -eq "successfully_finished") {
            if (-not $confirmedCompleted.Contains($symbolAlias)) {
                [void]$confirmedCompleted.Add($symbolAlias)
            }
        }
    }
}

$currentSymbol = ""
$testerState = ""
if ($null -ne $mt5Status) {
    $currentSymbol = Normalize-RegistryAlias -Registry $registry -Alias ([string]$mt5Status.current_symbol)
    $testerState = [string]$mt5Status.state
}

if (-not [string]::IsNullOrWhiteSpace($currentSymbol) -and $confirmedCompleted.Contains($currentSymbol)) {
    [void]$confirmedCompleted.Remove($currentSymbol)
}

$pending = @(
    $queueSymbols |
        Where-Object {
            $_ -ne $currentSymbol -and
            -not $confirmedCompleted.Contains($_)
        }
)

$state = "planned"
if ($testerState -eq "running") {
    $state = "running"
}
elseif ($testerState -eq "stale") {
    $state = "stale"
}
elseif ($queueSymbols.Count -gt 0 -and $pending.Count -eq 0 -and [string]::IsNullOrWhiteSpace($currentSymbol)) {
    $state = "completed"
}
elseif ($queueSymbols.Count -gt 0) {
    $state = "waiting_for_idle"
}

$currentNoteParts = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($testerState)) {
    [void]$currentNoteParts.Add(("tester_state=" + $testerState))
}
if ($null -ne $researchPlan) {
    [void]$currentNoteParts.Add(("queue_source=research_plan"))
}
if (Test-Path -LiteralPath $BatchReportPath) {
    [void]$currentNoteParts.Add(("batch_report_age_s=" + (Get-FileAgeSecondsOrNull -Path $BatchReportPath)))
}

$status = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    state = $state
    current_symbol = $currentSymbol
    completed = @($confirmedCompleted.ToArray())
    pending = @($pending)
    queue = @($queueSymbols)
    queue_source = "research_plan"
    mt5_status_path = $Mt5StatusPath
    batch_report_path = if (Test-Path -LiteralPath $BatchReportPath) { $BatchReportPath } else { "" }
    current_note = ($currentNoteParts -join "; ")
}

$statusJsonLatest = Join-Path $OpsEvidenceDir "mt5_retest_queue_latest.json"
$statusMdLatest = Join-Path $OpsEvidenceDir "mt5_retest_queue_latest.md"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$statusJsonStamped = Join-Path $OpsEvidenceDir ("mt5_retest_queue_{0}.json" -f $timestamp)
$statusMdStamped = Join-Path $OpsEvidenceDir ("mt5_retest_queue_{0}.md" -f $timestamp)

$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusJsonLatest -Encoding UTF8
$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusJsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# MT5 Retest Queue Latest")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $status.generated_at_local))
$lines.Add(("- state: {0}" -f $status.state))
$lines.Add(("- current_symbol: {0}" -f $status.current_symbol))
$lines.Add(("- queue_source: {0}" -f $status.queue_source))
if (-not [string]::IsNullOrWhiteSpace([string]$status.current_note)) {
    $lines.Add(("- current_note: {0}" -f $status.current_note))
}
$lines.Add("")
$lines.Add("## Completed")
$lines.Add("")
if (@($status.completed).Count -gt 0) {
    foreach ($item in @($status.completed)) {
        $lines.Add(("- {0}" -f $item))
    }
}
else {
    $lines.Add("- none")
}
$lines.Add("")
$lines.Add("## Pending")
$lines.Add("")
if (@($status.pending).Count -gt 0) {
    foreach ($item in @($status.pending)) {
        $lines.Add(("- {0}" -f $item))
    }
}
else {
    $lines.Add("- none")
}
$lines.Add("")
$lines.Add("## Full Queue")
$lines.Add("")
if (@($status.queue).Count -gt 0) {
    $lines.Add(("- {0}" -f ((@($status.queue)) -join ", ")))
}
else {
    $lines.Add("- none")
}

($lines -join "`r`n") | Set-Content -LiteralPath $statusMdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $statusMdStamped -Encoding UTF8

$status
