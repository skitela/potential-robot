param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [int]$SinceHours = 72,
    [switch]$IncludeArchive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$logsRoot = Join-Path $CommonRoot "logs"
$evidenceRoot = Join-Path $projectPath "EVIDENCE"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonPath = Join-Path $evidenceRoot ("TUNING_ROLLBACK_CAUSE_RUNTIME_{0}.json" -f $stamp)
$mdPath = Join-Path $evidenceRoot ("TUNING_ROLLBACK_CAUSE_RUNTIME_{0}.md" -f $stamp)
$latestJson = Join-Path $evidenceRoot "TUNING_ROLLBACK_CAUSE_RUNTIME_latest.json"
$latestMd = Join-Path $evidenceRoot "TUNING_ROLLBACK_CAUSE_RUNTIME_latest.md"
$cutoffUnix = [DateTimeOffset]::UtcNow.AddHours(-1 * [Math]::Abs($SinceHours)).ToUnixTimeSeconds()

if (-not (Test-Path -LiteralPath $logsRoot)) {
    throw "Missing logs root: $logsRoot"
}

function Get-FieldValue {
    param(
        [hashtable]$Row,
        [string]$Name,
        [string]$Default = ""
    )

    if ($Row.ContainsKey($Name)) {
        return [string]$Row[$Name]
    }
    return $Default
}

function Convert-LineToRow {
    param(
        [string[]]$Headers,
        [string]$Line
    )

    $values = [regex]::Split($Line, "`t")
    if ($values.Count -lt $Headers.Count) {
        for ($missing = $values.Count; $missing -lt $Headers.Count; $missing++) {
            $values += ""
        }
    }

    $row = [ordered]@{}
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        $name = $Headers[$i]
        if ($name -eq "") {
            continue
        }
        $value = if ($i -lt $values.Count) { $values[$i] } else { "" }
        $row[$name] = $value
    }

    if ($values.Count -gt $Headers.Count) {
        $row["_extra_column_count"] = [string]($values.Count - $Headers.Count)
    }

    return $row
}

function Resolve-TrustFallback {
    param(
        [string]$TrustState,
        [string]$ReasonCode
    )

    switch ($TrustState) {
        "PAPER_CONVERSION_BLOCKED" {
            $code = if ($ReasonCode -ne "") { $ReasonCode } else { "PAPER_CONVERSION_BLOCKED" }
            return @{ domain = "RISK"; class = "CONTRACT"; code = $code; source = "trust_state" }
        }
        "FOREFIELD_DIRTY" {
            $code = if ($ReasonCode -ne "") { $ReasonCode } else { "FOREFIELD_DIRTY" }
            return @{ domain = "DATA"; class = "TRUST"; code = $code; source = "trust_state" }
        }
        "LOW_SAMPLE" { return @{ domain = "DATA"; class = "TRUST"; code = "LOW_SAMPLE"; source = "trust_state" } }
        "OBSERVATIONS_MISSING" { return @{ domain = "DATA"; class = "TRUST"; code = "OBSERVATIONS_MISSING"; source = "trust_state" } }
        "INFRASTRUCTURE_WEAK" {
            $code = if ($ReasonCode -ne "") { $ReasonCode } else { "INFRASTRUCTURE_WEAK" }
            return @{ domain = "INFRA"; class = "HEALTH"; code = $code; source = "trust_state" }
        }
        "CENTRAL_STATE_STALE" { return @{ domain = "CENTRAL"; class = "STALENESS"; code = "CENTRAL_STATE_STALE"; source = "trust_state" } }
        default { return $null }
    }
}

