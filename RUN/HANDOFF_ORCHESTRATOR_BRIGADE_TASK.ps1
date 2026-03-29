param(
    [Parameter(Mandatory = $true)]
    [string]$FromBrigadeId,
    [Parameter(Mandatory = $true)]
    [string]$ToBrigadeId,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [string]$Instructions = "",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RequestId = "",
    [string]$ParentClaimId = "",
    [string]$ReportPath = "",
    [string[]]$ScopePaths = @(),
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

function Resolve-Brigade {
    param(
        [object]$Registry,
        [string]$Lookup
    )

    return @($Registry.brigades | Where-Object {
        [string]$_.brigade_id -eq $Lookup -or [string]$_.actor_id -eq $Lookup
    }) | Select-Object -First 1
}

$registry = Read-JsonFile -Path $RegistryPath
$fromBrigade = Resolve-Brigade -Registry $registry -Lookup $FromBrigadeId
$toBrigade = Resolve-Brigade -Registry $registry -Lookup $ToBrigadeId
$policy = Get-OptionalValue -Object $registry -Name "message_handling_policy" -Default $null
$requestOwnerActor = [string]$fromBrigade.actor_id
$requestOwnerBrigadeId = [string]$fromBrigade.brigade_id
$reportToActor = [string](Get-OptionalValue -Object $policy -Name "default_report_to_actor" -Default "")
$reportToBrigadeId = [string](Get-OptionalValue -Object $policy -Name "default_report_to_brigade_id" -Default "")
if ([string]::IsNullOrWhiteSpace($reportToActor)) {
    $reportToActor = $requestOwnerActor
}
if ([string]::IsNullOrWhiteSpace($reportToBrigadeId)) {
    $reportToBrigadeId = $requestOwnerBrigadeId
}
$informationAdminRule = [string](Get-OptionalValue -Object $policy -Name "information_admin_rule" -Default "")

if ($null -eq $fromBrigade) {
    throw "Unknown source brigade id or actor id: $FromBrigadeId"
}
if ($null -eq $toBrigade) {
    throw "Unknown target brigade id or actor id: $ToBrigadeId"
}

$noteScriptPath = Join-Path $PSScriptRoot "WRITE_ORCHESTRATOR_NOTE.ps1"
$assignScriptPath = Join-Path $PSScriptRoot "ASSIGN_ORCHESTRATOR_BRIGADE_TASK.ps1"

if (-not (Test-Path -LiteralPath $noteScriptPath)) {
    throw "Missing note script: $noteScriptPath"
}
if (-not (Test-Path -LiteralPath $assignScriptPath)) {
    throw "Missing brigade assign script: $assignScriptPath"
}

$instructionsText = if ([string]::IsNullOrWhiteSpace($Instructions)) { "none" } else { $Instructions }
$scopeLines = if (@($ScopePaths).Count -gt 0) {
    @($ScopePaths | ForEach-Object { "- $_" })
}
else {
    @("- none")
}

$observerActors = @($registry.brigades | ForEach-Object { [string]$_.actor_id } | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne [string]$toBrigade.actor_id
} | Sort-Object -Unique)
$executionContractLines = @(
    "- All brigades read this note.",
    "- Only the target brigade executes after safety review and capital or session contract check.",
    ("- The note should be reported back to: {0} / {1}." -f $reportToActor, $reportToBrigadeId),
    "- Codex remains the default bridge coordinator unless the operator overrides the routing explicitly.",
    "- If another brigade is needed, the target brigade delegates through note plus task handoff.",
    "- After execution, block or delegation, publish a short result note to all brigades and Codex."
)

if (-not [string]::IsNullOrWhiteSpace($informationAdminRule)) {
    $executionContractLines += ("- Information admin rule: {0}" -f $informationAdminRule)
}

$noteText = @(
    "# Brigade handoff",
    "",
    "Title: $Title",
    "From brigade id: $([string]$fromBrigade.brigade_id)",
    "From actor id: $([string]$fromBrigade.actor_id)",
    "To brigade id: $([string]$toBrigade.brigade_id)",
    "To actor id: $([string]$toBrigade.actor_id)",
    "Request owner actor: $requestOwnerActor",
    "Request owner brigade id: $requestOwnerBrigadeId",
    "Report to actor: $reportToActor",
    "Report to brigade id: $reportToBrigadeId",
    "Request id: $RequestId",
    "Parent claim id: $ParentClaimId",
    "Report path: $ReportPath",
    "",
    "## Scope paths",
    @($scopeLines),
    "",
    "## Instructions",
    $instructionsText,
    "",
    "## Execution contract",
    @($executionContractLines)
) -join [Environment]::NewLine

$noteTitle = "Handoff {0} -> {1} :: {2}" -f [string]$fromBrigade.brigade_id, [string]$toBrigade.brigade_id, $Title
$notePath = & $noteScriptPath `
    -Title $noteTitle `
    -Text $noteText `
    -MailboxDir $MailboxDir `
    -Author ([string]$fromBrigade.actor_id) `
    -SourceRole "brigade_handoff" `
    -TargetActor ([string]$toBrigade.actor_id) `
    -TargetBrigadeId ([string]$toBrigade.brigade_id) `
    -RequestOwnerActor $requestOwnerActor `
    -RequestOwnerBrigadeId $requestOwnerBrigadeId `
    -ReportToActor $reportToActor `
    -ReportToBrigadeId $reportToBrigadeId `
    -ObserverActors $observerActors `
    -Visibility "ALL_BRIGADES_READ" `
    -ExecutionIntent "HANDOFF" `
    -ExecutionPolicy "TARGET_ONLY_AFTER_REVIEW" `
    -NonTargetPolicy "READ_AND_ESCALATE_IF_NEEDED" `
    -RequiresSafetyReview $true `
    -RelatedRequestId $RequestId `
    -Tags @("brigade-handoff", [string]$fromBrigade.brigade_id, [string]$toBrigade.brigade_id)

& $assignScriptPath `
    -BrigadeId ([string]$toBrigade.brigade_id) `
    -Title $Title `
    -SourceActor ([string]$fromBrigade.actor_id) `
    -MailboxDir $MailboxDir `
    -RequestId $RequestId `
    -ParentClaimId $ParentClaimId `
    -ReportPath $ReportPath `
    -ScopePaths $ScopePaths `
    -Instructions $Instructions `
    -ReportToActor $requestOwnerActor `
    -ReportToBrigadeId $requestOwnerBrigadeId `
    -Priority $Priority | Out-Null

$taskLatestPath = Join-Path $MailboxDir "status\task_latest.json"
$taskLatest = if (Test-Path -LiteralPath $taskLatestPath) { Read-JsonFile -Path $taskLatestPath } else { $null }

[pscustomobject]@{
    handoff_note_path = [string]$notePath
    from_actor_id = [string]$fromBrigade.actor_id
    to_actor_id = [string]$toBrigade.actor_id
    task_id = if ($taskLatest) { [string]$taskLatest.task_id } else { "" }
    task_status = if ($taskLatest) { [string]$taskLatest.status } else { "" }
    task_path = if ($taskLatest) { [string]$taskLatest.task_path } else { "" }
} | Format-List
