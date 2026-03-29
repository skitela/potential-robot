param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [int]$ChromeDebugPort = 9222,
    [string]$ChatUrl = "https://chatgpt.com/c/69c63027-795c-8390-9a23-d033b2e319cb"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$statusDir = Join-Path $MailboxDir "status"
$responsesReady = Join-Path $MailboxDir "responses\ready"
$responsesConsumed = Join-Path $MailboxDir "responses\consumed"
$requestsPending = Join-Path $MailboxDir "requests\pending"
$requestsInProgress = Join-Path $MailboxDir "requests\in_progress"
$requestsFailed = Join-Path $MailboxDir "requests\failed"
$requestsHold = Join-Path $MailboxDir "requests\hold"
$notesInbox = Join-Path $MailboxDir "notes\inbox"
$notesArchive = Join-Path $MailboxDir "notes\archive"
$claimsActive = Join-Path $MailboxDir "coordination\claims\active"
$claimsReleased = Join-Path $MailboxDir "coordination\claims\released"
$tasksPending = Join-Path $MailboxDir "coordination\tasks\pending"
$tasksActive = Join-Path $MailboxDir "coordination\tasks\active"
$tasksBlocked = Join-Path $MailboxDir "coordination\tasks\blocked"
$tasksDone = Join-Path $MailboxDir "coordination\tasks\done"
$activityDir = Join-Path $MailboxDir "coordination\activity"

function Get-StatusJson {
    param([string]$Name)
    $path = Join-Path $statusDir ("{0}.json" -f $Name)
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        return $null
    }
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

function Get-ClaimJson {
    param([string]$Path)
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        return $null
    }
}

$lastRequest = Get-StatusJson -Name "codex_last_request"
$lastResponse = Get-StatusJson -Name "gpt_last_response"
$lastError = Get-StatusJson -Name "orchestrator_error"
$launcher = Get-StatusJson -Name "launcher_latest"

$pendingMd = Get-ChildItem -LiteralPath $requestsPending -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$inProgressMd = Get-ChildItem -LiteralPath $requestsInProgress -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$failedMd = Get-ChildItem -LiteralPath $requestsFailed -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$heldMd = Get-ChildItem -LiteralPath $requestsHold -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$readyMd = Get-ChildItem -LiteralPath $responsesReady -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$consumedDirs = Get-ChildItem -LiteralPath $responsesConsumed -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$noteMd = Get-ChildItem -LiteralPath $notesInbox -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$archivedNoteMd = Get-ChildItem -LiteralPath $notesArchive -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$activeClaimJson = Get-ChildItem -LiteralPath $claimsActive -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$releasedClaimJson = Get-ChildItem -LiteralPath $claimsReleased -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$pendingTaskJson = Get-ChildItem -LiteralPath $tasksPending -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$activeTaskJson = Get-ChildItem -LiteralPath $tasksActive -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$blockedTaskJson = Get-ChildItem -LiteralPath $tasksBlocked -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$doneTaskJson = Get-ChildItem -LiteralPath $tasksDone -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$activityJson = Get-ChildItem -LiteralPath $activityDir -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

$now = Get-Date
$activeClaimsCount = 0
$staleClaimsCount = 0
foreach ($item in $activeClaimJson) {
    $claim = Get-ClaimJson -Path $item.FullName
    if ($null -eq $claim) {
        continue
    }
    $expiresAt = Get-DateSafe -Text ([string]$claim.expires_at_local)
    if ($null -ne $expiresAt -and $expiresAt -lt $now) {
        $staleClaimsCount += 1
    }
    else {
        $activeClaimsCount += 1
    }
}

$activeTasksCount = 0
$staleActiveTasksCount = 0
foreach ($item in $activeTaskJson) {
    $task = Get-ClaimJson -Path $item.FullName
    if ($null -eq $task) {
        continue
    }
    $lastActivityAt = Get-DateSafe -Text ([string]$task.last_activity_at_local)
    if ($null -ne $lastActivityAt -and $lastActivityAt -lt $now.AddMinutes(-30)) {
        $staleActiveTasksCount += 1
    }
    else {
        $activeTasksCount += 1
    }
}

$summary = [pscustomobject]@{
    pending_requests = @($pendingMd).Count
    in_progress_requests = @($inProgressMd).Count
    failed_requests = @($failedMd).Count
    held_requests = @($heldMd).Count
    ready_responses = @($readyMd).Count
    consumed_responses = @($consumedDirs).Count
    inbox_notes = @($noteMd).Count
    archived_notes = @($archivedNoteMd).Count
    active_work_claims = $activeClaimsCount
    stale_work_claims = $staleClaimsCount
    released_work_claims = @($releasedClaimJson).Count
    pending_parallel_tasks = @($pendingTaskJson).Count
    active_parallel_tasks = $activeTasksCount
    stale_parallel_tasks = $staleActiveTasksCount
    blocked_parallel_tasks = @($blockedTaskJson).Count
    done_parallel_tasks = @($doneTaskJson).Count
    last_request_file = if ($lastRequest) { [string]$lastRequest.path } else { "" }
    last_response_file = if ($lastResponse) { [string]$lastResponse.response_path } else { "" }
    last_note_file = if (@($noteMd).Count -gt 0) { $noteMd[0].FullName } else { "" }
    last_claim_file = if (@($activeClaimJson).Count -gt 0) { $activeClaimJson[0].FullName } elseif (@($releasedClaimJson).Count -gt 0) { $releasedClaimJson[0].FullName } else { "" }
    last_task_file = if (@($activeTaskJson).Count -gt 0) { $activeTaskJson[0].FullName } elseif (@($pendingTaskJson).Count -gt 0) { $pendingTaskJson[0].FullName } elseif (@($blockedTaskJson).Count -gt 0) { $blockedTaskJson[0].FullName } elseif (@($doneTaskJson).Count -gt 0) { $doneTaskJson[0].FullName } else { "" }
    last_activity_file = if (@($activityJson).Count -gt 0) { $activityJson[0].FullName } else { "" }
    chrome_debug_port = $ChromeDebugPort
    chat_url = if ($launcher -and $launcher.chat_url) { [string]$launcher.chat_url } else { $ChatUrl }
    last_error_summary = if ($lastError) { [string]$lastError.error } else { "" }
    mailbox_dir = $MailboxDir
}

$summary | Format-List