function Resolve-RollbackCause {
    param([hashtable]$Row)

    $failureDomain = Get-FieldValue $Row "failure_reason_domain"
    $failureClass = Get-FieldValue $Row "failure_reason_class"
    $failureCode = Get-FieldValue $Row "failure_reason_code"
    if ($failureDomain -ne "" -and $failureDomain -ne "MODE" -and $failureCode -ne "NONE") {
        return @{ domain = $failureDomain; class = $failureClass; code = $failureCode; source = "failure_reason" }
    }

    $reviewDomain = Get-FieldValue $Row "review_reason_domain"
    $reviewClass = Get-FieldValue $Row "review_reason_class"
    $reviewCode = Get-FieldValue $Row "review_reason_code"
    if ($reviewDomain -ne "" -and $reviewDomain -ne "MODE" -and $reviewCode -ne "EXPERIMENT_STARTED") {
        return @{ domain = $reviewDomain; class = $reviewClass; code = $reviewCode; source = "review_reason" }
    }

    $reportReasonDomain = Get-FieldValue $Row "report_reason_domain"
    $reportReasonClass = Get-FieldValue $Row "report_reason_class"
    $reportReasonCode = Get-FieldValue $Row "report_reason_code"
    if ($reportReasonDomain -ne "" -and $reportReasonDomain -ne "MODE" -and $reportReasonCode -ne "" -and $reportReasonCode -ne "TRUSTED") {
        return @{ domain = $reportReasonDomain; class = $reportReasonClass; code = $reportReasonCode; source = "report_reason" }
    }

    $executionState = Get-FieldValue $Row "execution_quality_state"
    $executionReasonCode = Get-FieldValue $Row "execution_quality_reason_code"
    if ($executionState -eq "BAD") {
        $code = if ($executionReasonCode -ne "") { $executionReasonCode } else { "EXECUTION_QUALITY_BAD" }
        return @{ domain = "EXECUTION"; class = "DEGRADATION"; code = $code; source = "execution_state" }
    }

    $costState = Get-FieldValue $Row "cost_pressure_state"
    $costReasonCode = Get-FieldValue $Row "cost_pressure_reason_code"
    if ($costState -eq "NON_REPRESENTATIVE") {
        $code = if ($costReasonCode -ne "") { $costReasonCode } else { "NON_REPRESENTATIVE_COST" }
        return @{ domain = "COST"; class = "PRESSURE"; code = $code; source = "cost_state" }
    }

    $trustState = Get-FieldValue $Row "trust_state"
    $trustReason = Get-FieldValue $Row "trust_reason"
    $trustFallback = Resolve-TrustFallback -TrustState $trustState -ReasonCode $trustReason
    if ($null -ne $trustFallback) {
        return $trustFallback
    }

    return @{ domain = "SIGNAL"; class = "NEGATIVE_OUTCOME"; code = "LEGACY_INFERRED_SIGNAL_FAILURE"; source = "legacy_signal_fallback" }
}

function Resolve-RollbackCauseConfidence {
    param(
        [string]$Source,
        [string]$SchemaMode
    )

    switch ($Source) {
        "failure_reason" { return "HIGH" }
        "review_reason" { return "MEDIUM" }
        "report_reason" { return "MEDIUM" }
        "execution_state" { return "LOW" }
        "cost_state" { return "LOW" }
        "trust_state" {
            if ($SchemaMode -eq "legacy_v1") {
                return "INFERRED_LEGACY"
            }
            return "LOW"
        }
        "legacy_signal_fallback" { return "INFERRED_LEGACY" }
        default {
            if ($SchemaMode -eq "legacy_v1") {
                return "INFERRED_LEGACY"
            }
            return "UNKNOWN"
        }
    }
}

function Convert-ExperimentFile {
    param(
        [string]$Path,
        [string]$SourceKind
    )

    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    if ($lines.Count -lt 2) {
        return @()
    }

    $headers = [regex]::Split($lines[0], "`t")
    $schemaMode = if ($headers -contains "failure_reason_domain") { "cause_v2" } else { "legacy_v1" }
    $rows = New-Object System.Collections.Generic.List[object]

    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $raw = Convert-LineToRow -Headers $headers -Line $line
        $ts = 0L
        [void][long]::TryParse((Get-FieldValue $raw "ts" "0"), [ref]$ts)
        if ($ts -lt $cutoffUnix) {
            continue
        }

        $phase = Get-FieldValue $raw "phase"
        $rollbackCause = if ($phase -eq "ROLLBACK") { Resolve-RollbackCause -Row $raw } else { $null }
        $rollbackCauseConfidence = if ($rollbackCause) { Resolve-RollbackCauseConfidence -Source $rollbackCause.source -SchemaMode $schemaMode } else { "" }
        $symbol = Get-FieldValue $raw "symbol"
        $deltaPnl = 0.0
        [void][double]::TryParse((Get-FieldValue $raw "delta_realized_pnl_lifetime" "0"), [ref]$deltaPnl)

        $rows.Add([pscustomobject]@{
            ts = $ts
            ts_local = ([DateTimeOffset]::FromUnixTimeSeconds($ts).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss zzz"))
            symbol = $symbol
            phase = $phase
            experiment_status = Get-FieldValue $raw "experiment_status"
            experiment_revision = Get-FieldValue $raw "experiment_revision"
            action_code = Get-FieldValue $raw "experiment_action_code"
            focus_setup_type = Get-FieldValue $raw "experiment_focus_setup_type"
            focus_market_regime = Get-FieldValue $raw "experiment_focus_market_regime"
            delta_samples = Get-FieldValue $raw "delta_samples"
            delta_wins = Get-FieldValue $raw "delta_wins"
            delta_losses = Get-FieldValue $raw "delta_losses"
            delta_paper_open_rows = Get-FieldValue $raw "delta_paper_open_rows"
            delta_realized_pnl_lifetime = $deltaPnl
            trust_state = Get-FieldValue $raw "trust_state"
            execution_quality_state = Get-FieldValue $raw "execution_quality_state"
            cost_pressure_state = Get-FieldValue $raw "cost_pressure_state"
            review_reason_domain = Get-FieldValue $raw "review_reason_domain"
            review_reason_class = Get-FieldValue $raw "review_reason_class"
            review_reason_code = Get-FieldValue $raw "review_reason_code"
            failure_reason_domain = Get-FieldValue $raw "failure_reason_domain"
            failure_reason_class = Get-FieldValue $raw "failure_reason_class"
            failure_reason_code = Get-FieldValue $raw "failure_reason_code"
            report_reason_code = Get-FieldValue $raw "report_reason_code"
            report_reason_domain = Get-FieldValue $raw "report_reason_domain"
            report_reason_class = Get-FieldValue $raw "report_reason_class"
            trust_reason = Get-FieldValue $raw "trust_reason"
            rollback_cause_domain = if ($rollbackCause) { $rollbackCause.domain } else { "" }
            rollback_cause_class = if ($rollbackCause) { $rollbackCause.class } else { "" }
            rollback_cause_code = if ($rollbackCause) { $rollbackCause.code } else { "" }
            rollback_cause_source = if ($rollbackCause) { $rollbackCause.source } else { "" }
            rollback_cause_confidence = $rollbackCauseConfidence
            schema_mode = $schemaMode
            source_kind = $SourceKind
            source_path = $Path
            detail = Get-FieldValue $raw "detail"
        })
    }

    return @($rows.ToArray())
}

