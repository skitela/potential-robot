param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [string]$Actor = "",
    [ValidateSet("COMPLETED", "BLOCKED", "CANCELLED")]
    [string]$Outcome = "COMPLETED",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$Notes = "",
    [switch]$PublishResultNote,
    [string]$ResultSummary = "",
    [string[]]$Checked = @(),
    [string[]]$Confirmed = @(),
    [string[]]$Blockers = @(),
    [string[]]$DelegateWork = @(),
    [string]$CodexAction = "",
    [string]$NextAction = "",
    [string]$RegistryPath = ""
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
New-Item -ItemType Directory -Force -Path $tasksPendingDir, $tasksActiveDir, $tasksBlockedDir, $tasksDoneDir, $statusDir | Out-Null

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

function Find-TaskJson {
    param([string]$Id)
    foreach ($root in @($tasksPendingDir, $tasksActiveDir, $tasksBlockedDir)) {
        $candidate = Join-Path $root ("{0}.json" -f $Id)
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

$sourceJsonPath = Find-TaskJson -Id $TaskId
if ($null -eq $sourceJsonPath) {
    throw "Task not found in pending, active or blocked: $TaskId"
}

$payload = Read-JsonFile -Path $sourceJsonPath
if ($null -eq $payload) {
    throw "Unable to parse task: $sourceJsonPath"
}

if (-not [string]::IsNullOrWhiteSpace($Actor) -and [string]$payload.assigned_to -ne $Actor) {
    throw "Task is assigned to '$([string]$payload.assigned_to)', not '$Actor'."
}

$updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$payload.status = $Outcome
$payload.updated_at_local = $updatedAt
$payload.last_activity_at_local = $updatedAt
$payload.last_activity_title = "TASK_$Outcome"
$payload.last_activity_notes = $Notes
if ($payload.PSObject.Properties.Name -contains "outcome") {
    $payload.outcome = $Outcome
}
else {
    $payload | Add-Member -NotePropertyName outcome -NotePropertyValue $Outcome -Force
}

if ($Outcome -eq "COMPLETED" -or $Outcome -eq "CANCELLED") {
    if ($payload.PSObject.Properties.Name -contains "completed_at_local") {
        $payload.completed_at_local = $updatedAt
    }
    else {
        $payload | Add-Member -NotePropertyName completed_at_local -NotePropertyValue $updatedAt -Force
    }
    $targetRoot = $tasksDoneDir
}
else {
    if ($payload.PSObject.Properties.Name -contains "blocked_at_local") {
        $payload.blocked_at_local = $updatedAt
    }
    else {
        $payload | Add-Member -NotePropertyName blocked_at_local -NotePropertyValue $updatedAt -Force
    }
    $targetRoot = $tasksBlockedDir
}

$targetJsonPath = Join-Path $targetRoot ([IO.Path]::GetFileName($sourceJsonPath))
$sourceMdPath = [IO.Path]::ChangeExtension($sourceJsonPath, ".md")
$targetMdPath = Join-Path $targetRoot ([IO.Path]::GetFileName($sourceMdPath))
$statusActor = if ([string]::IsNullOrWhiteSpace($Actor)) { [string]$payload.assigned_to } else { $Actor }

Write-JsonFile -Path $targetJsonPath -Payload $payload
Remove-Item -LiteralPath $sourceJsonPath -Force
if (Test-Path -LiteralPath $sourceMdPath) {
    Move-Item -LiteralPath $sourceMdPath -Destination $targetMdPath -Force
}

Write-JsonFile -Path (Join-Path $statusDir "task_latest.json") -Payload ([ordered]@{
    action = "complete"
    task_id = $TaskId
    actor = $statusActor
    status = $Outcome
    task_path = $targetJsonPath
    written_at_local = $updatedAt
})

$resultNotePath = ""
if ($PublishResultNote) {
    $resultScriptPath = Join-Path $PSScriptRoot "WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1"
    if (-not (Test-Path -LiteralPath $resultScriptPath)) {
        throw "Missing execution result script: $resultScriptPath"
    }

    $effectiveResultSummary = if ([string]::IsNullOrWhiteSpace($ResultSummary)) { $Notes } else { $ResultSummary }
    $resultPayload = & $resultScriptPath `
        -TaskId $TaskId `
        -Actor $statusActor `
        -Outcome $Outcome `
        -Summary $effectiveResultSummary `
        -Checked $Checked `
        -Confirmed $Confirmed `
        -Blockers $Blockers `
        -DelegateWork $DelegateWork `
        -CodexAction $CodexAction `
        -NextAction $NextAction `
        -MailboxDir $MailboxDir `
        -RegistryPath $RegistryPath

    if ($null -ne $resultPayload -and $resultPayload.PSObject.Properties.Name -contains "note_path") {
        $resultNotePath = [string]$resultPayload.note_path
    }
}

[pscustomobject]@{
    task_id = $TaskId
    assigned_to = [string]$payload.assigned_to
    title = [string]$payload.title
    status = $Outcome
    task_path = $targetJsonPath
    result_note_path = $resultNotePath
} | Format-List
