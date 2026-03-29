param(
    [Parameter(Mandatory = $true)]
    [string]$WorkTitle,
    [string]$Actor = "codex",
    [string]$ActorSession = "",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$TaskId = "",
    [string]$ReportPath = "",
    [string[]]$ScopePaths = @(),
    [int]$LeaseMinutes = 90,
    [string]$Notes = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$claimsActiveDir = Join-Path $MailboxDir "coordination\claims\active"
$claimsReleasedDir = Join-Path $MailboxDir "coordination\claims\released"
$activityDir = Join-Path $MailboxDir "coordination\activity"
$tasksPendingDir = Join-Path $MailboxDir "coordination\tasks\pending"
$tasksActiveDir = Join-Path $MailboxDir "coordination\tasks\active"
$tasksBlockedDir = Join-Path $MailboxDir "coordination\tasks\blocked"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $claimsActiveDir, $claimsReleasedDir, $activityDir, $tasksPendingDir, $tasksActiveDir, $tasksBlockedDir, $statusDir | Out-Null

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

function Get-NormalizedPathKey {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ""
    }
    $trimmed = $PathValue.Trim().Replace('/', '\')
    return $trimmed.ToLowerInvariant()
}

function Test-PathOverlap {
    param(
        [string]$Left,
        [string]$Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }

    return $Left.StartsWith($Right, [System.StringComparison]::OrdinalIgnoreCase) -or
        $Right.StartsWith($Left, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ClaimPayload {
    param([string]$JsonPath)

    return Read-JsonFile -Path $JsonPath
}

function Get-DateSafe {
    param([string]$Text)

    try {
        return [datetime]::Parse($Text)
    }
    catch {
        return $null
    }
}

function Find-TaskContext {
    param([string]$Id)

    foreach ($entry in @(
        @{ root = $tasksPendingDir; state = "PENDING" },
        @{ root = $tasksActiveDir; state = "ACTIVE" },
        @{ root = $tasksBlockedDir; state = "BLOCKED" }
    )) {
        $candidate = Join-Path $entry.root ("{0}.json" -f $Id)
        if (Test-Path -LiteralPath $candidate) {
            return [pscustomobject]@{
                path = $candidate
                state = $entry.state
                root = $entry.root
            }
        }
    }

    return $null
}

function Start-TaskIfNeeded {
    param(
        [string]$Id,
        [string]$ClaimActor,
        [string]$StartedAt,
        [string]$ClaimNotes
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return $null
    }

    $context = Find-TaskContext -Id $Id
    if ($null -eq $context) {
        throw "Task not found for claim activation: $Id"
    }

    $taskPayload = Read-JsonFile -Path $context.path
    if ($null -eq $taskPayload) {
        throw "Unable to parse task for claim activation: $($context.path)"
    }

    if ([string]$taskPayload.assigned_to -ne $ClaimActor) {
        throw "Task '$Id' is assigned to '$([string]$taskPayload.assigned_to)', not '$ClaimActor'."
    }

    if ($context.state -eq "ACTIVE") {
        return [pscustomobject]@{
            task_path = $context.path
            task_status = "ACTIVE"
        }
    }

    $taskPayload.status = "ACTIVE"
    $taskPayload.updated_at_local = $StartedAt
    $taskPayload.last_activity_at_local = $StartedAt
    $taskPayload.last_activity_title = "TASK_STARTED_FROM_CLAIM"
    $taskPayload.last_activity_notes = if ([string]::IsNullOrWhiteSpace($ClaimNotes)) { "Task started from claim" } else { $ClaimNotes }
    if ($taskPayload.PSObject.Properties.Name -notcontains "started_at_local" -or [string]::IsNullOrWhiteSpace([string]$taskPayload.started_at_local)) {
        $taskPayload | Add-Member -NotePropertyName started_at_local -NotePropertyValue $StartedAt -Force
    }

    $targetJsonPath = Join-Path $tasksActiveDir ([IO.Path]::GetFileName($context.path))
    $sourceMdPath = [IO.Path]::ChangeExtension($context.path, ".md")
    $targetMdPath = Join-Path $tasksActiveDir ([IO.Path]::GetFileName($sourceMdPath))

    Write-JsonFile -Path $targetJsonPath -Payload $taskPayload
    if ($context.path -ne $targetJsonPath) {
        Remove-Item -LiteralPath $context.path -Force
    }
    if (Test-Path -LiteralPath $sourceMdPath) {
        if ($sourceMdPath -ne $targetMdPath) {
            Move-Item -LiteralPath $sourceMdPath -Destination $targetMdPath -Force
        }
    }

    Write-JsonFile -Path (Join-Path $statusDir "task_latest.json") -Payload ([ordered]@{
        action = "start_from_claim"
        task_id = $Id
        actor = $ClaimActor
        status = "ACTIVE"
        task_path = $targetJsonPath
        written_at_local = $StartedAt
    })

    return [pscustomobject]@{
        task_path = $targetJsonPath
        task_status = "ACTIVE"
    }
}

if ([string]::IsNullOrWhiteSpace($ActorSession)) {
    $ActorSession = "{0}@{1}" -f $Actor, $env:COMPUTERNAME
}

$normalizedReportPath = Get-NormalizedPathKey -PathValue $ReportPath
$normalizedScopePaths = @($ScopePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Get-NormalizedPathKey -PathValue $_ })

$activeClaims = Get-ChildItem -LiteralPath $claimsActiveDir -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$now = Get-Date
$conflicts = @()

foreach ($item in $activeClaims) {
    $claim = Get-ClaimPayload -JsonPath $item.FullName
    if ($null -eq $claim) {
        continue
    }

    $expiresAt = Get-DateSafe -Text ([string]$claim.expires_at_local)
    if ($null -ne $expiresAt -and $expiresAt -lt $now) {
        continue
    }

    if ([string]$claim.actor -eq $Actor) {
        continue
    }

    $claimReport = Get-NormalizedPathKey -PathValue ([string]$claim.report_path)
    $claimScopes = @()
    if ($claim.PSObject.Properties.Name -contains "scope_paths") {
        $claimScopes = @($claim.scope_paths | ForEach-Object { Get-NormalizedPathKey -PathValue ([string]$_) })
    }

    $hasConflict = $false
    if (-not [string]::IsNullOrWhiteSpace($normalizedReportPath) -and $normalizedReportPath -eq $claimReport) {
        $hasConflict = $true
    }

    if (-not $hasConflict) {
        foreach ($scope in $normalizedScopePaths) {
            if (Test-PathOverlap -Left $scope -Right $claimReport) {
                $hasConflict = $true
                break
            }
            foreach ($otherScope in $claimScopes) {
                if (Test-PathOverlap -Left $scope -Right $otherScope) {
                    $hasConflict = $true
                    break
                }
            }
            if ($hasConflict) {
                break
            }
        }
    }

    if ($hasConflict) {
        $conflicts += [pscustomobject]@{
            claim_id = [string]$claim.claim_id
            actor = [string]$claim.actor
            work_title = [string]$claim.work_title
            report_path = [string]$claim.report_path
            expires_at_local = [string]$claim.expires_at_local
        }
    }
}

if ($conflicts.Count -gt 0 -and -not $Force) {
    $conflictText = ($conflicts | ForEach-Object {
        "- {0} | {1} | {2} | {3}" -f $_.claim_id, $_.actor, $_.work_title, $_.report_path
    }) -join [Environment]::NewLine
    throw "Detected overlapping active claims. Use -Force only if you intentionally want parallel overlap.`n$conflictText"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeActor = ($Actor -replace '[^A-Za-z0-9._-]', '_')
$safeTitle = ($WorkTitle -replace '[^A-Za-z0-9._-]', '_')
$claimId = "{0}_{1}_{2}" -f $timestamp, $safeActor, $safeTitle
$claimPath = Join-Path $claimsActiveDir ("{0}.json" -f $claimId)
$claimMdPath = Join-Path $claimsActiveDir ("{0}.md" -f $claimId)
$expiresAtLocal = $now.AddMinutes($LeaseMinutes).ToString("yyyy-MM-dd HH:mm:ss")
$createdAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
$taskActivation = Start-TaskIfNeeded -Id $TaskId -ClaimActor $Actor -StartedAt $createdAtLocal -ClaimNotes $Notes

$payload = [ordered]@{
    claim_id = $claimId
    actor = $Actor
    actor_session = $ActorSession
    work_title = $WorkTitle
    created_at_local = $createdAtLocal
    expires_at_local = $expiresAtLocal
    state = "ACTIVE"
    task_id = $TaskId
    report_path = $ReportPath
    scope_paths = @($ScopePaths)
    notes = $Notes
    conflicts_with = @($conflicts)
}

$bodyLines = @(
    "# Work Claim"
    ""
    "Claim id: $claimId"
    "Actor: $Actor"
    "Actor session: $ActorSession"
    "Work title: $WorkTitle"
    "Created at: $($payload.created_at_local)"
    "Expires at: $expiresAtLocal"
    "Task id: $TaskId"
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

Set-Content -LiteralPath $claimMdPath -Value ($bodyLines -join [Environment]::NewLine) -Encoding UTF8
Write-JsonFile -Path $claimPath -Payload $payload
Write-JsonFile -Path (Join-Path $statusDir "work_claim_latest.json") -Payload ([ordered]@{
    action = "claim"
    claim_id = $claimId
    actor = $Actor
    work_title = $WorkTitle
    created_at_local = $payload.created_at_local
    expires_at_local = $expiresAtLocal
    claim_path = $claimPath
    task_id = $TaskId
    task_status = if ($null -ne $taskActivation) { [string]$taskActivation.task_status } else { "" }
    report_path = $ReportPath
    scope_paths = @($ScopePaths)
    conflicts_count = $conflicts.Count
})

[pscustomobject]@{
    claim_id = $claimId
    actor = $Actor
    work_title = $WorkTitle
    task_id = $TaskId
    report_path = $ReportPath
    expires_at_local = $expiresAtLocal
    conflicts_count = $conflicts.Count
    claim_path = $claimPath
} | Format-List