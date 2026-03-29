param(
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [Parameter(Mandatory = $true)]
    [string]$AssignedTo,
    [string]$TargetBrigadeId = "",
    [string]$RequestOwnerActor = "",
    [string]$RequestOwnerBrigadeId = "",
    [string]$ReportToActor = "",
    [string]$ReportToBrigadeId = "",
    [string]$SourceActor = "codex",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [string]$RequestId = "",
    [string]$ParentClaimId = "",
    [string]$ReportPath = "",
    [string[]]$ScopePaths = @(),
    [string[]]$ObserverActors = @(),
    [string]$Instructions = "",
    [ValidateSet("INFO", "QUESTION", "ACTION_REQUEST", "AUDIT_REQUEST", "HANDOFF", "STATUS")]
    [string]$ExecutionIntent = "ACTION_REQUEST",
    [ValidateSet("BROADCAST_READ_ONLY", "TARGET_ONLY_AFTER_REVIEW", "SHARED_REVIEW")]
    [string]$ExecutionPolicy = "TARGET_ONLY_AFTER_REVIEW",
    [ValidateSet("ALL_BRIGADES_READ", "TARGET_PLUS_OBSERVERS", "TARGET_ONLY")]
    [string]$Visibility = "ALL_BRIGADES_READ",
    [ValidateSet("READ_ONLY", "READ_AND_ESCALATE_IF_NEEDED", "READ_AND_SUPPORT_IF_ASKED")]
    [string]$NonTargetPolicy = "READ_AND_ESCALATE_IF_NEEDED",
    [bool]$RequiresSafetyReview = $true,
    [ValidateSet("LOW", "NORMAL", "HIGH", "CRITICAL")]
    [string]$Priority = "NORMAL"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tasksPendingDir = Join-Path $MailboxDir "coordination\tasks\pending"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $tasksPendingDir, $statusDir | Out-Null

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        return $null
    }
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

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeActor = ($AssignedTo -replace '[^A-Za-z0-9._-]', '_')
$safeTitle = ($Title -replace '[^A-Za-z0-9._-]', '_')
$taskId = "{0}_{1}_{2}" -f $timestamp, $safeActor, $safeTitle
$taskJsonPath = Join-Path $tasksPendingDir ("{0}.json" -f $taskId)
$taskMdPath = Join-Path $tasksPendingDir ("{0}.md" -f $taskId)
$writtenAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$registry = Read-JsonFile -Path $RegistryPath
$policy = Get-OptionalValue -Object $registry -Name "message_handling_policy" -Default $null
$effectiveRequestOwnerActor = if ([string]::IsNullOrWhiteSpace($RequestOwnerActor)) { $SourceActor } else { $RequestOwnerActor }
$effectiveRequestOwnerBrigadeId = $RequestOwnerBrigadeId
$policyDefaultReportToActor = [string](Get-OptionalValue -Object $policy -Name "default_report_to_actor" -Default "")
$policyDefaultReportToBrigadeId = [string](Get-OptionalValue -Object $policy -Name "default_report_to_brigade_id" -Default "")
$effectiveReportToActor = if ([string]::IsNullOrWhiteSpace($ReportToActor)) {
    if (-not [string]::IsNullOrWhiteSpace($policyDefaultReportToActor)) { $policyDefaultReportToActor } else { $effectiveRequestOwnerActor }
} else { $ReportToActor }
$effectiveReportToBrigadeId = if ([string]::IsNullOrWhiteSpace($ReportToBrigadeId)) {
    if (-not [string]::IsNullOrWhiteSpace($policyDefaultReportToBrigadeId)) { $policyDefaultReportToBrigadeId } else { $effectiveRequestOwnerBrigadeId }
} else { $ReportToBrigadeId }

$payload = [ordered]@{
    task_id = $taskId
    title = $Title
    assigned_to = $AssignedTo
    target_brigade_id = $TargetBrigadeId
    request_owner_actor = $effectiveRequestOwnerActor
    request_owner_brigade_id = $effectiveRequestOwnerBrigadeId
    report_to_actor = $effectiveReportToActor
    report_to_brigade_id = $effectiveReportToBrigadeId
    source_actor = $SourceActor
    created_at_local = $writtenAt
    updated_at_local = $writtenAt
    last_activity_at_local = $writtenAt
    last_activity_title = "TASK_ASSIGNED"
    last_activity_notes = "Task assigned"
    status = "PENDING"
    request_id = $RequestId
    parent_claim_id = $ParentClaimId
    report_path = $ReportPath
    scope_paths = @($ScopePaths)
    observer_actors = @($ObserverActors)
    instructions = $Instructions
    execution_intent = $ExecutionIntent
    execution_policy = $ExecutionPolicy
    visibility = $Visibility
    non_target_policy = $NonTargetPolicy
    requires_safety_review = $RequiresSafetyReview
    priority = $Priority
}

$bodyLines = @(
    "# Parallel Task"
    ""
    "Task id: $taskId"
    "Assigned to: $AssignedTo"
    "Target brigade id: $TargetBrigadeId"
    "Request owner actor: $effectiveRequestOwnerActor"
    "Request owner brigade id: $effectiveRequestOwnerBrigadeId"
    "Report to actor: $effectiveReportToActor"
    "Report to brigade id: $effectiveReportToBrigadeId"
    "Source actor: $SourceActor"
    "Created at: $writtenAt"
    "Priority: $Priority"
    "Execution intent: $ExecutionIntent"
    "Execution policy: $ExecutionPolicy"
    "Visibility: $Visibility"
    "Non-target policy: $NonTargetPolicy"
    "Requires safety review: $RequiresSafetyReview"
    "Request id: $RequestId"
    "Parent claim id: $ParentClaimId"
    "Report path: $ReportPath"
    ""
    "## Observer actors"
)

if (@($ObserverActors).Count -gt 0) {
    $bodyLines += @($ObserverActors | ForEach-Object { "- $_" })
}
else {
    $bodyLines += "- none"
}

$bodyLines += @(
    ""
    "## Scope paths"
)

if (@($ScopePaths).Count -gt 0) {
    $bodyLines += @($ScopePaths | ForEach-Object { "- $_" })
}
else {
    $bodyLines += "- none"
}

$instructionsText = if ([string]::IsNullOrWhiteSpace($Instructions)) { "none" } else { $Instructions }

$bodyLines += @(
    "",
    "## Instructions",
    $instructionsText
)

Set-Content -LiteralPath $taskMdPath -Value ($bodyLines -join [Environment]::NewLine) -Encoding UTF8
Write-JsonFile -Path $taskJsonPath -Payload $payload
Write-JsonFile -Path (Join-Path $statusDir "task_latest.json") -Payload ([ordered]@{
    action = "assign"
    task_id = $taskId
    assigned_to = $AssignedTo
    source_actor = $SourceActor
    status = "PENDING"
    task_path = $taskJsonPath
    written_at_local = $writtenAt
})

[pscustomobject]@{
    task_id = $taskId
    assigned_to = $AssignedTo
    title = $Title
    status = "PENDING"
    task_path = $taskJsonPath
} | Format-List
