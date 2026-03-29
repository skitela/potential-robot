param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [string]$Actor = "",
    [ValidateSet("COMPLETED", "BLOCKED", "DELEGATED", "CANCELLED", "STATUS")]
    [string]$Outcome = "COMPLETED",
    [string]$Summary = "",
    [string[]]$Checked = @(),
    [string[]]$Confirmed = @(),
    [string[]]$Blockers = @(),
    [string[]]$ChangedFiles = @(),
    [string[]]$OutputArtifacts = @(),
    [string]$SaveStatus = "",
    [string[]]$DelegateWork = @(),
    [string]$CodexAction = "",
    [string]$NextAction = "",
    [string]$ReportPath = "",
    [string[]]$ScopePaths = @(),
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [string[]]$Tags = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

$tasksPendingDir = Join-Path $MailboxDir "coordination\tasks\pending"
$tasksActiveDir = Join-Path $MailboxDir "coordination\tasks\active"
$tasksBlockedDir = Join-Path $MailboxDir "coordination\tasks\blocked"
$tasksDoneDir = Join-Path $MailboxDir "coordination\tasks\done"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $statusDir | Out-Null

function Read-JsonFile {
    param([string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
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

    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function Find-TaskJson {
    param([string]$Id)

    foreach ($root in @($tasksPendingDir, $tasksActiveDir, $tasksBlockedDir, $tasksDoneDir)) {
        $candidate = Join-Path $root ("{0}.json" -f $Id)
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Resolve-BrigadeByActor {
    param(
        [object]$Registry,
        [string]$ActorId
    )

    return @($Registry.brigades | Where-Object { [string]$_.actor_id -eq $ActorId }) | Select-Object -First 1
}

$taskJsonPath = Find-TaskJson -Id $TaskId
if ($null -eq $taskJsonPath) {
    throw "Task not found in pending, active, blocked or done: $TaskId"
}

$taskPayload = Read-JsonFile -Path $taskJsonPath
if ($null -eq $taskPayload) {
    throw "Unable to parse task: $taskJsonPath"
}

$effectiveActor = if ([string]::IsNullOrWhiteSpace($Actor)) { [string]$taskPayload.assigned_to } else { $Actor }
if ([string]::IsNullOrWhiteSpace($effectiveActor)) {
    throw "Task has no assigned actor and no explicit -Actor was provided."
}

if (-not [string]::IsNullOrWhiteSpace([string]$taskPayload.assigned_to) -and $effectiveActor -ne [string]$taskPayload.assigned_to) {
    throw "Task is assigned to '$([string]$taskPayload.assigned_to)', not '$effectiveActor'."
}

$registry = Read-JsonFile -Path $RegistryPath
if ($null -eq $registry) {
    throw "Unable to read brigade registry: $RegistryPath"
}

$brigade = Resolve-BrigadeByActor -Registry $registry -ActorId $effectiveActor
$policy = Get-OptionalValue -Object $registry -Name "message_handling_policy" -Default $null
$requestOwnerActor = [string](Get-OptionalValue -Object $taskPayload -Name "request_owner_actor" -Default ([string](Get-OptionalValue -Object $taskPayload -Name "source_actor" -Default "")))
$requestOwnerBrigadeId = [string](Get-OptionalValue -Object $taskPayload -Name "request_owner_brigade_id" -Default "")
$reportToActor = [string](Get-OptionalValue -Object $taskPayload -Name "report_to_actor" -Default ([string](Get-OptionalValue -Object $policy -Name "default_report_to_actor" -Default "")))
$reportToBrigadeId = [string](Get-OptionalValue -Object $taskPayload -Name "report_to_brigade_id" -Default ([string](Get-OptionalValue -Object $policy -Name "default_report_to_brigade_id" -Default "")))
$informationAdminActor = [string](Get-OptionalValue -Object $policy -Name "information_admin_actor_id" -Default "")
$informationAdminBrigadeId = [string](Get-OptionalValue -Object $policy -Name "information_admin_brigade_id" -Default "")

$effectiveReportPath = if ([string]::IsNullOrWhiteSpace($ReportPath)) { [string](Get-OptionalValue -Object $taskPayload -Name "report_path" -Default "") } else { $ReportPath }
$effectiveScopePaths = if (@($ScopePaths).Count -gt 0) { @($ScopePaths) } else { @(Get-OptionalValue -Object $taskPayload -Name "scope_paths" -Default @()) }
$effectiveSummary = if ([string]::IsNullOrWhiteSpace($Summary)) {
    $fallback = [string](Get-OptionalValue -Object $taskPayload -Name "last_activity_notes" -Default "")
    if ([string]::IsNullOrWhiteSpace($fallback)) { "Task outcome recorded." } else { $fallback }
}
else {
    $Summary
}

$observerActors = @($registry.brigades | ForEach-Object { [string]$_.actor_id } | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne $effectiveActor
} | Sort-Object -Unique)

$visibility = [string](Get-OptionalValue -Object $policy -Name "completion_report_visibility" -Default "ALL_BRIGADES_READ")
$executionIntent = if ($Outcome -in @("BLOCKED", "DELEGATED", "CANCELLED")) { "DECISION" } else { "STATUS" }
$writtenAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$noteTitle = "Wynik {0} :: {1} :: {2}" -f $(if ($null -ne $brigade) { [string]$brigade.brigade_id } else { $effectiveActor }), [string]$taskPayload.title, $Outcome

$scopeLines = if (@($effectiveScopePaths).Count -gt 0) {
    @($effectiveScopePaths | ForEach-Object { "- $_" })
}
else {
    @("- none")
}

$nextActionText = if ([string]::IsNullOrWhiteSpace($NextAction)) { "none" } else { $NextAction }
$codexActionText = if ([string]::IsNullOrWhiteSpace($CodexAction)) { "none" } else { $CodexAction }
$completionRule = [string](Get-OptionalValue -Object $policy -Name "completion_report_rule" -Default "Report the result to all brigades and Codex.")
$checkedLines = Get-BulletLines -Values @($Checked)
$confirmedLines = Get-BulletLines -Values @($Confirmed)
$blockerLines = Get-BulletLines -Values @($Blockers)
$changedFileLines = Get-BulletLines -Values @($ChangedFiles)
$artifactLines = Get-BulletLines -Values @($OutputArtifacts)
$delegateLines = Get-BulletLines -Values @($DelegateWork)
$saveStatusText = if ([string]::IsNullOrWhiteSpace($SaveStatus)) { "none" } else { $SaveStatus }
$noteLines = New-Object System.Collections.Generic.List[string]
$noteLines.Add("# Brigade execution result")
$noteLines.Add("")
$noteLines.Add(("Task id: {0}" -f $TaskId))
$noteLines.Add(("Title: {0}" -f [string]$taskPayload.title))
$noteLines.Add(("Outcome: {0}" -f $Outcome))
$noteLines.Add(("Execution owner actor: {0}" -f $effectiveActor))
$noteLines.Add(("Brigade id: {0}" -f $(if ($null -ne $brigade) { [string]$brigade.brigade_id } else { "unknown" })))
$noteLines.Add(("Written at: {0}" -f $writtenAt))
$noteLines.Add(("Request id: {0}" -f [string](Get-OptionalValue -Object $taskPayload -Name 'request_id' -Default '')))
$noteLines.Add(("Request owner actor: {0}" -f $requestOwnerActor))
$noteLines.Add(("Request owner brigade id: {0}" -f $requestOwnerBrigadeId))
$noteLines.Add(("Parent claim id: {0}" -f [string](Get-OptionalValue -Object $taskPayload -Name 'parent_claim_id' -Default '')))
$noteLines.Add(("Source actor: {0}" -f [string](Get-OptionalValue -Object $taskPayload -Name 'source_actor' -Default '')))
$noteLines.Add(("Target brigade id: {0}" -f [string](Get-OptionalValue -Object $taskPayload -Name 'target_brigade_id' -Default '')))
$noteLines.Add(("Report to actor: {0}" -f $reportToActor))
$noteLines.Add(("Report to brigade id: {0}" -f $reportToBrigadeId))
$noteLines.Add(("Information admin actor: {0}" -f $informationAdminActor))
$noteLines.Add(("Information admin brigade id: {0}" -f $informationAdminBrigadeId))
$noteLines.Add(("Report path: {0}" -f $effectiveReportPath))
$noteLines.Add("")
$noteLines.Add("## Summary")
$noteLines.Add($effectiveSummary)
$noteLines.Add("")
$noteLines.Add("## Checked")
foreach ($line in $checkedLines) {
    $noteLines.Add([string]$line)
}
$noteLines.Add("")
$noteLines.Add("## Confirmed")
foreach ($line in $confirmedLines) {
    $noteLines.Add([string]$line)
}
$noteLines.Add("")
$noteLines.Add("## Blockers")
foreach ($line in $blockerLines) {
    $noteLines.Add([string]$line)
}
$noteLines.Add("")
$noteLines.Add("## Changed files")
foreach ($line in $changedFileLines) {
    $noteLines.Add([string]$line)
}
$noteLines.Add("")
$noteLines.Add("## Output artifacts")
foreach ($line in $artifactLines) {
    $noteLines.Add([string]$line)
}
$noteLines.Add("")
$noteLines.Add("## Save status")
$noteLines.Add($saveStatusText)
$noteLines.Add("")
$noteLines.Add("## Delegate further work")
foreach ($line in $delegateLines) {
    $noteLines.Add([string]$line)
}
$noteLines.Add("")
$noteLines.Add("## Codex action")
$noteLines.Add($codexActionText)
$noteLines.Add("")
$noteLines.Add("## Next action")
$noteLines.Add($nextActionText)
$noteLines.Add("")
$noteLines.Add("## Scope paths")
foreach ($scopeLine in $scopeLines) {
    $noteLines.Add([string]$scopeLine)
}
$noteLines.Add("")
$noteLines.Add("## Broadcast contract")
$noteLines.Add(("- Visibility: {0}" -f $visibility))
$noteLines.Add(("- Audience: {0}" -f [string](Get-OptionalValue -Object $policy -Name 'completion_report_audience' -Default 'ALL_BRIGADES_AND_CODEX')))
$noteLines.Add(("- Request owner: {0} / {1}" -f $requestOwnerActor, $requestOwnerBrigadeId))
$noteLines.Add(("- Processing owner for this report: {0} / {1}" -f $reportToActor, $reportToBrigadeId))
$noteLines.Add(("- Rule: {0}" -f $completionRule))

$noteScriptPath = Join-Path $PSScriptRoot "WRITE_ORCHESTRATOR_NOTE.ps1"
if (-not (Test-Path -LiteralPath $noteScriptPath)) {
    throw "Missing note script: $noteScriptPath"
}

$defaultTags = @("brigade-result", $Outcome.ToLowerInvariant(), $effectiveActor)
if ($null -ne $brigade -and -not [string]::IsNullOrWhiteSpace([string]$brigade.brigade_id)) {
    $defaultTags += [string]$brigade.brigade_id
}
$effectiveTags = @($defaultTags + $Tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)

$notePath = & $noteScriptPath `
    -Title $noteTitle `
    -Text ($noteLines -join [Environment]::NewLine) `
    -MailboxDir $MailboxDir `
    -Author $effectiveActor `
    -SourceRole "brigade_result" `
    -RequestOwnerActor $requestOwnerActor `
    -RequestOwnerBrigadeId $requestOwnerBrigadeId `
    -TargetActor $reportToActor `
    -TargetBrigadeId $reportToBrigadeId `
    -ReportToActor $reportToActor `
    -ReportToBrigadeId $reportToBrigadeId `
    -ObserverActors $observerActors `
    -Visibility $visibility `
    -ExecutionIntent $executionIntent `
    -ExecutionPolicy "BROADCAST_READ_ONLY" `
    -NonTargetPolicy "READ_ONLY" `
    -RequiresSafetyReview $false `
    -RelatedRequestId ([string](Get-OptionalValue -Object $taskPayload -Name "request_id" -Default "")) `
    -Tags $effectiveTags

$taskPayload.updated_at_local = $writtenAt
if ($taskPayload.PSObject.Properties.Name -contains "last_result_outcome") {
    $taskPayload.last_result_outcome = $Outcome
}
else {
    $taskPayload | Add-Member -NotePropertyName last_result_outcome -NotePropertyValue $Outcome -Force
}
if ($taskPayload.PSObject.Properties.Name -contains "last_result_note_path") {
    $taskPayload.last_result_note_path = [string]$notePath
}
else {
    $taskPayload | Add-Member -NotePropertyName last_result_note_path -NotePropertyValue ([string]$notePath) -Force
}
if ($taskPayload.PSObject.Properties.Name -contains "last_result_reported_at_local") {
    $taskPayload.last_result_reported_at_local = $writtenAt
}
else {
    $taskPayload | Add-Member -NotePropertyName last_result_reported_at_local -NotePropertyValue $writtenAt -Force
}
if ($taskPayload.PSObject.Properties.Name -contains "last_result_changed_files") {
    $taskPayload.last_result_changed_files = @($ChangedFiles)
}
else {
    $taskPayload | Add-Member -NotePropertyName last_result_changed_files -NotePropertyValue @($ChangedFiles) -Force
}
if ($taskPayload.PSObject.Properties.Name -contains "last_result_output_artifacts") {
    $taskPayload.last_result_output_artifacts = @($OutputArtifacts)
}
else {
    $taskPayload | Add-Member -NotePropertyName last_result_output_artifacts -NotePropertyValue @($OutputArtifacts) -Force
}
if ($taskPayload.PSObject.Properties.Name -contains "last_result_save_status") {
    $taskPayload.last_result_save_status = $saveStatusText
}
else {
    $taskPayload | Add-Member -NotePropertyName last_result_save_status -NotePropertyValue $saveStatusText -Force
}
Write-JsonFile -Path $taskJsonPath -Payload $taskPayload

Write-JsonFile -Path (Join-Path $statusDir "result_note_latest.json") -Payload ([ordered]@{
    action = "result_note"
    task_id = $TaskId
    actor = $effectiveActor
    outcome = $Outcome
    note_path = [string]$notePath
    written_at_local = $writtenAt
})

[pscustomobject]@{
    task_id = $TaskId
    actor = $effectiveActor
    brigade_id = if ($null -ne $brigade) { [string]$brigade.brigade_id } else { "" }
    outcome = $Outcome
    note_path = [string]$notePath
} | Format-List
