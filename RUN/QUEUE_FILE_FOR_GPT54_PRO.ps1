param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [string]$Title = "",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$ExtraInstructions = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Missing source file: $SourcePath"
}

$pendingDir = Join-Path $MailboxDir "requests\pending"
New-Item -ItemType Directory -Force -Path $pendingDir | Out-Null

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
    extra_instructions_present = -not [string]::IsNullOrWhiteSpace($ExtraInstructions)
    queued_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
$meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $requestMetaPath -Encoding UTF8
Write-Output $requestPath
