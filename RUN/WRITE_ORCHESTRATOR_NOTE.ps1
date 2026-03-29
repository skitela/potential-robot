param(
    [string]$Title = "",
    [string]$Text = "",
    [string]$SourcePath = "",
    [switch]$FromClipboard,
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$Author = "codex",
    [string]$SourceRole = "local_agent",
    [string]$TargetActor = "",
    [string]$TargetBrigadeId = "",
    [string[]]$ObserverActors = @(),
    [ValidateSet("ALL_BRIGADES_READ", "TARGET_PLUS_OBSERVERS", "TARGET_ONLY")]
    [string]$Visibility = "ALL_BRIGADES_READ",
    [ValidateSet("INFO", "QUESTION", "ACTION_REQUEST", "AUDIT_REQUEST", "HANDOFF", "STATUS", "DECISION")]
    [string]$ExecutionIntent = "INFO",
    [ValidateSet("BROADCAST_READ_ONLY", "TARGET_ONLY_AFTER_REVIEW", "SHARED_REVIEW")]
    [string]$ExecutionPolicy = "",
    [ValidateSet("READ_ONLY", "READ_AND_ESCALATE_IF_NEEDED", "READ_AND_SUPPORT_IF_ASKED")]
    [string]$NonTargetPolicy = "READ_AND_ESCALATE_IF_NEEDED",
    [Nullable[bool]]$RequiresSafetyReview = $null,
    [string]$RelatedRequestId = "",
    [string[]]$Tags = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TextSha256 {
    param([string]$Body)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $hash = $sha.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $sha.Dispose()
    }
}

if ($FromClipboard) {
    $Text = Get-Clipboard -Raw
}

if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Missing source file: $SourcePath"
    }
    $Text = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($Text)) {
    throw "Provide -Text, -SourcePath or use -FromClipboard."
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = if (-not [string]::IsNullOrWhiteSpace($SourcePath)) { [IO.Path]::GetFileNameWithoutExtension($SourcePath) } else { "Bridge note" }
}

$effectiveExecutionPolicy = $ExecutionPolicy
if ([string]::IsNullOrWhiteSpace($effectiveExecutionPolicy)) {
    $effectiveExecutionPolicy = if (-not [string]::IsNullOrWhiteSpace($TargetActor) -or -not [string]::IsNullOrWhiteSpace($TargetBrigadeId)) {
        "TARGET_ONLY_AFTER_REVIEW"
    }
    else {
        "BROADCAST_READ_ONLY"
    }
}

$effectiveSafetyReview = $RequiresSafetyReview
if ($null -eq $effectiveSafetyReview) {
    $effectiveSafetyReview = (
        -not [string]::IsNullOrWhiteSpace($TargetActor) -or
        -not [string]::IsNullOrWhiteSpace($TargetBrigadeId) -or
        $ExecutionIntent -in @("ACTION_REQUEST", "AUDIT_REQUEST", "HANDOFF", "DECISION")
    )
}

$notesInbox = Join-Path $MailboxDir "notes\inbox"
New-Item -ItemType Directory -Force -Path $notesInbox | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeAuthor = ($Author -replace '[^A-Za-z0-9._-]','_')
$safeTitle = ($Title -replace '[^A-Za-z0-9._-]','_')
$noteId = "{0}_{1}_{2}" -f $timestamp, $safeAuthor, $safeTitle
$notePath = Join-Path $notesInbox ("{0}.md" -f $noteId)
$metaPath = Join-Path $notesInbox ("{0}.json" -f $noteId)

Set-Content -LiteralPath $notePath -Value $Text -Encoding UTF8

$meta = [ordered]@{
    note_id = $noteId
    title = $Title
    author = $Author
    source = $SourceRole
    target_actor = $TargetActor
    target_brigade_id = $TargetBrigadeId
    observer_actors = @($ObserverActors)
    visibility = $Visibility
    execution_intent = $ExecutionIntent
    execution_policy = $effectiveExecutionPolicy
    non_target_policy = $NonTargetPolicy
    requires_safety_review = [bool]$effectiveSafetyReview
    note_path = $notePath
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    sha256 = Get-TextSha256 -Body $Text
}

if (-not [string]::IsNullOrWhiteSpace($RelatedRequestId)) {
    $meta["request_id"] = $RelatedRequestId
}
if (@($Tags).Count -gt 0) {
    $meta["tags"] = @($Tags)
}
if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
    $meta["source_path"] = $SourcePath
}

$meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metaPath -Encoding UTF8
Write-Output $notePath