$allRows = New-Object System.Collections.Generic.List[object]
$symbolDirs = Get-ChildItem -Path $logsRoot -Directory | Where-Object { $_.Name -ne "archive" }

foreach ($symbolDir in $symbolDirs) {
    $activePath = Join-Path $symbolDir.FullName "tuning_experiments.csv"
    if (Test-Path -LiteralPath $activePath) {
        foreach ($row in (Convert-ExperimentFile -Path $activePath -SourceKind "active")) {
            $allRows.Add($row)
        }
    }

    if ($IncludeArchive) {
        $archiveRoot = Join-Path $symbolDir.FullName "archive"
        if (Test-Path -LiteralPath $archiveRoot) {
            $archiveFiles = Get-ChildItem -Path $archiveRoot -Recurse -Filter "tuning_experiments.csv" -File -ErrorAction SilentlyContinue
            foreach ($file in $archiveFiles) {
                foreach ($row in (Convert-ExperimentFile -Path $file.FullName -SourceKind "archive")) {
                    $allRows.Add($row)
                }
            }
        }
    }
}

$rows = @($allRows.ToArray())
$rollbackRows = @($rows | Where-Object { $_.phase -eq "ROLLBACK" } | Sort-Object ts)
$latestBySymbol = @($rows | Group-Object symbol | ForEach-Object {
    $_.Group | Sort-Object ts -Descending | Select-Object -First 1
} | Sort-Object symbol)

$rollbackBySymbol = @($rollbackRows | Group-Object symbol | ForEach-Object {
    $group = @($_.Group | Sort-Object ts -Descending)
    $latest = $group[0]
    $domains = @($group | Group-Object rollback_cause_domain | ForEach-Object {
        [pscustomobject]@{
            domain = $_.Name
            count = $_.Count
        }
    } | Sort-Object domain)

    [pscustomobject]@{
        symbol = $_.Name
        rollback_count = $group.Count
        latest_ts_local = $latest.ts_local
        latest_schema_mode = $latest.schema_mode
        latest_source_kind = $latest.source_kind
        latest_action_code = $latest.action_code
        latest_focus_setup_type = $latest.focus_setup_type
        latest_focus_market_regime = $latest.focus_market_regime
        latest_delta_realized_pnl_lifetime = $latest.delta_realized_pnl_lifetime
        latest_trust_state = $latest.trust_state
        latest_execution_quality_state = $latest.execution_quality_state
        latest_cost_pressure_state = $latest.cost_pressure_state
        latest_cause_domain = $latest.rollback_cause_domain
        latest_cause_class = $latest.rollback_cause_class
        latest_cause_code = $latest.rollback_cause_code
        latest_cause_source = $latest.rollback_cause_source
        latest_cause_confidence = $latest.rollback_cause_confidence
        domains = $domains
    }
} | Sort-Object -Property @{Expression="rollback_count";Descending=$true}, @{Expression="symbol";Descending=$false})

$domainSummary = @($rollbackRows | Group-Object rollback_cause_domain | ForEach-Object {
    [pscustomobject]@{
        domain = $_.Name
        count = $_.Count
    }
} | Sort-Object -Property @{Expression="count";Descending=$true}, @{Expression="domain";Descending=$false})

