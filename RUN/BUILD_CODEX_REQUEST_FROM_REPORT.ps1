param(
    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    [string]$Title = "",
    [string]$Topic = "makro_i_mikro_bot",
    [ValidateSet("analysis", "review", "implementation", "validation", "rollback", "concept")]
    [string]$Phase = "analysis",
    [ValidateSet("codex", "executor", "reviewer", "operator")]
    [string]$SourceRole = "codex",
    [ValidateSet("gpt54_pro", "reviewer", "executor")]
    [string]$TargetRole = "gpt54_pro",
    [string]$RepoRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string[]]$Attachments = @(),
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$ExtraInstructions = ""
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

if (-not (Test-Path -LiteralPath $ReportPath)) {
    throw "Missing report file: $ReportPath"
}

$pendingDir = Join-Path $MailboxDir "requests\pending"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $pendingDir, $statusDir | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$baseName = [IO.Path]::GetFileNameWithoutExtension($ReportPath)
$safeBase = ($baseName -replace '[^A-Za-z0-9._-]', '_')
$requestId = "{0}_{1}" -f $timestamp, $safeBase
$requestPath = Join-Path $pendingDir ("{0}.md" -f $requestId)
$requestMetaPath = Join-Path $pendingDir ("{0}.json" -f $requestId)

$content = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8
$fileHash = (Get-FileHash -LiteralPath $ReportPath -Algorithm SHA256).Hash
if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = $baseName
}

$attachmentLines = @()
foreach ($attachment in $Attachments) {
    $attachmentLines += ("- {0}" -f $attachment)
}
if ($attachmentLines.Count -eq 0) {
    $attachmentLines = @("- none")
}

$bodyLines = @(
    "# $Title"
    ""
    "Request id: $requestId"
    "Topic: $Topic"
    "Phase: $Phase"
    "Source role: $SourceRole"
    "Target role: $TargetRole"
    "Repo root: $RepoRoot"
    "Report path: $ReportPath"
    ""
    "## Attachments"
)
$bodyLines += $attachmentLines
$bodyLines += @(
    ""
    "## Instructions for GPT-5.4 Pro"
    ""
    "- Treat this as a bounded collaboration request for the MAKRO_I_MIKRO_BOT system."
    "- Stay consistent with the current local architecture and existing file names."
    "- If implementation output needs more than one file, use the exact format:"
    ""
    "FILE: relative/path.ext"
    '```text'
    "...content..."
    '```'
    ""
    "- Separate diagnosis, implementation and validation clearly."
)

if (-not [string]::IsNullOrWhiteSpace($ExtraInstructions)) {
    $bodyLines += @(
        ""
        "## Extra instructions"
        ""
        $ExtraInstructions
    )
}

$bodyLines += @(
    ""
    "## Attached report"
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
    topic = $Topic
    phase = $Phase
    source_role = $SourceRole
    target_role = $TargetRole
    repo_root = $RepoRoot
    report_file = $ReportPath
    attachments = $Attachments
    requires_ack_from = @("reviewer", "executor")
    source_path = $ReportPath
    source_file_name = [IO.Path]::GetFileName($ReportPath)
    source_sha256 = $fileHash
    request_body_sha256 = Get-TextSha256 -Text $body
    extra_instructions_present = -not [string]::IsNullOrWhiteSpace($ExtraInstructions)
    queued_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    status = "NEW"
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
Write-Output $requestPath
