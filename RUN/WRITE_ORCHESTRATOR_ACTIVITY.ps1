param(
    [Parameter(Mandatory = $true)]
    [string]$Actor,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$TaskId = "",
    [string]$ClaimId = "",
    [string]$ReportPath = "",
    [string[]]$ScopePaths = @(),
    [string]$Notes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$activityDir = Join-Path $MailboxDir "coordination\activity"
$tasksPendingDir = Join-Path $MailboxDir "coordination\tasks\pending"
$tasksActiveDir = Join-Path $MailboxDir "coordination\tasks\active"
$tasksBlockedDir = Join-Path $MailboxDir "coordination\tasks\blocked"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $activityDir, $tasksPendingDir, $tasksActiveDir, $tasksBlockedDir, $statusDir | Out-Null

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

function Get-TaskState {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    if ($Path.StartsWith($tasksPendingDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "PENDING"
    }
    if ($Path.StartsWith($tasksActiveDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "ACTIVE"
    }
    if ($Path.StartsWith($tasksBlockedDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "BLOCKED"
    }

    return ""
}

function Promote-TaskToActive {
    param(
        [string]$TaskJsonPath,
        [string]$TaskId,
        [string]$Actor,
        [string]$ActivatedAt,
        [string]$ActivityTitle,
        [string]$ActivityNotes
    )

    $taskPayload = Read-JsonFile -Path $TaskJsonPath
    if ($null -eq $taskPayload) {
        return $null
    }

    $taskPayload.status = "ACTIVE"
    $taskPayload.updated_at_local = $ActivatedAt
    $taskPayload.last_activity_at_local = $ActivatedAt
    $taskPayload.last_activity_title = $ActivityTitle
    $taskPayload.last_activity_notes = $ActivityNotes
    if ($taskPayload.PSObject.Properties.Name -notcontains "started_at_local" -or [string]::IsNullOrWhiteSpace([string]$taskPayload.started_at_local)) {
        $taskPayload | Add-Member -NotePropertyName started_at_local -NotePropertyValue $ActivatedAt -Force
    }

    $targetJsonPath = Join-Path $tasksActiveDir ([IO.Path]::GetFileName($TaskJsonPath))
    $sourceMdPath = [IO.Path]::ChangeExtension($TaskJsonPath, ".md")
    $targetMdPath = Join-Path $tasksActiveDir ([IO.Path]::GetFileName($sourceMdPath))

    Write-JsonFile -Path $targetJsonPath -Payload $taskPayload
    if ($TaskJsonPath -ne $targetJsonPath) {
        Remove-Item -LiteralPath $TaskJsonPath -Force
    }
    if ((Test-Path -LiteralPath $sourceMdPath) -and $sourceMdPath -ne $targetMdPath) {
        Move-Item -LiteralPath $sourceMdPath -Destination $targetMdPath -Force
    }

    Write-JsonFile -Path (Join-Path $statusDir "task_latest.json") -Payload ([ordered]@{
        action = "start_from_activity"
        task_id = $TaskId
        actor = $Actor
        status = "ACTIVE"
        task_path = $targetJsonPath
        written_at_local = $ActivatedAt
    })

    return $targetJsonPath
}

$writtenAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeActor = ($Actor -replace '[^A-Za-z0-9._-]', '_')
$safeTitle = ($Title -replace '[^A-Za-z0-9._-]', '_')
$activityId = "{0}_{1}_{2}" -f $timestamp, $safeActor, $safeTitle
$activityJsonPath = Join-Path $activityDir ("{0}.json" -f $activityId)
$activityMdPath = Join-Path $activityDir ("{0}.md" -f $activityId)

$payload = [ordered]@{
    activity_id = $activityId
    actor = $Actor
    title = $Title
    written_at_local = $writtenAt
    task_id = $TaskId
    claim_id = $ClaimId
    report_path = $ReportPath
    scope_paths = @($ScopePaths)
    notes = $Notes
}

$bodyLines = @(
    "# Activity"
    ""
    "Activity id: $activityId"
    "Actor: $Actor"
    "Title: $Title"
    "Written at: $writtenAt"
    "Task id: $TaskId"
    "Claim id: $ClaimId"
    "Report path: $ReportPath"
    ""
    "## Scope paths"
)

if (@($ScopePaths).Count -gt 0) {
    $bodyLines += @($ScopePaths | ForEach-Object { "- $_" })
}
else {
    $bodyLines += "- none"
}

$notesText = if ([string]::IsNullOrWhiteSpace($Notes)) { "none" } else { $Notes }

$bodyLines += @(
    "",
    "## Notes",
    $notesText
)

Set-Content -LiteralPath $activityMdPath -Value ($bodyLines -join [Environment]::NewLine) -Encoding UTF8
Write-JsonFile -Path $activityJsonPath -Payload $payload

if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
    $taskJsonPath = Find-TaskJson -Id $TaskId
    if ($null -ne $taskJsonPath) {
        $taskState = Get-TaskState -Path $taskJsonPath
        if ($taskState -in @("PENDING", "BLOCKED")) {
            $taskJsonPath = Promote-TaskToActive -TaskJsonPath $taskJsonPath -TaskId $TaskId -Actor $Actor -ActivatedAt $writtenAt -ActivityTitle $Title -ActivityNotes $Notes
        }

        if ($null -ne $taskJsonPath) {
            $taskPayload = Read-JsonFile -Path $taskJsonPath
            if ($null -ne $taskPayload) {
                $taskPayload.updated_at_local = $writtenAt
                $taskPayload.last_activity_at_local = $writtenAt
                $taskPayload.last_activity_title = $Title
                $taskPayload.last_activity_notes = $Notes
                Write-JsonFile -Path $taskJsonPath -Payload $taskPayload
            }
        }
    }
}

Write-JsonFile -Path (Join-Path $statusDir "activity_latest.json") -Payload ([ordered]@{
    activity_id = $activityId
    actor = $Actor
    title = $Title
    task_id = $TaskId
    claim_id = $ClaimId
    written_at_local = $writtenAt
    activity_path = $activityJsonPath
})

[pscustomobject]@{
    activity_id = $activityId
    actor = $Actor
    title = $Title
    task_id = $TaskId
    activity_path = $activityJsonPath
} | Format-List
