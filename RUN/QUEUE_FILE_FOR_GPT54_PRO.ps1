param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [string]$Title = "",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$ExtraInstructions = "",
    [string]$Topic = "",
    [string]$Phase = "",
    [string]$SourceRole = "codex",
    [string]$TargetRole = "gpt54_pro",
    [string[]]$RequiresAckFrom = @(),
    [switch]$CopyToClipboard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TextSha256 {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $sha.Dispose()
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $Payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Missing source file: $SourcePath"
}

$pendingDir = Join-Path $MailboxDir "requests\pending"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $pendingDir, $statusDir | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$baseName = [IO.Path]::GetFileNameWithoutExtension($SourcePath)
$safeBase = ($baseName -replace '[^A-Za-z0-9._-]','_')
$requestId = "{0}_{1}" -f $timestamp, $safeBase
$requestPath = Join-Path $pendingDir ("{0}.md" -f $requestId)
$requestMetaPath = Join-Path $pendingDir ("{0}.json" -f $requestId)

$content = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
$fileHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = $baseName
}

$bodyLines = @(
    "# $Title"
    ""
    "Source file: $SourcePath"
    "Request id: $requestId"
    ""
    "## Instructions for GPT-5.4 Pro"
    ""
    "- Read the attached content carefully."
    "- If you produce reusable bridge notes, return them as FILE blocks under notes/ or shared_notes/."
    "- If you want to return multiple files, use the exact format:"
    ""
    "FILE: relative/path.ext"
    '```text'
    "...content..."
    '```'
    ""
    "- Keep file names stable and practical."
    ""
    $ExtraInstructions
    ""
    "## Attached content"
    ""
    '```md'
    $content
    '```'
)

$body = ($bodyLines -join [Environment]::NewLine)
Set-Content -LiteralPath $requestPath -Value $body -Encoding UTF8

$meta = [ordered]@{
    request_id = $requestId
    title = $Title
    source_path = $SourcePath
    source_file_name = [IO.Path]::GetFileName($SourcePath)
    source_sha256 = $fileHash
    request_body_sha256 = Get-TextSha256 -Text $body
    extra_instructions_present = -not [string]::IsNullOrWhiteSpace($ExtraInstructions)
    queued_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    source_role = $SourceRole
    target_role = $TargetRole
    status = "NEW"
}

if (-not [string]::IsNullOrWhiteSpace($Topic)) {
    $meta["topic"] = $Topic
}
if (-not [string]::IsNullOrWhiteSpace($Phase)) {
    $meta["phase"] = $Phase
}
if (@($RequiresAckFrom).Count -gt 0) {
    $meta["requires_ack_from"] = @($RequiresAckFrom)
}

Write-JsonFile -Path $requestMetaPath -Payload $meta
Write-JsonFile -Path (Join-Path $statusDir "codex_last_request.json") -Payload ([ordered]@{
    request_id = $requestId
    path = $requestPath
    meta_path = $requestMetaPath
    request_meta = $meta
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    state = "requests/pending"
})

if ($CopyToClipboard) {
    Set-Clipboard -Value $body
}

Write-Output $requestPath