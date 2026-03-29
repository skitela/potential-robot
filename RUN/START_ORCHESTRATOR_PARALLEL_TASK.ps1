param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [string]$Actor = "",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$Notes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tasksPendingDir = Join-Path $MailboxDir "coordination\tasks\pending"
$tasksActiveDir = Join-Path $MailboxDir "coordination\tasks\active"
$tasksBlockedDir = Join-Path $MailboxDir "coordination\tasks\blocked"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $tasksPendingDir, $tasksActiveDir, $tasksBlockedDir, $statusDir | Out-Null

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

function Find-TaskFile {
    param([string]$Id)
    $roots = @($tasksPendingDir, $tasksBlockedDir)
    foreach ($root in $roots) {
        $candidate = Join-Path $root ("{0}.json" -f $Id)
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

$sourceJsonPath = Find-TaskFile -Id $TaskId
if ($null -eq $sourceJsonPath) {
    throw "Task not found in pending or blocked: $TaskId"
}

$payload = Read-JsonFile -Path $sourceJsonPath
if ($null -eq $payload) {
    throw "Unable to parse task: $sourceJsonPath"
}

if (-not [string]::IsNullOrWhiteSpace($Actor) -and [string]$payload.assigned_to -ne $Actor) {
    throw "Task is assigned to '$([string]$payload.assigned_to)', not '$Actor'."
}

$startedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$payload.status = "ACTIVE"
$payload.updated_at_local = $startedAt
$payload.last_activity_at_local = $startedAt
$payload.last_activity_title = "TASK_STARTED"
$payload.last_activity_notes = $Notes
if ($payload.PSObject.Properties.Name -notcontains "started_at_local" -or [string]::IsNullOrWhiteSpace([string]$payload.started_at_local)) {
    $payload | Add-Member -NotePropertyName started_at_local -NotePropertyValue $startedAt -Force
}

$targetJsonPath = Join-Path $tasksActiveDir ([IO.Path]::GetFileName($sourceJsonPath))
$sourceMdPath = [IO.Path]::ChangeExtension($sourceJsonPath, ".md")
$targetMdPath = Join-Path $tasksActiveDir ([IO.Path]::GetFileName($sourceMdPath))
$statusActor = if ([string]::IsNullOrWhiteSpace($Actor)) { [string]$payload.assigned_to } else { $Actor }

Write-JsonFile -Path $targetJsonPath -Payload $payload
Remove-Item -LiteralPath $sourceJsonPath -Force
if (Test-Path -LiteralPath $sourceMdPath) {
    Move-Item -LiteralPath $sourceMdPath -Destination $targetMdPath -Force
}

Write-JsonFile -Path (Join-Path $statusDir "task_latest.json") -Payload ([ordered]@{
    action = "start"
    task_id = $TaskId
    actor = $statusActor
    status = "ACTIVE"
    task_path = $targetJsonPath
    written_at_local = $startedAt
})

[pscustomobject]@{
    task_id = $TaskId
    assigned_to = [string]$payload.assigned_to
    title = [string]$payload.title
    status = "ACTIVE"
    task_path = $targetJsonPath
} | Format-List
