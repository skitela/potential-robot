param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [string]$OutputRoot = "",
    [string]$LearningHealthPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\learning_health_registry_latest.json",
    [string]$LocalModelReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\local_model_readiness_latest.json",
    [string]$TruthStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_pretrade_execution_truth_status_latest.json",
    [string]$TradeTransitionAuditPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\trade_transition_audit_latest.json",
    [int]$TaskStaleMinutes = 30,
    [int]$WarningAgeMinutes = 120,
    [int]$StaleAgeMinutes = 360,
    [switch]$PublishToNotes,
    [string]$NoteTitlePrefix = "Status dzienny brygad",
    [string]$NoteAuthor = "codex",
    [string]$NoteSourceRole = "local_agent",
    [string[]]$NoteTags = @("brigady", "status_dzienny", "watch")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $ProjectRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$script:Now = Get-Date

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $normalized = [regex]::Replace($raw, ':\s*(-?Infinity|NaN)(\s*[,}\]])', ': null$2')
        return $normalized | ConvertFrom-Json -Depth 50
    }
    catch {
        return $null
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $Payload | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Get-ObjectEntries {
    param([object]$Object)

    $rows = @()
    if ($null -eq $Object) {
        return $rows
    }

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            $rows += [pscustomobject]@{
                Name = [string]$key
                Value = $Object[$key]
            }
        }
        return $rows
    }

    foreach ($property in $Object.PSObject.Properties) {
        $rows += [pscustomobject]@{
            Name = [string]$property.Name
            Value = $property.Value
        }
    }

    return $rows
}

function Get-DateSafe {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        return [datetime]::Parse($Text)
    }
    catch {
        return $null
    }
}

function Format-LocalDate {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    $timestamp = [datetime]$Value
    if ($timestamp.Kind -eq [System.DateTimeKind]::Utc) {
        return $timestamp.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
    }

    return $timestamp.ToString("yyyy-MM-dd HH:mm:ss")
}

function Get-SeverityRank {
    param([string]$Severity)

    switch ($Severity) {
        "CRITICAL" { return 3 }
        "WARN" { return 2 }
        "INFO" { return 1 }
        default { return 0 }
    }
}

function Get-MaxSeverity {
    param([string[]]$Values)

    $selected = "OK"
    $bestRank = -1
    foreach ($value in @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $rank = Get-SeverityRank -Severity $value
        if ($rank -gt $bestRank) {
            $bestRank = $rank
            $selected = $value
        }
    }

    return $selected
}

function Get-PayloadTimestamp {
    param(
        [object]$Payload,
        [Nullable[datetime]]$Fallback
    )

    foreach ($name in @("generated_at_local", "generated_at_utc", "written_at_local", "generated_at")) {
        $candidate = Get-DateSafe -Text ([string](Get-OptionalValue -Object $Payload -Name $name -Default ""))
        if ($null -ne $candidate) {
            return $candidate
        }
    }

    return $Fallback
}

function Get-TopCountReasons {
    param(
        [object]$Object,
        [int]$Limit = 3
    )

    return @(
        Get-ObjectEntries -Object $Object |
            Sort-Object { [int]$_.Value } -Descending |
            Select-Object -First $Limit |
            ForEach-Object { "{0}={1}" -f $_.Name, $_.Value }
    )
}

function Get-FreshnessSnapshot {
    param(
        [bool]$Exists,
        [object]$ObservedAt,
        [int]$WarningAgeMinutes,
        [int]$StaleAgeMinutes
    )

    if (-not $Exists -or $null -eq $ObservedAt) {
        return [pscustomobject]@{
            freshness_state = "MISSING"
            freshness_severity = "CRITICAL"
            age_minutes = $null
        }
    }

    $ageMinutes = [math]::Round((New-TimeSpan -Start ([datetime]$ObservedAt) -End $script:Now).TotalMinutes, 1)
    if ($ageMinutes -ge $StaleAgeMinutes) {
        return [pscustomobject]@{
            freshness_state = "STALE"
            freshness_severity = "WARN"
            age_minutes = $ageMinutes
        }
    }

    if ($ageMinutes -ge $WarningAgeMinutes) {
        return [pscustomobject]@{
            freshness_state = "AGING"
            freshness_severity = "INFO"
            age_minutes = $ageMinutes
        }
    }

    return [pscustomobject]@{
        freshness_state = "FRESH"
        freshness_severity = "OK"
        age_minutes = $ageMinutes
    }
}

