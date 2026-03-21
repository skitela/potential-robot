param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$QdmMissingProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_only_profile_latest.json",
    [string]$ResearchPlanPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_intensive_research_plan_latest.json",
    [string]$Mt5QueuePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_retest_queue_latest.json",
    [string]$RuntimeControlSummaryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\runtime_control_summary.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1")

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

foreach ($requiredPath in @($RegistryPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required file not found: $requiredPath"
    }
}

function Get-OptionalPropertyValue {
    param(
        $Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Read-JsonFileSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Read-KeyValueFile {
    param([string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $map[[string]$parts[0]] = [string]$parts[1]
    }

    return $map
}

function Get-MapString {
    param(
        [hashtable]$Map,
        [string]$Key,
        [string]$Default = ""
    )

    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) {
        return $Default
    }

    return [string]$Map[$Key]
}

function Get-MapDouble {
    param(
        [hashtable]$Map,
        [string]$Key,
        [double]$Default = 0.0
    )

    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) {
        return $Default
    }

    try {
        return [double]::Parse([string]$Map[$Key], [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $Default
    }
}

function Get-MapLong {
    param(
        [hashtable]$Map,
        [string]$Key,
        [long]$Default = 0
    )

    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) {
        return $Default
    }

    try {
        return [long]$Map[$Key]
    }
    catch {
        return $Default
    }
}

function Convert-UnixToLocalString {
    param([long]$EpochSeconds)

    if ($EpochSeconds -le 0) {
        return ""
    }

    try {
        return ([DateTimeOffset]::FromUnixTimeSeconds($EpochSeconds).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss"))
    }
    catch {
        return ""
    }
}

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Collection,
        [string]$Loop,
        [string]$Severity,
        [string]$Component,
        [string]$Message
    )

    $Collection.Add([pscustomobject]@{
        loop = $Loop
        severity = $Severity
        component = $Component
        message = $Message
    }) | Out-Null
}

function Test-SourceContains {
    param(
        [string]$SourceText,
        [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($SourceText)) {
        return $false
    }

    return $SourceText.IndexOf($Pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Resolve-ExistingDirFromRegistry {
    param(
        [object]$RegistryItem,
        [string]$Root,
        [string]$SubDirName
    )

    foreach ($candidate in @(Get-RegistrySymbolCandidates -RegistryItem $RegistryItem)) {
        $path = Join-Path $Root ("{0}\{1}" -f $SubDirName, $candidate)
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    return Join-Path $Root ("{0}\{1}" -f $SubDirName, (Get-RegistryCanonicalSymbol -RegistryItem $RegistryItem))
}

function Get-LogFileReport {
    param(
        [string]$DirectoryPath,
        [string]$FileName
    )

    $path = Join-Path $DirectoryPath $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            exists = $false
            size_mb = 0.0
            last_write_local = ""
            path = $path
        }
    }

    $item = Get-Item -LiteralPath $path
    return [pscustomobject]@{
        exists = $true
        size_mb = [math]::Round($item.Length / 1MB, 3)
        last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        path = $path
    }
}

function Get-QdmState {
    param(
        [object]$QdmProfile,
        [string]$SymbolAlias
    )

    foreach ($bucketName in @("present", "blocked", "unsupported", "missing")) {
        foreach ($item in @((Get-OptionalPropertyValue -Object $QdmProfile -Name $bucketName @()))) {
            if ([string](Get-OptionalPropertyValue -Object $item -Name "symbol_alias" "") -eq $SymbolAlias) {
                return [pscustomobject]@{
                    status = $bucketName
                    item = $item
                }
            }
        }
    }

    return [pscustomobject]@{
        status = "unknown"
        item = $null
    }
}

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$qdmProfile = Read-JsonFileSafe -Path $QdmMissingProfilePath
$researchPlan = Read-JsonFileSafe -Path $ResearchPlanPath
$mt5Queue = Read-JsonFileSafe -Path $Mt5QueuePath
$runtimeControlSummary = Read-JsonFileSafe -Path $RuntimeControlSummaryPath

$outputJsonPath = Join-Path $EvidenceDir "microbot_triple_loop_audit_latest.json"
$outputMdPath = Join-Path $EvidenceDir "microbot_triple_loop_audit_latest.md"

$expertRoot = Join-Path $ProjectRoot "MQL5\Experts\MicroBots"
$profileRoot = Join-Path $ProjectRoot "MQL5\Include\Profiles"
$stateRoot = Join-Path $CommonFilesRoot "state"
$logRoot = Join-Path $CommonFilesRoot "logs"

$symbolReports = New-Object System.Collections.Generic.List[object]
$allFindings = New-Object System.Collections.Generic.List[object]

foreach ($registryItem in @($registry.symbols)) {
    $canonicalSymbol = Get-RegistryCanonicalSymbol -RegistryItem $registryItem
    $brokerSymbol = Get-RegistryBrokerSymbol -RegistryItem $registryItem
    $codeSymbol = Get-RegistryCodeSymbol -RegistryItem $registryItem
    $expertName = "MicroBot_{0}.mq5" -f $codeSymbol
    $profileName = "Profile_{0}.mqh" -f $codeSymbol
    $expertPath = Join-Path $expertRoot $expertName
    $profilePath = Join-Path $profileRoot $profileName
    $stateAlias = Resolve-RegistryStateAlias -RegistryItem $registryItem -CommonFilesRoot $CommonFilesRoot -RequiredFiles @("runtime_state.csv", "execution_summary.json")
    $stateDir = Join-Path $stateRoot $stateAlias
    $logDir = Resolve-ExistingDirFromRegistry -RegistryItem $registryItem -Root $CommonFilesRoot -SubDirName "logs"
    $runtimeStatePath = Join-Path $stateDir "runtime_state.csv"
    $executionSummaryPath = Join-Path $stateDir "execution_summary.json"
    $runtimeControlPath = Join-Path $stateDir "runtime_control.csv"
    $tuningPolicyPath = Join-Path $stateDir "tuning_policy.csv"
    $tuningPolicyEffectivePath = Join-Path $stateDir "tuning_policy_effective.csv"

    $runtimeState = Read-KeyValueFile -Path $runtimeStatePath
    $runtimeControl = Read-KeyValueFile -Path $runtimeControlPath
    $tuningPolicy = Read-KeyValueFile -Path $tuningPolicyPath
    $tuningPolicyEffective = Read-KeyValueFile -Path $tuningPolicyEffectivePath
    $executionSummary = Read-JsonFileSafe -Path $executionSummaryPath
    $expertSource = if (Test-Path -LiteralPath $expertPath) { Get-Content -LiteralPath $expertPath -Raw -Encoding UTF8 } else { "" }

    $symbolFindings = New-Object System.Collections.Generic.List[object]

    $currentQueue = @((Get-OptionalPropertyValue -Object $mt5Queue -Name "queue" @()))
    $queueIndex = -1
    if ($currentQueue.Count -gt 0) {
        $queueIndex = [Array]::IndexOf([string[]]$currentQueue, $canonicalSymbol)
    }

    $slotPlanItem = @((Get-OptionalPropertyValue -Object $researchPlan -Name "slot_plan" @()) | Where-Object { [string]$_.symbol_alias -eq $canonicalSymbol } | Select-Object -First 1)
    $qdmState = Get-QdmState -QdmProfile $qdmProfile -SymbolAlias $canonicalSymbol
    $runtimeSummaryEntry = @((Get-OptionalPropertyValue -Object $runtimeControlSummary -Name "kontrola" @()) | Where-Object { [string]$_.para_walutowa -eq $canonicalSymbol } | Select-Object -First 1)

    $structure = [ordered]@{
        expert_exists = (Test-Path -LiteralPath $expertPath)
        profile_exists = (Test-Path -LiteralPath $profilePath)
        state_dir_exists = (Test-Path -LiteralPath $stateDir)
        runtime_state_exists = (Test-Path -LiteralPath $runtimeStatePath)
        execution_summary_exists = (Test-Path -LiteralPath $executionSummaryPath)
        runtime_control_exists = (Test-Path -LiteralPath $runtimeControlPath)
        tuning_policy_exists = (Test-Path -LiteralPath $tuningPolicyPath)
        tuning_policy_effective_exists = (Test-Path -LiteralPath $tuningPolicyEffectivePath)
        tester_telemetry_hook = (Test-SourceContains -SourceText $expertSource -Pattern "MbTesterTelemetry")
        hierarchy_bridge_hook = (Test-SourceContains -SourceText $expertSource -Pattern "MbTuningHierarchyBridge")
        session_guard_hook = (Test-SourceContains -SourceText $expertSource -Pattern "MbSessionGuard")
        ontester_init_hook = (Test-SourceContains -SourceText $expertSource -Pattern "OnTesterInit")
        ontester_hook = (Test-SourceContains -SourceText $expertSource -Pattern "OnTester(")
        ontester_pass_hook = (Test-SourceContains -SourceText $expertSource -Pattern "OnTesterPass")
        ontester_deinit_hook = (Test-SourceContains -SourceText $expertSource -Pattern "OnTesterDeinit")
    }

    if (-not $structure.expert_exists) {
        Add-Finding -Collection $symbolFindings -Loop "loop_1_structure" -Severity "critical" -Component "expert" -Message ("Brak pliku eksperta {0}" -f $expertName)
    }
    if (-not $structure.profile_exists) {
        Add-Finding -Collection $symbolFindings -Loop "loop_1_structure" -Severity "critical" -Component "profile" -Message ("Brak profilu {0}" -f $profileName)
    }
    foreach ($hookName in @("tester_telemetry_hook","hierarchy_bridge_hook","session_guard_hook","ontester_init_hook","ontester_hook","ontester_pass_hook","ontester_deinit_hook")) {
        if (-not [bool]$structure[$hookName]) {
            Add-Finding -Collection $symbolFindings -Loop "loop_1_structure" -Severity "warning" -Component "source_hooks" -Message ("Brakuje hooka `{0}` w {1}" -f $hookName, $expertName)
        }
    }
    if (-not $structure.runtime_state_exists -or -not $structure.execution_summary_exists) {
        Add-Finding -Collection $symbolFindings -Loop "loop_1_structure" -Severity "critical" -Component "state" -Message "Brak podstawowych artefaktow runtime dla mikrobota."
    }

    $lastHeartbeatEpoch = Get-MapLong -Map $runtimeState -Key "last_heartbeat_at"
    $learningSampleCount = Get-MapLong -Map $runtimeState -Key "learning_sample_count"
    $localPolicyConfidenceCap = Get-MapDouble -Map $tuningPolicy -Key "confidence_cap"
    $localPolicyRiskCap = Get-MapDouble -Map $tuningPolicy -Key "risk_cap"
    $effectiveConfidenceCap = Get-MapDouble -Map $tuningPolicyEffective -Key "confidence_cap"
    $effectiveRiskCap = Get-MapDouble -Map $tuningPolicyEffective -Key "risk_cap"
    $requestedMode = Get-MapString -Map $runtimeControl -Key "requested_mode"
    $effectiveRequestedMode = if ($runtimeSummaryEntry.Count -gt 0) { [string]$runtimeSummaryEntry[0].requested_mode } else { $requestedMode }
    $runtimeControlSource = if ($runtimeSummaryEntry.Count -gt 0) { [string]$runtimeSummaryEntry[0].source } else { "SYMBOL" }
    $summaryRuntimeMode = [string](Get-OptionalPropertyValue -Object $executionSummary -Name "runtime_mode" "")
    $trustState = [string](Get-OptionalPropertyValue -Object $executionSummary -Name "trust_state" "")
    $costState = [string](Get-OptionalPropertyValue -Object $executionSummary -Name "cost_pressure_state" "")
    $paperOverrideActive = [bool](Get-OptionalPropertyValue -Object $executionSummary -Name "paper_runtime_override_active" $false)
    $rawTradeAllowed = [bool](Get-OptionalPropertyValue -Object $executionSummary -Name "raw_trade_permissions_ok" $false)
    $lastHeartbeatLocal = Convert-UnixToLocalString -EpochSeconds $lastHeartbeatEpoch
    $runtime = [ordered]@{
        state_alias = $stateAlias
        last_heartbeat_local = $lastHeartbeatLocal
        learning_sample_count = $learningSampleCount
        realized_pnl_lifetime = Get-MapDouble -Map $runtimeState -Key "realized_pnl_lifetime"
        paper_mode_active = (Get-MapLong -Map $runtimeState -Key "paper_mode_active")
        kill_switch_cached_halt = (Get-MapLong -Map $runtimeState -Key "kill_switch_cached_halt")
        symbol_requested_mode = $requestedMode
        effective_requested_mode = $effectiveRequestedMode
        runtime_control_source = $runtimeControlSource
        execution_summary_runtime_mode = $summaryRuntimeMode
        trust_state = $trustState
        cost_state = $costState
        paper_runtime_override_active = $paperOverrideActive
        raw_trade_permissions_ok = $rawTradeAllowed
        local_policy_confidence_cap = $localPolicyConfidenceCap
        local_policy_risk_cap = $localPolicyRiskCap
        effective_policy_confidence_cap = $effectiveConfidenceCap
        effective_policy_risk_cap = $effectiveRiskCap
    }

    if ($learningSampleCount -gt 0 -and [string]::IsNullOrWhiteSpace($lastHeartbeatLocal)) {
        Add-Finding -Collection $symbolFindings -Loop "loop_2_runtime" -Severity "warning" -Component "heartbeat" -Message "Bot ma probe uczenia, ale brak poprawnego timestampu ostatniego heartbeat."
    }
    if (-not [string]::IsNullOrWhiteSpace($effectiveRequestedMode) -and -not [string]::IsNullOrWhiteSpace($summaryRuntimeMode) -and $effectiveRequestedMode -ne $summaryRuntimeMode) {
        Add-Finding -Collection $symbolFindings -Loop "loop_2_runtime" -Severity "info" -Component "runtime_mode" -Message ("effective_requested_mode={0}, execution_summary.runtime_mode={1}, source={2}" -f $effectiveRequestedMode, $summaryRuntimeMode, $runtimeControlSource)
    }
    if ($localPolicyConfidenceCap -gt 0 -and $effectiveConfidenceCap -le 0 -and $learningSampleCount -ge 50) {
        Add-Finding -Collection $symbolFindings -Loop "loop_2_runtime" -Severity "critical" -Component "tuning_policy_effective" -Message ("Local confidence_cap={0:N2}, a effective confidence_cap={1:N2}" -f $localPolicyConfidenceCap, $effectiveConfidenceCap)
    }
    if ($localPolicyRiskCap -gt 0 -and $effectiveRiskCap -le 0 -and $learningSampleCount -ge 50) {
        Add-Finding -Collection $symbolFindings -Loop "loop_2_runtime" -Severity "critical" -Component "tuning_policy_effective" -Message ("Local risk_cap={0:N2}, a effective risk_cap={1:N2}" -f $localPolicyRiskCap, $effectiveRiskCap)
    }
    if ($paperOverrideActive -and -not $rawTradeAllowed -and $effectiveRequestedMode -eq "READY") {
        Add-Finding -Collection $symbolFindings -Loop "loop_2_runtime" -Severity "warning" -Component "paper_override" -Message "Efektywny runtime deklaruje READY, ale paper override jest aktywny i raw trade permissions sa wylaczone."
    }
    if ($trustState -eq "LOW_SAMPLE" -and $learningSampleCount -lt 50) {
        Add-Finding -Collection $symbolFindings -Loop "loop_2_runtime" -Severity "info" -Component "sample" -Message "To wyglada zdrowo: bot jest jeszcze w fazie zbierania probki."
    }

    $candidateSignalsLog = Get-LogFileReport -DirectoryPath $logDir -FileName "candidate_signals.csv"
    $decisionEventsLog = Get-LogFileReport -DirectoryPath $logDir -FileName "decision_events.csv"
    $incidentJournalLog = Get-LogFileReport -DirectoryPath $logDir -FileName "incident_journal.jsonl"

    $integration = [ordered]@{
        qdm_status = $qdmState.status
        qdm_note = [string](Get-OptionalPropertyValue -Object $qdmState.item -Name "reason" "")
        research_slot = if ($slotPlanItem.Count -gt 0) { [string]$slotPlanItem[0].slot_pl } else { "" }
        research_group = if ($slotPlanItem.Count -gt 0) { [string]$slotPlanItem[0].research_group } else { "" }
        research_data_lane = if ($slotPlanItem.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $slotPlanItem[0] -Name "research_data_lane" "") } else { "" }
        mt5_queue_index = if ($queueIndex -ge 0) { ($queueIndex + 1) } else { 0 }
        mt5_completed = (@((Get-OptionalPropertyValue -Object $mt5Queue -Name "completed" @())) -contains $canonicalSymbol)
        mt5_pending = (@((Get-OptionalPropertyValue -Object $mt5Queue -Name "pending" @())) -contains $canonicalSymbol)
        candidate_signals_mb = $candidateSignalsLog.size_mb
        decision_events_mb = $decisionEventsLog.size_mb
        incident_journal_mb = $incidentJournalLog.size_mb
    }

    switch ($qdmState.status) {
        "blocked" {
            $severity = "warning"
            $messagePrefix = "QDM blocked"
            if ($slotPlanItem.Count -gt 0 -and [string](Get-OptionalPropertyValue -Object $slotPlanItem[0] -Name "research_data_lane" "") -eq "MT5_RUNTIME_TESTER_FALLBACK") {
                $severity = "info"
                $messagePrefix = "QDM blocked, fallback active"
            }
            Add-Finding -Collection $symbolFindings -Loop "loop_3_integration" -Severity $severity -Component "qdm" -Message ("{0}: {1}" -f $messagePrefix, [string](Get-OptionalPropertyValue -Object $qdmState.item -Name "reason" ""))
        }
        "unsupported" {
            $severity = "warning"
            $messagePrefix = "QDM unsupported"
            if ($slotPlanItem.Count -gt 0 -and [string](Get-OptionalPropertyValue -Object $slotPlanItem[0] -Name "research_data_lane" "") -eq "MT5_RUNTIME_TESTER_FALLBACK") {
                $severity = "info"
                $messagePrefix = "QDM unavailable, fallback active"
            }
            Add-Finding -Collection $symbolFindings -Loop "loop_3_integration" -Severity $severity -Component "qdm" -Message ("{0}: {1}" -f $messagePrefix, [string](Get-OptionalPropertyValue -Object $qdmState.item -Name "reason" ""))
        }
        "missing" {
            Add-Finding -Collection $symbolFindings -Loop "loop_3_integration" -Severity "critical" -Component "qdm" -Message "Brak wymaganych danych QDM."
        }
    }
    if ($slotPlanItem.Count -eq 0) {
        Add-Finding -Collection $symbolFindings -Loop "loop_3_integration" -Severity "warning" -Component "research_plan" -Message "Bot nie ma przypisanego slotu 20-minutowego w planie research."
    }
    if ($queueIndex -lt 0) {
        Add-Finding -Collection $symbolFindings -Loop "loop_3_integration" -Severity "warning" -Component "mt5_queue" -Message "Bot nie wystepuje w kolejce testera MT5."
    }
    foreach ($logReport in @(
        @{ label = "candidate_signals"; report = $candidateSignalsLog },
        @{ label = "decision_events"; report = $decisionEventsLog },
        @{ label = "incident_journal"; report = $incidentJournalLog }
    )) {
        if ($logReport.report.exists -and $logReport.report.size_mb -gt 8) {
            Add-Finding -Collection $symbolFindings -Loop "loop_3_integration" -Severity "warning" -Component "runtime_logs" -Message ("{0} ma {1:N1} MB i kwalifikuje sie do rotacji." -f $logReport.label, $logReport.report.size_mb)
        }
    }

    $severityCounts = @{
        critical = @($symbolFindings | Where-Object { $_.severity -eq "critical" }).Count
        warning  = @($symbolFindings | Where-Object { $_.severity -eq "warning" }).Count
        info     = @($symbolFindings | Where-Object { $_.severity -eq "info" }).Count
    }

    $sessionProfile = [string](Get-OptionalPropertyValue -Object $registryItem -Name "session_profile" "")
    $structureObject = [pscustomobject]$structure
    $runtimeObject = [pscustomobject]$runtime
    $integrationObject = [pscustomobject]$integration
    $severityCountsObject = [pscustomobject]$severityCounts
    $symbolReport = [pscustomobject]@{
        symbol_alias = $canonicalSymbol
        broker_symbol = $brokerSymbol
        code_symbol = $codeSymbol
        session_profile = $sessionProfile
        expert = $expertName
        state_alias = $stateAlias
        structure = $structureObject
        runtime = $runtimeObject
        integration = $integrationObject
        severity_counts = $severityCountsObject
    }

    $symbolReports.Add($symbolReport) | Out-Null
    foreach ($finding in $symbolFindings.ToArray()) {
        $allFindings.Add([pscustomobject]@{
            symbol_alias = $canonicalSymbol
            loop = $finding.loop
            severity = $finding.severity
            component = $finding.component
            message = $finding.message
        }) | Out-Null
    }
}

$summary = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    total_symbols = $symbolReports.Count
    critical_count = @($allFindings.ToArray() | Where-Object { $_.severity -eq "critical" }).Count
    warning_count = @($allFindings.ToArray() | Where-Object { $_.severity -eq "warning" }).Count
    info_count = @($allFindings.ToArray() | Where-Object { $_.severity -eq "info" }).Count
    symbols_with_critical = @($symbolReports.ToArray() | Where-Object { $_.severity_counts.critical -gt 0 } | Select-Object -ExpandProperty symbol_alias)
    symbols_with_warnings = @($symbolReports.ToArray() | Where-Object { $_.severity_counts.warning -gt 0 } | Select-Object -ExpandProperty symbol_alias)
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = $summary.generated_at_local
    project_root = $ProjectRoot
    common_files_root = $CommonFilesRoot
    summary = [pscustomobject]$summary
    symbol_reports = $symbolReports.ToArray()
    findings = $allFindings.ToArray()
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputJsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Microbot Triple Loop Audit")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $summary.generated_at_local))
$lines.Add(("- total_symbols: {0}" -f $summary.total_symbols))
$lines.Add(("- critical_count: {0}" -f $summary.critical_count))
$lines.Add(("- warning_count: {0}" -f $summary.warning_count))
$lines.Add(("- info_count: {0}" -f $summary.info_count))
$lines.Add("")
$lines.Add("## Top Blockers")
$lines.Add("")

$topSymbols = @($symbolReports.ToArray() | Sort-Object @{ Expression = { $_.severity_counts.critical }; Descending = $true }, @{ Expression = { $_.severity_counts.warning }; Descending = $true }, symbol_alias | Select-Object -First 8)
foreach ($item in $topSymbols) {
    $lines.Add(("- {0}: critical={1}, warning={2}, slot={3}, qdm={4}, queue_index={5}" -f
        $item.symbol_alias,
        $item.severity_counts.critical,
        $item.severity_counts.warning,
        $item.integration.research_slot,
        $item.integration.qdm_status,
        $item.integration.mt5_queue_index))
    foreach ($finding in @($allFindings | Where-Object { $_.symbol_alias -eq $item.symbol_alias } | Select-Object -First 4)) {
        $lines.Add(("  - [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message))
    }
}

$lines.Add("")
$lines.Add("## Per Symbol")
$lines.Add("")
foreach ($item in @($symbolReports.ToArray() | Sort-Object symbol_alias)) {
    $lines.Add(("### {0}" -f $item.symbol_alias))
    $lines.Add(("- broker_symbol: {0}" -f $item.broker_symbol))
    $lines.Add(("- session_profile: {0}" -f $item.session_profile))
    $lines.Add(("- state_alias: {0}" -f $item.state_alias))
    $lines.Add(("- effective_requested_mode: {0}" -f $item.runtime.effective_requested_mode))
    $lines.Add(("- summary_runtime_mode: {0}" -f $item.runtime.execution_summary_runtime_mode))
    $lines.Add(("- learning_sample_count: {0}" -f $item.runtime.learning_sample_count))
    $lines.Add(("- last_heartbeat_local: {0}" -f $item.runtime.last_heartbeat_local))
    $lines.Add(("- qdm_status: {0}" -f $item.integration.qdm_status))
    $lines.Add(("- research_data_lane: {0}" -f $item.integration.research_data_lane))
    $lines.Add(("- research_slot: {0}" -f $item.integration.research_slot))
    $lines.Add(("- mt5_queue_index: {0}" -f $item.integration.mt5_queue_index))
    foreach ($finding in @($allFindings | Where-Object { $_.symbol_alias -eq $item.symbol_alias } | Select-Object -First 5)) {
        $lines.Add(("  - [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message))
    }
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $outputMdPath -Encoding UTF8

[pscustomobject]$report