$sourceSummary = @($rollbackRows | Group-Object rollback_cause_source | ForEach-Object {
    [pscustomobject]@{
        source = $_.Name
        count = $_.Count
    }
} | Sort-Object -Property @{Expression="count";Descending=$true}, @{Expression="source";Descending=$false})

$confidenceSummary = @($rollbackRows | Group-Object rollback_cause_confidence | ForEach-Object {
    [pscustomobject]@{
        confidence = $_.Name
        count = $_.Count
    }
} | Sort-Object -Property @{Expression="count";Descending=$true}, @{Expression="confidence";Descending=$false})

$schemaSummary = @($rollbackRows | Group-Object schema_mode | ForEach-Object {
    [pscustomobject]@{
        schema_mode = $_.Name
        count = $_.Count
    }
} | Sort-Object schema_mode)

$report = [pscustomobject]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    common_root = $CommonRoot
    since_hours = [Math]::Abs($SinceHours)
    include_archive = [bool]$IncludeArchive
    total_rows = $rows.Count
    total_rollbacks = $rollbackRows.Count
    rollback_domains = $domainSummary
    rollback_sources = $sourceSummary
    rollback_confidence = $confidenceSummary
    rollback_schema_modes = $schemaSummary
    latest_by_symbol = $latestBySymbol
    rollback_by_symbol = $rollbackBySymbol
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJson -Encoding UTF8

$lines = @()
$lines += "# TUNING ROLLBACK CAUSE RUNTIME REPORT"
$lines += ""
$lines += ("generated_at_utc: {0}" -f $report.generated_at_utc)
$lines += ("since_hours: {0}" -f $report.since_hours)
$lines += ("include_archive: {0}" -f $report.include_archive)
$lines += ("total_rows: {0}" -f $report.total_rows)
$lines += ("total_rollbacks: {0}" -f $report.total_rollbacks)
$lines += ""
$lines += "## Rollback domains"
if ($domainSummary.Count -eq 0) {
    $lines += "- none"
} else {
    foreach ($item in $domainSummary) {
        $lines += ("- {0}: {1}" -f $item.domain,$item.count)
    }
}
$lines += ""
$lines += "## Rollback source quality"
if ($sourceSummary.Count -eq 0) {
    $lines += "- none"
} else {
    foreach ($item in $sourceSummary) {
        $lines += ("- {0}: {1}" -f $item.source,$item.count)
    }
}
$lines += ""
$lines += "## Rollback cause confidence"
if ($confidenceSummary.Count -eq 0) {
    $lines += "- none"
} else {
    foreach ($item in $confidenceSummary) {
        $lines += ("- {0}: {1}" -f $item.confidence,$item.count)
    }
}
$lines += ""
$lines += "## Rollback schema coverage"
if ($schemaSummary.Count -eq 0) {
    $lines += "- none"
} else {
    foreach ($item in $schemaSummary) {
        $lines += ("- {0}: {1}" -f $item.schema_mode,$item.count)
    }
}
$lines += ""
$lines += "## Per instrument rollback summary"
if ($rollbackBySymbol.Count -eq 0) {
    $lines += "- none"
} else {
    foreach ($item in $rollbackBySymbol) {
        $lines += ("- {0}: rollbacks={1}; latest={2}; cause={3}/{4}/{5}; source={6}; confidence={7}; action={8}; focus={9}/{10}; pnl={11}" -f `
            $item.symbol,
            $item.rollback_count,
            $item.latest_ts_local,
            $item.latest_cause_domain,
            $item.latest_cause_class,
            $item.latest_cause_code,
            $item.latest_cause_source,
            $item.latest_cause_confidence,
            $item.latest_action_code,
            $item.latest_focus_setup_type,
            $item.latest_focus_market_regime,
            $item.latest_delta_realized_pnl_lifetime)
    }
}
$lines += ""
$lines += "## Latest phase by symbol"
if ($latestBySymbol.Count -eq 0) {
    $lines += "- none"
} else {
    foreach ($item in $latestBySymbol) {
        $lines += ("- {0}: phase={1}; status={2}; ts={3}; trust={4}; exec={5}; cost={6}; review={7}/{8}/{9}; failure={10}/{11}/{12}; schema={13}" -f `
            $item.symbol,
            $item.phase,
            $item.experiment_status,
            $item.ts_local,
            $item.trust_state,
            $item.execution_quality_state,
            $item.cost_pressure_state,
            $item.review_reason_domain,
            $item.review_reason_class,
            $item.review_reason_code,
            $item.failure_reason_domain,
            $item.failure_reason_class,
            $item.failure_reason_code,
            $item.schema_mode)
    }
}

$lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
$lines | Set-Content -LiteralPath $latestMd -Encoding UTF8

$report | ConvertTo-Json -Depth 8