function New-WatchSnapshot {
    param(
        [string]$Key,
        [string]$Label,
        [string]$Owner,
        [string]$Path,
        [int]$WarningAgeMinutes,
        [int]$StaleAgeMinutes
    )

    $exists = Test-Path -LiteralPath $Path
    $payload = Read-JsonSafe -Path $Path
    $lastWriteAt = if ($exists) { (Get-Item -LiteralPath $Path).LastWriteTime } else { $null }
    $observedAt = Get-PayloadTimestamp -Payload $payload -Fallback $lastWriteAt
    $freshness = Get-FreshnessSnapshot -Exists $exists -ObservedAt $observedAt -WarningAgeMinutes $WarningAgeMinutes -StaleAgeMinutes $StaleAgeMinutes

    $semanticState = "UNKNOWN"
    $semanticSeverity = "WARN"
    $headline = "Brak danych do interpretacji."
    $reasons = @()
    $metrics = [ordered]@{}

    switch ($Key) {
        "learning_health" {
            if ($null -eq $payload) {
                $semanticState = "MISSING"
                $semanticSeverity = "CRITICAL"
                $headline = "Brak raportu learning health."
                $reasons += "Nie mozna odczytac learning_health_registry_latest.json"
                break
            }

            $summary = Get-OptionalValue -Object $payload -Name "summary" -Default $null
            $totalSymbols = [int](Get-OptionalValue -Object $summary -Name "total_symbols" -Default 0)
            $fallbackGlobal = [int](Get-OptionalValue -Object $summary -Name "fallback_globalny" -Default 0)
            $healthyCount = [int](Get-OptionalValue -Object $summary -Name "uczy_sie_zdrowo" -Default 0)
            $paperLiveReady = [int](Get-OptionalValue -Object $summary -Name "gotowy_do_paper_live" -Default 0)
            $runtimeOutcomeSymbols = [int](Get-OptionalValue -Object $summary -Name "runtime_outcome_symbols" -Default 0)
            $topPressure = @(
                Get-OptionalValue -Object $payload -Name "top_pressure" -Default @() |
                    Select-Object -First 3 |
                    ForEach-Object { [string](Get-OptionalValue -Object $_ -Name "symbol_alias" -Default "") } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )

            $metrics.total_symbols = $totalSymbols
            $metrics.fallback_globalny = $fallbackGlobal
            $metrics.uczy_sie_zdrowo = $healthyCount
            $metrics.gotowy_do_paper_live = $paperLiveReady
            $metrics.runtime_outcome_symbols = $runtimeOutcomeSymbols

            if ($totalSymbols -gt 0 -and $fallbackGlobal -ge $totalSymbols) {
                $semanticState = "GLOBAL_FALLBACK"
                $semanticSeverity = "CRITICAL"
                $headline = "{0}/{1} symboli nadal jedzie na fallbacku globalnym." -f $fallbackGlobal, $totalSymbols
                $reasons += "Brak lokalnego postepu uczenia dla aktywnej floty."
            }
            elseif ($paperLiveReady -gt 0) {
                $semanticState = "PAPER_LIVE_READY"
                $semanticSeverity = "OK"
                $headline = "{0} symboli ma gotowosc do paper-live." -f $paperLiveReady
            }
            elseif ($healthyCount -gt 0) {
                $semanticState = "PARTIAL_HEALTH"
                $semanticSeverity = "WARN"
                $headline = "Uczenie zdrowe tylko dla {0}/{1} symboli." -f $healthyCount, $totalSymbols
            }
            else {
                $semanticState = "LIMITED_LEARNING"
                $semanticSeverity = "WARN"
                $headline = "Brak symboli gotowych do paper-live i brak zdrowego uczenia."
            }

            if ($runtimeOutcomeSymbols -le 0) {
                $reasons += "Brakuje outcome rows dla aktywnej floty runtime."
            }
            elseif ($runtimeOutcomeSymbols -lt $totalSymbols) {
                $reasons += "Outcome runtime sa tylko dla czesci floty: {0}/{1}." -f $runtimeOutcomeSymbols, $totalSymbols
            }
            if ($topPressure.Count -gt 0) {
                $reasons += "Najwieksza presja: {0}." -f ($topPressure -join ", ")
            }
        }
        "local_model_readiness" {
            if ($null -eq $payload) {
                $semanticState = "MISSING"
                $semanticSeverity = "CRITICAL"
                $headline = "Brak raportu local model readiness."
                $reasons += "Nie mozna odczytac local_model_readiness_latest.json"
                break
            }

            $summary = Get-OptionalValue -Object $payload -Name "summary" -Default $null
            $totalSymbols = [int](Get-OptionalValue -Object $summary -Name "total_symbols" -Default 0)
            $trainingReadyCount = [int](Get-OptionalValue -Object $summary -Name "training_ready_count" -Default 0)
            $runtimeReadyCount = [int](Get-OptionalValue -Object $summary -Name "runtime_ready_count" -Default 0)
            $deploymentPassCount = [int](Get-OptionalValue -Object $summary -Name "deployment_pass_count" -Default 0)
            $deploymentBlockedCount = [int](Get-OptionalValue -Object $summary -Name "deployment_blocked_count" -Default 0)
            $packageDisabledCount = [int](Get-OptionalValue -Object $summary -Name "runtime_package_present_but_disabled_count" -Default 0)
            $topReasons = Get-TopCountReasons -Object (Get-OptionalValue -Object $summary -Name "deployment_reason_counts" -Default $null)

            $metrics.total_symbols = $totalSymbols
            $metrics.training_ready_count = $trainingReadyCount
            $metrics.runtime_ready_count = $runtimeReadyCount
            $metrics.deployment_pass_count = $deploymentPassCount
            $metrics.deployment_blocked_count = $deploymentBlockedCount
            $metrics.runtime_package_present_but_disabled_count = $packageDisabledCount

            if ($deploymentPassCount -le 0) {
                $semanticState = "DEPLOYMENT_BLOCKED"
                $semanticSeverity = "CRITICAL"
                $headline = "Deployment pass = 0/{0}; lane wdrozeniowy nadal zablokowany." -f $totalSymbols
            }
            elseif ($runtimeReadyCount -le 0) {
                $semanticState = "RUNTIME_NOT_READY"
                $semanticSeverity = "WARN"
                $headline = "Sa kandydaci treningowi, ale runtime ready = 0/{0}." -f $totalSymbols
            }
            elseif ($trainingReadyCount -le 0) {
                $semanticState = "TRAINING_NOT_READY"
                $semanticSeverity = "WARN"
                $headline = "Brak symboli training_ready mimo obecnych kontraktow runtime."
            }
            else {
                $semanticState = "PARTIAL_READY"
                $semanticSeverity = "OK"
                $headline = "Sa symbole z training/runtime readiness, ale nadal nie cala flota."
            }

            if ($packageDisabledCount -gt 0) {
                $reasons += "Pakiet runtime jest obecny, ale wylaczony dla {0} symboli." -f $packageDisabledCount
            }
            if ($topReasons.Count -gt 0) {
                $reasons += "Top blokery deploy: {0}." -f ($topReasons -join "; ")
            }
        }
        "mt5_truth" {
            if ($null -eq $payload) {
                $semanticState = "MISSING"
                $semanticSeverity = "CRITICAL"
                $headline = "Brak raportu MT5 pretrade/execution truth."
                $reasons += "Nie mozna odczytac mt5_pretrade_execution_truth_status_latest.json"
                break
            }

            $truthSummary = Get-OptionalValue -Object $payload -Name "truth_summary" -Default $null
            $operationalState = [string](Get-OptionalValue -Object $payload -Name "operational_state" -Default "")
            $pretradeRows = [int](Get-OptionalValue -Object $truthSummary -Name "pretrade_rows" -Default 0)
            $executionRows = [int](Get-OptionalValue -Object $truthSummary -Name "execution_rows" -Default 0)
            $mergedRows = [int](Get-OptionalValue -Object $truthSummary -Name "merged_rows" -Default 0)
            $dormantReason = [string](Get-OptionalValue -Object $truthSummary -Name "dormant_reason" -Default "")
            $notes = @(
                Get-OptionalValue -Object $payload -Name "notes" -Default @() |
                    Select-Object -First 3 |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )

            $metrics.operational_state = $operationalState
            $metrics.pretrade_rows = $pretradeRows
            $metrics.execution_rows = $executionRows
            $metrics.merged_rows = $mergedRows

            if ($operationalState -eq "IMPLANTED_BUT_DORMANT" -or $mergedRows -le 0) {
                $semanticState = "DORMANT"
                $semanticSeverity = "CRITICAL"
                $headline = "Hooki truth sa wpiete, ale spool nadal nie daje rekordow."
            }
            elseif ($operationalState -match "ACTIVE|LIVE") {
                $semanticState = "ACTIVE"
                $semanticSeverity = "OK"
                $headline = "Truth pipeline jest aktywny i zbiera rekordy."
            }
            else {
                $semanticState = if ([string]::IsNullOrWhiteSpace($operationalState)) { "UNKNOWN" } else { $operationalState }
                $semanticSeverity = "WARN"
                $headline = "Stan truth pipeline jest niejednoznaczny: {0}." -f $semanticState
            }

            if (-not [string]::IsNullOrWhiteSpace($dormantReason)) {
                $reasons += "Dormant reason: {0}." -f $dormantReason
            }
            foreach ($note in $notes) {
                $reasons += $note
            }
        }
        "trade_transition" {
            if ($null -eq $payload) {
                $semanticState = "MISSING"
                $semanticSeverity = "CRITICAL"
                $headline = "Brak audytu trade transition."
                $reasons += "Nie mozna odczytac trade_transition_audit_latest.json"
                break
            }

            $globalPromotion = Get-OptionalValue -Object $payload -Name "global_promotion" -Default $null
            $globalApproved = [bool](Get-OptionalValue -Object $globalPromotion -Name "approved" -Default $false)
            $globalReasons = @(
                Get-OptionalValue -Object $globalPromotion -Name "reasons" -Default @() |
                    Select-Object -First 4 |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            $symbolPromotions = Get-OptionalValue -Object $payload -Name "symbol_promotions" -Default $null
            $approvedSymbols = @(
                Get-ObjectEntries -Object $symbolPromotions |
                    Where-Object { [bool](Get-OptionalValue -Object $_.Value -Name "approved" -Default $false) } |
                    Select-Object -ExpandProperty Name
            )

            $metrics.global_approved = $globalApproved
            $metrics.approved_symbols_count = @($approvedSymbols).Count

            if ($globalApproved) {
                $semanticState = "GLOBAL_PROMOTION_APPROVED"
                $semanticSeverity = "OK"
                $headline = "Trade transition ma global promotion approval."
            }
            elseif (@($approvedSymbols).Count -gt 0) {
                $semanticState = "PARTIAL_PROMOTION"
                $semanticSeverity = "WARN"
                $headline = "Global promotion zablokowany, ale sa pojedyncze aprobowane symbole."
            }
            else {
                $semanticState = "PROMOTION_BLOCKED"
                $semanticSeverity = "WARN"
                $headline = "Brak global promotion approval dla przejscia do handlu."
            }

            if (@($approvedSymbols).Count -gt 0) {
                $reasons += "Approved symbols: {0}." -f ($approvedSymbols -join ", ")
            }
            foreach ($reason in $globalReasons) {
                $reasons += $reason
            }
        }
    }

    $severity = Get-MaxSeverity -Values @($freshness.freshness_severity, $semanticSeverity)
    $relativePath = [System.IO.Path]::GetFileName($Path)

    return [pscustomobject]@{
        key = $Key
        label = $Label
        owner = $Owner
        path = $Path
        relative_path = $relativePath
        exists = $exists
        observed_at_local = Format-LocalDate -Value $observedAt
        freshness_state = [string]$freshness.freshness_state
        age_minutes = $freshness.age_minutes
        semantic_state = $semanticState
        severity = $severity
        headline = $headline
        reasons = @($reasons | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        metrics = [pscustomobject]$metrics
    }
}

function Get-LaneStatus {
    param(
        [string]$RuntimeState,
        [int]$Pending,
        [int]$Active,
        [int]$StaleActive,
        [int]$Blocked,
        [int]$ActiveClaims,
        [int]$StaleClaims
    )

    if ($RuntimeState -ne "RUNNING") {
        return "PAUSED"
    }
    if ($StaleActive -gt 0 -or $StaleClaims -gt 0) {
        return "STALE"
    }
    if ($Blocked -gt 0) {
        return "BLOCKED"
    }
    if ($Active -gt 0 -or $ActiveClaims -gt 0) {
        return "ACTIVE"
    }
    if ($Pending -gt 0) {
        return "READY_TO_START"
    }

    return "QUIET"
}

function Get-LaneRecommendation {
    param(
        [string]$LaneStatus,
        [int]$Pending,
        [int]$ActiveClaims,
        [int]$StaleClaims,
        [int]$StaleActive,
        [int]$Blocked
    )

    switch ($LaneStatus) {
        "PAUSED" { return "lane paused; wznowic tylko swiadomie" }
        "STALE" { return "odswiezyc heartbeat albo zamknac stary claim/task" }
        "BLOCKED" { return "rozpisac blokery i zrobic handoff" }
        "ACTIVE" {
            if ($Pending -gt 0 -and $ActiveClaims -gt 0) {
                return "claim aktywny; podnies pending task do ACTIVE" }
            return "utrzymac heartbeat i krotki handoff" }
        "READY_TO_START" {
            if ($ActiveClaims -le 0) {
                return "wez claim i podnies zadanie do ACTIVE"
            }
            return "claim juz jest; wystartuj lane"
        }
        default { return "monitorowac bez wymuszania pracy" }
    }
}

function ConvertTo-MarkdownCell {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return ($Text -replace '\|', '/' -replace "`r?`n", ' ')
}

function New-BrigadeDailyNoteText {
    param(
        [string]$GeneratedAtLocal,
        [string]$OverallVerdict,
        [object]$Summary,
        [object[]]$BrigadeRows,
        [object[]]$Watches,
        [string[]]$Actions,
        [string]$MarkdownReportPath
    )

    $noteLines = New-Object System.Collections.Generic.List[string]
    $noteLines.Add(("Raport dzienny brygad {0}" -f $GeneratedAtLocal))
    $noteLines.Add("")
    $noteLines.Add(("Werdykt: {0}" -f $OverallVerdict))
    $noteLines.Add(("Lane active/ready/block/stale: {0}/{1}/{2}/{3}" -f $Summary.lanes_active, $Summary.lanes_ready_to_start, $Summary.lanes_blocked, $Summary.lanes_stale))
    $noteLines.Add(("Taski pending/active/stale/blocked: {0}/{1}/{2}/{3}" -f $Summary.pending_tasks, $Summary.active_tasks, $Summary.stale_active_tasks, $Summary.blocked_tasks))
    $noteLines.Add(("Claimy active/stale: {0}/{1}" -f $Summary.active_claims, $Summary.stale_claims))
    $noteLines.Add(("Watch ok/warn/critical: {0}/{1}/{2}" -f $Summary.watch_ok, $Summary.watch_warn, $Summary.watch_critical))
    $noteLines.Add("")
    $noteLines.Add("Lane wymagajace startu:")

    foreach ($row in @($BrigadeRows | Where-Object { $_.lane_status -eq "READY_TO_START" } | Sort-Object startup_priority, brigade_id | Select-Object -First 6)) {
        $noteLines.Add(("- {0}: pending={1}, next={2}" -f $row.brigade_id, $row.pending, $row.recommendation))
    }

    $noteLines.Add("")
    $noteLines.Add("Top watchery:")
    foreach ($watch in @($Watches | Sort-Object { Get-SeverityRank -Severity $_.severity } -Descending | Select-Object -First 4)) {
        $noteLines.Add(("- {0}: {1}/{2} - {3}" -f $watch.label, $watch.severity, $watch.semantic_state, $watch.headline))
    }

    $noteLines.Add("")
    $noteLines.Add("Natychmiastowe ruchy:")
    foreach ($action in @($Actions | Select-Object -First 5)) {
        $noteLines.Add(("- {0}" -f $action))
    }

    $noteLines.Add("")
    $noteLines.Add(("Pelny raport: {0}" -f $MarkdownReportPath))
    return ($noteLines -join [Environment]::NewLine)
}

$taskboardScriptPath = Join-Path $ProjectRoot "RUN\GET_ORCHESTRATOR_TASKBOARD.ps1"
$workboardScriptPath = Join-Path $ProjectRoot "RUN\GET_ORCHESTRATOR_WORKBOARD.ps1"
$writeNoteScriptPath = Join-Path $ProjectRoot "RUN\WRITE_ORCHESTRATOR_NOTE.ps1"
$taskboardStatusPath = Join-Path (Join-Path $MailboxDir "status") "taskboard_latest.json"
$workboardStatusPath = Join-Path (Join-Path $MailboxDir "status") "workboard_latest.json"

if (-not (Test-Path -LiteralPath $taskboardScriptPath)) {
    throw "Brakuje skryptu taskboard: $taskboardScriptPath"
}
if (-not (Test-Path -LiteralPath $workboardScriptPath)) {
    throw "Brakuje skryptu workboard: $workboardScriptPath"
}
if ($PublishToNotes -and -not (Test-Path -LiteralPath $writeNoteScriptPath)) {
    throw "Brakuje skryptu zapisu notatek: $writeNoteScriptPath"
}

& $taskboardScriptPath -MailboxDir $MailboxDir -RegistryPath $RegistryPath -ByBrigade -StaleMinutes $TaskStaleMinutes | Out-Null
& $workboardScriptPath -MailboxDir $MailboxDir | Out-Null

$registry = Read-JsonSafe -Path $RegistryPath
if ($null -eq $registry) {
    throw "Nie mozna odczytac rejestru brygad: $RegistryPath"
}

$taskboard = Read-JsonSafe -Path $taskboardStatusPath
$workboard = Read-JsonSafe -Path $workboardStatusPath
if ($null -eq $taskboard) {
    throw "Nie mozna odczytac taskboard_latest.json z mailboxa."
}
if ($null -eq $workboard) {
    throw "Nie mozna odczytac workboard_latest.json z mailboxa."
}

$watches = @(
    New-WatchSnapshot -Key "learning_health" -Label "Learning health" -Owner "brygada_ml_migracja_mt5 + brygada_nadzor_uczenia_rolloutu" -Path $LearningHealthPath -WarningAgeMinutes $WarningAgeMinutes -StaleAgeMinutes $StaleAgeMinutes
    New-WatchSnapshot -Key "local_model_readiness" -Label "Local model readiness" -Owner "brygada_ml_migracja_mt5 + brygada_wdrozenia_mt5" -Path $LocalModelReadinessPath -WarningAgeMinutes $WarningAgeMinutes -StaleAgeMinutes $StaleAgeMinutes
    New-WatchSnapshot -Key "mt5_truth" -Label "MT5 pretrade/execution truth" -Owner "brygada_rozwoj_kodu + brygada_wdrozenia_mt5" -Path $TruthStatusPath -WarningAgeMinutes $WarningAgeMinutes -StaleAgeMinutes $StaleAgeMinutes
    New-WatchSnapshot -Key "trade_transition" -Label "Trade transition audit" -Owner "brygada_nadzor_uczenia_rolloutu" -Path $TradeTransitionAuditPath -WarningAgeMinutes $WarningAgeMinutes -StaleAgeMinutes $StaleAgeMinutes
)

$watchIndex = @{}
foreach ($watch in $watches) {
    $watchIndex[$watch.key] = $watch
}

$taskboardBrigades = @(Get-OptionalValue -Object $taskboard -Name "brigade_rows" -Default @())
$workboardClaims = @(Get-OptionalValue -Object $workboard -Name "active_rows" -Default @())
$brigadeRows = @()

foreach ($brigade in @($registry.brigades)) {
    $actorId = [string]$brigade.actor_id
    $brigadeTaskRow = @($taskboardBrigades | Where-Object { [string]$_.actor_id -eq $actorId -or [string]$_.brigade_id -eq [string]$brigade.brigade_id }) | Select-Object -First 1
    $claimRows = @($workboardClaims | Where-Object { [string]$_.actor -eq $actorId })
    $activeClaims = @($claimRows | Where-Object { [string]$_.state -eq "ACTIVE" }).Count
    $staleClaims = @($claimRows | Where-Object { [string]$_.state -eq "STALE" }).Count
    $pending = [int](Get-OptionalValue -Object $brigadeTaskRow -Name "pending" -Default 0)
    $active = [int](Get-OptionalValue -Object $brigadeTaskRow -Name "active" -Default 0)
    $staleActive = [int](Get-OptionalValue -Object $brigadeTaskRow -Name "stale_active" -Default 0)
    $blocked = [int](Get-OptionalValue -Object $brigadeTaskRow -Name "blocked" -Default 0)
    $runtimeState = [string](Get-OptionalValue -Object $brigadeTaskRow -Name "state" -Default ([string]$brigade.default_runtime_state))
    $autostart = [string](Get-OptionalValue -Object $brigadeTaskRow -Name "autostart" -Default ($(if ($brigade.autostart_enabled) { "ON" } else { "OFF" })))
    $laneStatus = Get-LaneStatus -RuntimeState $runtimeState -Pending $pending -Active $active -StaleActive $staleActive -Blocked $blocked -ActiveClaims $activeClaims -StaleClaims $staleClaims
    $recommendation = Get-LaneRecommendation -LaneStatus $laneStatus -Pending $pending -ActiveClaims $activeClaims -StaleClaims $staleClaims -StaleActive $staleActive -Blocked $blocked
    $claimTitles = @($claimRows | Select-Object -ExpandProperty work_title | Select-Object -First 2)

    $brigadeRows += [pscustomobject]@{
        brigade_id = [string]$brigade.brigade_id
        actor_id = $actorId
        chat_name = [string]$brigade.chat_name
        startup_priority = [string]$brigade.startup_priority
        runtime_state = $runtimeState
        autostart = $autostart
        lane_status = $laneStatus
        pending = $pending
        active = $active
        stale_active = $staleActive
        blocked = $blocked
        active_claims = $activeClaims
        stale_claims = $staleClaims
        claim_titles = @($claimTitles)
        recommendation = $recommendation
    }
}

$taskSummary = Get-OptionalValue -Object $taskboard -Name "summary" -Default $null
$workSummary = Get-OptionalValue -Object $workboard -Name "summary" -Default $null

$summary = [ordered]@{
    total_brigades = @($brigadeRows).Count
    lanes_active = @($brigadeRows | Where-Object { $_.lane_status -eq "ACTIVE" }).Count
    lanes_ready_to_start = @($brigadeRows | Where-Object { $_.lane_status -eq "READY_TO_START" }).Count
    lanes_blocked = @($brigadeRows | Where-Object { $_.lane_status -eq "BLOCKED" }).Count
    lanes_stale = @($brigadeRows | Where-Object { $_.lane_status -eq "STALE" }).Count
    lanes_paused = @($brigadeRows | Where-Object { $_.lane_status -eq "PAUSED" }).Count
    pending_tasks = [int](Get-OptionalValue -Object $taskSummary -Name "pending_tasks" -Default 0)
    active_tasks = [int](Get-OptionalValue -Object $taskSummary -Name "active_tasks" -Default 0)
    stale_active_tasks = [int](Get-OptionalValue -Object $taskSummary -Name "stale_active_tasks" -Default 0)
    blocked_tasks = [int](Get-OptionalValue -Object $taskSummary -Name "blocked_tasks" -Default 0)
    active_claims = [int](Get-OptionalValue -Object $workSummary -Name "active_claims" -Default 0)
    stale_claims = [int](Get-OptionalValue -Object $workSummary -Name "stale_claims" -Default 0)
    watch_ok = @($watches | Where-Object { $_.severity -eq "OK" }).Count
    watch_warn = @($watches | Where-Object { $_.severity -eq "WARN" }).Count
    watch_critical = @($watches | Where-Object { $_.severity -eq "CRITICAL" }).Count
}

$overallVerdict = "STABLE"
if ($summary.watch_critical -gt 0 -or $summary.lanes_stale -gt 0 -or $summary.stale_claims -gt 0 -or $summary.stale_active_tasks -gt 0) {
    $overallVerdict = "ATTENTION_REQUIRED"
}
elseif ($summary.watch_warn -gt 0 -or $summary.lanes_blocked -gt 0 -or $summary.blocked_tasks -gt 0) {
    $overallVerdict = "WATCH_CLOSELY"
}
elseif ($summary.lanes_active -gt 0 -or $summary.active_tasks -gt 0 -or $summary.active_claims -gt 0) {
    $overallVerdict = "IN_PROGRESS"
}

$actions = New-Object System.Collections.Generic.List[string]

$readyWithoutClaim = @($brigadeRows | Where-Object { $_.lane_status -eq "READY_TO_START" -and $_.active_claims -le 0 })
if ($readyWithoutClaim.Count -gt 0) {
    $actions.Add(("Lane z pending bez claimu: {0}." -f (($readyWithoutClaim | Select-Object -ExpandProperty brigade_id) -join ", ")))
}

$staleLanes = @($brigadeRows | Where-Object { $_.lane_status -eq "STALE" })
if ($staleLanes.Count -gt 0) {
    $actions.Add(("Lane ze starym heartbeat/claimem: {0}." -f (($staleLanes | Select-Object -ExpandProperty brigade_id) -join ", ")))
}

if ($watchIndex.ContainsKey("learning_health") -and $watchIndex.learning_health.semantic_state -eq "GLOBAL_FALLBACK") {
    $metrics = $watchIndex.learning_health.metrics
    $actions.Add(("ML + nadzor: fallback globalny nadal trzyma {0}/{1} symboli aktywnej floty." -f $metrics.fallback_globalny, $metrics.total_symbols))
}

if ($watchIndex.ContainsKey("local_model_readiness") -and $watchIndex.local_model_readiness.semantic_state -eq "DEPLOYMENT_BLOCKED") {
    $metrics = $watchIndex.local_model_readiness.metrics
    $actions.Add(("Wdrozenia MT5: deployment pass = {0}/{1}; nie robic rolloutu bez odblokowania readiness." -f $metrics.deployment_pass_count, $metrics.total_symbols))
}

if ($watchIndex.ContainsKey("mt5_truth") -and $watchIndex.mt5_truth.semantic_state -eq "DORMANT") {
    $actions.Add("Rozwoj kodu + wdrozenia: uruchomic zywy spool pretrade/execution, bo truth jest nadal dormant.")
}

if ($watchIndex.ContainsKey("trade_transition") -and $watchIndex.trade_transition.semantic_state -eq "PROMOTION_BLOCKED") {
    $actions.Add("Nadzor uczenia: global promotion dla przejscia do handlu nadal jest zablokowany.")
}

if ($actions.Count -eq 0) {
    $actions.Add("Brak natychmiastowych akcji krytycznych; utrzymac monitoring i heartbeat.")
}

$generatedAtLocal = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$generatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$jsonPath = Join-Path $OutputRoot "brigade_daily_status_latest.json"
$mdPath = Join-Path $OutputRoot "brigade_daily_status_latest.md"
$publishedNotePath = ""
$publishedNoteTitle = ""

$payload = [ordered]@{
    schema_version = "1.0"
    generated_at_local = $generatedAtLocal
    generated_at_utc = $generatedAtUtc
    overall_verdict = $overallVerdict
    summary = $summary
    brigades = @($brigadeRows)
    critical_watches = @($watches)
    immediate_actions = @($actions)
    sources = [ordered]@{
        mailbox_dir = $MailboxDir
        taskboard_status_path = $taskboardStatusPath
        workboard_status_path = $workboardStatusPath
    }
}

Write-JsonFile -Path $jsonPath -Payload $payload

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# RAPORT DZIENNY BRYGAD")
$lines.Add("")
$lines.Add(("Wygenerowano: {0}" -f $generatedAtLocal))
$lines.Add(("Werdykt: {0}" -f $overallVerdict))
$lines.Add("")
$lines.Add("## Podsumowanie")
$lines.Add("")
$lines.Add(("- brygady: {0}" -f $summary.total_brigades))
$lines.Add(("- lane active: {0}" -f $summary.lanes_active))
$lines.Add(("- lane ready_to_start: {0}" -f $summary.lanes_ready_to_start))
$lines.Add(("- lane blocked: {0}" -f $summary.lanes_blocked))
$lines.Add(("- lane stale: {0}" -f $summary.lanes_stale))
$lines.Add(("- lane paused: {0}" -f $summary.lanes_paused))
$lines.Add(("- taski pending/active/stale/blocked: {0}/{1}/{2}/{3}" -f $summary.pending_tasks, $summary.active_tasks, $summary.stale_active_tasks, $summary.blocked_tasks))
$lines.Add(("- claimy active/stale: {0}/{1}" -f $summary.active_claims, $summary.stale_claims))
$lines.Add(("- watch ok/warn/critical: {0}/{1}/{2}" -f $summary.watch_ok, $summary.watch_warn, $summary.watch_critical))
$lines.Add("")
$lines.Add("## Status lane")
$lines.Add("")
$lines.Add("| brygada | lane | runtime | P | A | S | B | claims | priorytet | next |")
$lines.Add("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |")

foreach ($row in $brigadeRows) {
    $runtimeCell = "{0}/{1}" -f $row.runtime_state, $row.autostart
    $claimsCell = if ($row.stale_claims -gt 0) { "{0}+{1} stale" -f $row.active_claims, $row.stale_claims } else { [string]$row.active_claims }
    $lines.Add(
        ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f
            (ConvertTo-MarkdownCell -Text $row.brigade_id),
            (ConvertTo-MarkdownCell -Text $row.lane_status),
            (ConvertTo-MarkdownCell -Text $runtimeCell),
            $row.pending,
            $row.active,
            $row.stale_active,
            $row.blocked,
            (ConvertTo-MarkdownCell -Text $claimsCell),
            (ConvertTo-MarkdownCell -Text $row.startup_priority),
            (ConvertTo-MarkdownCell -Text $row.recommendation)
        )
    )
}

$lines.Add("")
$lines.Add("## Krytyczne watchery")
$lines.Add("")
$lines.Add("| watcher | severity | freshness | semantic | age_min | owner | headline |")
$lines.Add("| --- | --- | --- | --- | ---: | --- | --- |")

foreach ($watch in ($watches | Sort-Object { Get-SeverityRank -Severity $_.severity } -Descending)) {
    $ageCell = if ($null -eq $watch.age_minutes) { "n/a" } else { [string]$watch.age_minutes }
    $lines.Add(
        ("| [{0}]({1}) | {2} | {3} | {4} | {5} | {6} | {7} |" -f
            (ConvertTo-MarkdownCell -Text $watch.label),
            $watch.relative_path,
            (ConvertTo-MarkdownCell -Text $watch.severity),
            (ConvertTo-MarkdownCell -Text $watch.freshness_state),
            (ConvertTo-MarkdownCell -Text $watch.semantic_state),
            $ageCell,
            (ConvertTo-MarkdownCell -Text $watch.owner),
            (ConvertTo-MarkdownCell -Text $watch.headline)
        )
    )
}

$lines.Add("")
$lines.Add("## Szczegoly watcherow")
$lines.Add("")

foreach ($watch in ($watches | Sort-Object { Get-SeverityRank -Severity $_.severity } -Descending)) {
    $lines.Add(("### {0}" -f $watch.label))
    $lines.Add("")
    $lines.Add(("- plik: [{0}]({0})" -f $watch.relative_path))
    $lines.Add(("- owner: {0}" -f $watch.owner))
    $lines.Add(("- observed_at_local: {0}" -f $watch.observed_at_local))
    $lines.Add(("- severity/freshness/semantic: {0}/{1}/{2}" -f $watch.severity, $watch.freshness_state, $watch.semantic_state))
    $lines.Add(("- headline: {0}" -f $watch.headline))
    foreach ($reason in @($watch.reasons)) {
        $lines.Add(("- powod: {0}" -f $reason))
    }
    $lines.Add("")
}

$lines.Add("## Natychmiastowe ruchy")
$lines.Add("")
foreach ($action in $actions) {
    $lines.Add(("- {0}" -f $action))
}

$lines.Add("")
$lines.Add("## Zrodla")
$lines.Add("")
$lines.Add(("- taskboard mailbox: {0}" -f $taskboardStatusPath))
$lines.Add(("- workboard mailbox: {0}" -f $workboardStatusPath))

Set-Content -LiteralPath $mdPath -Value $lines -Encoding UTF8

if ($PublishToNotes) {
    $publishedNoteTitle = "{0} {1}" -f $NoteTitlePrefix, ((Get-Date).ToString("yyyyMMdd_HHmmss"))
    $noteText = New-BrigadeDailyNoteText -GeneratedAtLocal $generatedAtLocal -OverallVerdict $overallVerdict -Summary $summary -BrigadeRows $brigadeRows -Watches $watches -Actions $actions -MarkdownReportPath $mdPath
    $publishedNotePath = (& $writeNoteScriptPath -Title $publishedNoteTitle -Text $noteText -MailboxDir $MailboxDir -Author $NoteAuthor -SourceRole $NoteSourceRole -Visibility "ALL_BRIGADES_READ" -ExecutionIntent "STATUS" -ExecutionPolicy "BROADCAST_READ_ONLY" -NonTargetPolicy "READ_ONLY" -RequiresSafetyReview $false -Tags $NoteTags | Select-Object -Last 1)
    if (-not [string]::IsNullOrWhiteSpace($publishedNotePath)) {
        $payload["published_note_title"] = $publishedNoteTitle
        $payload["published_note_path"] = [string]$publishedNotePath
        Write-JsonFile -Path $jsonPath -Payload $payload
    }
}

[pscustomobject]@{
    generated_at_local = $generatedAtLocal
    overall_verdict = $overallVerdict
    markdown_report = $mdPath
    json_report = $jsonPath
    published_note_title = $publishedNoteTitle
    published_note_path = $publishedNotePath
    watch_critical = $summary.watch_critical
    watch_warn = $summary.watch_warn
    active_claims = $summary.active_claims
    pending_tasks = $summary.pending_tasks
} | Format-List
