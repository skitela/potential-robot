param(
    [Parameter(Mandatory = $true)]
    [string]$BrigadeId,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [string]$SourceActor = "operator",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RequestId = "",
    [string]$ParentClaimId = "",
    [string]$ReportPath = "",
    [string[]]$ScopePaths = @(),
    [string]$Instructions = "",
    [string]$ReportToActor = "",
    [string]$ReportToBrigadeId = "",
    [ValidateSet("LOW", "NORMAL", "HIGH", "CRITICAL")]
    [string]$Priority = "NORMAL",
    [string]$RegistryPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
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

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $value = $Object.$Name
        if ($null -ne $value) {
            return $value
        }
    }

    return $Default
}

function Get-BulletLines {
    param(
        [object[]]$Values,
        [string]$Fallback = "- none"
    )

    $items = @($Values | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
    if (@($items).Count -eq 0) {
        return @($Fallback)
    }

    return @($items | ForEach-Object { "- {0}" -f [string]$_ })
}

function Get-PolicyLines {
    param(
        [object]$Registry
    )

    $lines = @()
    $policy = $null
    if ($null -ne $Registry -and $Registry.PSObject.Properties.Name -contains "message_handling_policy") {
        $policy = $Registry.message_handling_policy
    }

    if ($null -eq $policy) {
        return @("- all brigades read new notes, target brigade executes after review")
    }

    $lines += "- Visibility: {0}" -f [string]$policy.default_visibility
    $lines += "- Execution policy: {0}" -f [string]$policy.default_execution_policy
    $lines += "- Non-target policy: {0}" -f [string]$policy.default_non_target_policy
    $lines += "- Request owner default rule: {0}" -f [string]$policy.request_owner_default_rule
    $lines += "- Result return rule: {0}" -f [string]$policy.result_return_rule
    $lines += "- Requires safety review: {0}" -f [string]$policy.execution_requires_safety_review
    $lines += "- Dangerous requests must be escalated: {0}" -f [string]$policy.dangerous_or_conflicting_requests_must_be_escalated
    if (-not [string]::IsNullOrWhiteSpace([string]$policy.codex_rule)) {
        $lines += "- Codex rule: {0}" -f [string]$policy.codex_rule
    }

    return @($lines)
}

$registry = Read-JsonFile -Path $RegistryPath
$brigade = @($registry.brigades | Where-Object {
    [string]$_.brigade_id -eq $BrigadeId -or [string]$_.actor_id -eq $BrigadeId
}) | Select-Object -First 1

if ($null -eq $brigade) {
    throw "Unknown brigade id or actor id: $BrigadeId"
}

$assignScriptPath = Join-Path $PSScriptRoot "ASSIGN_ORCHESTRATOR_PARALLEL_TASK.ps1"
if (-not (Test-Path -LiteralPath $assignScriptPath)) {
    throw "Missing assign script: $assignScriptPath"
}

$effectiveScopePaths = @($ScopePaths)
if (@($effectiveScopePaths).Count -eq 0) {
    $effectiveScopePaths = @($brigade.default_claim_roots)
}

$userInstructions = if ([string]::IsNullOrWhiteSpace($Instructions)) { "none" } else { $Instructions }
$contractLines = if (@($brigade.shared_contracts).Count -gt 0) {
    @($brigade.shared_contracts | ForEach-Object { "- $_" })
}
else {
    @("- none")
}
$objectiveLines = Get-BulletLines -Values @($registry.primary_objectives)
$policyLines = Get-BulletLines -Values @($registry.universal_execution_policy)
$learningLines = @()
if ($null -ne $registry.learning_command) {
    if (@($registry.learning_command.always_on_brigades).Count -gt 0) {
        $learningLines += "- Always-on brigades: {0}" -f ((@($registry.learning_command.always_on_brigades) | ForEach-Object { [string]$_ }) -join ", ")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$registry.learning_command.training_brigade_id)) {
        $learningLines += "- Training brigade: {0}" -f [string]$registry.learning_command.training_brigade_id
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$registry.learning_command.supervision_brigade_id)) {
        $learningLines += "- Supervision brigade: {0}" -f [string]$registry.learning_command.supervision_brigade_id
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$registry.learning_command.reporting_rule)) {
        $learningLines += "- Reporting rule: {0}" -f [string]$registry.learning_command.reporting_rule
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$registry.learning_command.other_brigades_priority_rule)) {
        $learningLines += "- Priority rule: {0}" -f [string]$registry.learning_command.other_brigades_priority_rule
    }
}
if (@($learningLines).Count -eq 0) {
    $learningLines = @("- none")
}
$messageHandlingPolicy = if ($null -ne $registry -and $registry.PSObject.Properties.Name -contains "message_handling_policy") { $registry.message_handling_policy } else { $null }
$requestOwnerActor = $SourceActor
$requestOwnerBrigade = @($registry.brigades | Where-Object { [string]$_.actor_id -eq $SourceActor }) | Select-Object -First 1
$requestOwnerBrigadeId = if ([string]$brigade.actor_id -eq $SourceActor) {
    [string]$brigade.brigade_id
}
elseif ($null -ne $requestOwnerBrigade) {
    [string]$requestOwnerBrigade.brigade_id
}
else {
    ""
}
$defaultReportToActor = [string](Get-OptionalValue -Object $messageHandlingPolicy -Name "default_report_to_actor" -Default "")
$defaultReportToBrigadeId = [string](Get-OptionalValue -Object $messageHandlingPolicy -Name "default_report_to_brigade_id" -Default "")
$effectiveReportToActor = if ([string]::IsNullOrWhiteSpace($ReportToActor)) {
    if (-not [string]::IsNullOrWhiteSpace($defaultReportToActor)) { $defaultReportToActor } else { $requestOwnerActor }
} else { $ReportToActor }
$effectiveReportToBrigadeId = if ([string]::IsNullOrWhiteSpace($ReportToBrigadeId)) {
    if (-not [string]::IsNullOrWhiteSpace($defaultReportToBrigadeId)) { $defaultReportToBrigadeId } else { $requestOwnerBrigadeId }
} else { $ReportToBrigadeId }
$informationAdminRule = [string](Get-OptionalValue -Object $messageHandlingPolicy -Name "information_admin_rule" -Default "")
$allTasksFlag = if ($registry.all_tasks_must_be_assigned_to_brigades) { "yes" } else { "no" }
$specializationSummary = if ([string]::IsNullOrWhiteSpace([string]$brigade.specialization_summary)) { [string]$brigade.primary_focus } else { [string]$brigade.specialization_summary }
$crossDomainExecution = if ($brigade.can_execute_cross_domain_tasks) { "yes" } else { "no" }
$messagePolicyLines = Get-PolicyLines -Registry $registry
$observerActors = @($registry.brigades | ForEach-Object { [string]$_.actor_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

$effectiveInstructions = @(
    "Brigade id: $([string]$brigade.brigade_id)",
    "Actor id: $([string]$brigade.actor_id)",
    "Chat name: $([string]$brigade.chat_name)",
    "Primary focus: $([string]$brigade.primary_focus)",
    "Specialization summary: $specializationSummary",
    "Cross-domain execution allowed when explicitly instructed: $crossDomainExecution",
    "All tasks must be assigned to brigade lanes: $allTasksFlag",
    "",
    "Global objectives:",
    @($objectiveLines),
    "",
    "Universal execution policy:",
    @($policyLines),
    "",
    "Learning command chain:",
    @($learningLines),
    "",
    "Message handling contract:",
    @($messagePolicyLines),
    ("Processing target actor: {0}" -f [string]$brigade.actor_id),
    ("Processing target brigade id: {0}" -f [string]$brigade.brigade_id),
    ("Request owner actor: {0}" -f $requestOwnerActor),
    ("Request owner brigade id: {0}" -f $requestOwnerBrigadeId),
    ("Report to actor: {0}" -f $effectiveReportToActor),
    ("Report to brigade id: {0}" -f $effectiveReportToBrigadeId),
    $(if ([string]::IsNullOrWhiteSpace($informationAdminRule)) { "" } else { "Information admin rule:`n$informationAdminRule" }),
    "",
    "Mission:",
    [string]$brigade.mission,
    "",
    "Suggested shared contracts:",
    @($contractLines),
    "",
    "Operator instructions:",
    $userInstructions
) -join [Environment]::NewLine

& $assignScriptPath `
    -Title $Title `
    -AssignedTo ([string]$brigade.actor_id) `
    -TargetBrigadeId ([string]$brigade.brigade_id) `
    -RequestOwnerActor $requestOwnerActor `
    -RequestOwnerBrigadeId $requestOwnerBrigadeId `
    -ReportToActor $effectiveReportToActor `
    -ReportToBrigadeId $effectiveReportToBrigadeId `
    -SourceActor $SourceActor `
    -MailboxDir $MailboxDir `
    -RegistryPath $RegistryPath `
    -RequestId $RequestId `
    -ParentClaimId $ParentClaimId `
    -ReportPath $ReportPath `
    -ScopePaths $effectiveScopePaths `
    -ObserverActors $observerActors `
    -Instructions $effectiveInstructions `
    -ExecutionIntent "ACTION_REQUEST" `
    -ExecutionPolicy "TARGET_ONLY_AFTER_REVIEW" `
    -Visibility "ALL_BRIGADES_READ" `
    -NonTargetPolicy "READ_AND_ESCALATE_IF_NEEDED" `
    -RequiresSafetyReview $true `
    -Priority $Priority
