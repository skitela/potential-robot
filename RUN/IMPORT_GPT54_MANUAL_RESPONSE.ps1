param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RequestId = "",
    [string]$ResponsePath = "",
    [string]$ResponseText = "",
    [switch]$FromClipboard,
    [bool]$PublishNotes = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        return $null
    }
}

function Set-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-ResponseText {
    param(
        [string]$InputPath,
        [string]$InlineText,
        [switch]$UseClipboard
    )

    if ($UseClipboard) {
        return (Get-Clipboard -Raw)
    }
    if (-not [string]::IsNullOrWhiteSpace($InlineText)) {
        return $InlineText
    }
    if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        if (-not (Test-Path -LiteralPath $InputPath)) {
            throw "Missing response file: $InputPath"
        }
        return (Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8)
    }
    throw "Provide -ResponsePath, -ResponseText or use -FromClipboard."
}

function Resolve-RequestId {
    param(
        [string]$ExplicitRequestId,
        [string]$InputPath,
        [string]$MailboxRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRequestId)) {
        return $ExplicitRequestId
    }

    if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
        if ($baseName -match '^(?<id>.+?)_response$') {
            return $Matches.id
        }
        if (-not [string]::IsNullOrWhiteSpace($baseName)) {
            return $baseName
        }
    }

    $statusPath = Join-Path $MailboxRoot "status\codex_last_request.json"
    $payload = Get-JsonFile -Path $statusPath
    if ($null -ne $payload -and -not [string]::IsNullOrWhiteSpace([string]$payload.request_id)) {
        return [string]$payload.request_id
    }

    throw "Could not resolve request id. Provide -RequestId explicitly."
}

function Find-RequestRecord {
    param(
        [string]$MailboxRoot,
        [string]$ResolvedRequestId
    )

    $searchRoots = @("requests\pending", "requests\in_progress", "requests\done", "requests\failed", "requests\hold")
    foreach ($relativeRoot in $searchRoots) {
        $root = Join-Path $MailboxRoot $relativeRoot
        $mdPath = Join-Path $root ("{0}.md" -f $ResolvedRequestId)
        $jsonPath = Join-Path $root ("{0}.json" -f $ResolvedRequestId)
        if (Test-Path -LiteralPath $mdPath) {
            return [pscustomobject]@{
                state = $relativeRoot
                markdown_path = $mdPath
                meta_path = $jsonPath
                meta = Get-JsonFile -Path $jsonPath
            }
        }
    }
    return $null
}

function Move-RequestToDone {
    param(
        [object]$RequestRecord,
        [string]$MailboxRoot,
        [string]$ResolvedRequestId
    )

    $doneRoot = Join-Path $MailboxRoot "requests\done"
    New-Item -ItemType Directory -Force -Path $doneRoot | Out-Null

    if ($null -eq $RequestRecord) {
        return (Join-Path $doneRoot ("{0}.md" -f $ResolvedRequestId))
    }

    $targetMd = Join-Path $doneRoot ([IO.Path]::GetFileName($RequestRecord.markdown_path))
    $targetJson = Join-Path $doneRoot ([IO.Path]::GetFileName($RequestRecord.meta_path))

    if ($RequestRecord.state -ne "requests\done") {
        Move-Item -LiteralPath $RequestRecord.markdown_path -Destination $targetMd -Force
        if (Test-Path -LiteralPath $RequestRecord.meta_path) {
            Move-Item -LiteralPath $RequestRecord.meta_path -Destination $targetJson -Force
        }
    }

    return $targetMd
}

function Get-ExtractedFileBlocks {
    param(
        [string]$Text,
        [string]$TargetRoot
    )

    $rootPath = [IO.Path]::GetFullPath($TargetRoot)
    New-Item -ItemType Directory -Force -Path $rootPath | Out-Null
    $fileBlockMatches = [regex]::Matches($Text, '(?ms)^FILE:\s*(?<path>[^\r\n]+)\r?\n```[^\n]*\n(?<content>.*?)\n```')
    $results = @()
    foreach ($match in $fileBlockMatches) {
        $relativePath = $match.Groups['path'].Value.Trim().Replace('/', '\\')
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $rootPath $relativePath))
        if (-not $fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $parent = Split-Path -Parent $fullPath
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        Set-Content -LiteralPath $fullPath -Value $match.Groups['content'].Value -Encoding UTF8
        $results += [pscustomobject]@{
            path = $fullPath
            relative_path = $relativePath
        }
    }
    return @($results)
}

function Publish-NoteBlocks {
    param(
        [string]$MailboxRoot,
        [string]$ResolvedRequestId,
        [object]$RequestMeta,
        [object[]]$ExtractedFiles
    )

    $notesInbox = Join-Path $MailboxRoot "notes\inbox"
    New-Item -ItemType Directory -Force -Path $notesInbox | Out-Null
    $published = @()
    $index = 0

    foreach ($file in @($ExtractedFiles)) {
        $relative = [string]$file.relative_path
        if ([string]::IsNullOrWhiteSpace($relative)) {
            continue
        }

        $normalized = $relative.Replace('/', '\\')
        $prefix = ($normalized -split '\\')[0].ToLowerInvariant()
        if ($prefix -notin @('notes', 'shared_notes', 'bridge_notes')) {
            continue
        }

        $index += 1
        $title = [IO.Path]::GetFileNameWithoutExtension($normalized)
        $safeTitle = ($title -replace '[^A-Za-z0-9._-]','_')
        $noteId = "{0}_{1:00}_{2}" -f $ResolvedRequestId, $index, $safeTitle
        $sourceFile = [string]$file.path
        $suffix = [IO.Path]::GetExtension($sourceFile)
        if ([string]::IsNullOrWhiteSpace($suffix)) {
            $suffix = ".md"
        }
        $targetNote = Join-Path $notesInbox ("{0}{1}" -f $noteId, $suffix)
        Copy-Item -LiteralPath $sourceFile -Destination $targetNote -Force

        $meta = [ordered]@{
            note_id = $noteId
            request_id = $ResolvedRequestId
            request_title = if ($null -ne $RequestMeta) { [string]$RequestMeta.title } else { "" }
            title = $title
            author = "gpt54_pro"
            source = "manual_response_import"
            relative_path = $normalized
            note_path = $targetNote
            written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $metaPath = Join-Path $notesInbox ("{0}.json" -f $noteId)
        Set-JsonFile -Path $metaPath -Payload $meta
        $published += [pscustomobject]@{
            note_path = $targetNote
            meta_path = $metaPath
            title = $title
        }
    }

    return @($published)
}

$responseBody = Resolve-ResponseText -InputPath $ResponsePath -InlineText $ResponseText -UseClipboard:$FromClipboard
$resolvedRequestId = Resolve-RequestId -ExplicitRequestId $RequestId -InputPath $ResponsePath -MailboxRoot $MailboxDir

$readyRoot = Join-Path $MailboxDir "responses\ready"
$extractedRoot = Join-Path (Join-Path $MailboxDir "responses\extracted") $resolvedRequestId
$statusRoot = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $readyRoot, $statusRoot | Out-Null

$requestRecord = Find-RequestRecord -MailboxRoot $MailboxDir -ResolvedRequestId $resolvedRequestId
$requestMeta = if ($null -ne $requestRecord -and $null -ne $requestRecord.meta) { $requestRecord.meta } else { [ordered]@{
    request_id = $resolvedRequestId
    title = $resolvedRequestId
    source_path = ""
    source_file_name = ""
    queued_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
} }

$requestPathDone = Move-RequestToDone -RequestRecord $requestRecord -MailboxRoot $MailboxDir -ResolvedRequestId $resolvedRequestId
Set-JsonFile -Path (Join-Path $statusRoot "codex_last_request.json") -Payload ([ordered]@{
    request_id = $resolvedRequestId
    path = $requestPathDone
    meta_path = if ($null -ne $requestRecord) { Join-Path (Split-Path -Parent $requestPathDone) ([IO.Path]::GetFileName($requestRecord.meta_path)) } else { "" }
    request_meta = $requestMeta
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    state = "requests/done"
})
$extractedFiles = Get-ExtractedFileBlocks -Text $responseBody -TargetRoot $extractedRoot
$publishedNotes = if ($PublishNotes) { Publish-NoteBlocks -MailboxRoot $MailboxDir -ResolvedRequestId $resolvedRequestId -RequestMeta $requestMeta -ExtractedFiles $extractedFiles } else { @() }

$responseMdPath = Join-Path $readyRoot ("{0}_response.md" -f $resolvedRequestId)
$responseJsonPath = Join-Path $readyRoot ("{0}_response.json" -f $resolvedRequestId)
Set-Content -LiteralPath $responseMdPath -Value $responseBody -Encoding UTF8

$responsePayload = [ordered]@{
    request_id = $resolvedRequestId
    request_path = $requestPathDone
    request_meta = $requestMeta
    response_path = $responseMdPath
    extracted_root = $extractedRoot
    extracted_files = @($extractedFiles)
    published_notes = @($publishedNotes)
    status = [ordered]@{ mode = "manual_import" }
    html_snapshot_saved = $false
    recovered_after_timeout = $false
}
Set-JsonFile -Path $responseJsonPath -Payload $responsePayload

$gptLastResponse = [ordered]@{
    request_id = $resolvedRequestId
    response_path = $responseMdPath
    request_meta = $requestMeta
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
Set-JsonFile -Path (Join-Path $statusRoot "gpt_last_response.json") -Payload $gptLastResponse

$excerpt = $responseBody.Substring(0, [Math]::Min(1200, $responseBody.Length))
$inboxPayload = [ordered]@{
    has_response = $true
    request_id = $resolvedRequestId
    title = [string]$requestMeta.title
    source_path = [string]$requestMeta.source_path
    response_json = $responseJsonPath
    response_markdown = $responseMdPath
    extracted_root = $extractedRoot
    extracted_files_count = @($extractedFiles).Count
    published_notes_count = @($publishedNotes).Count
    html_snapshot_saved = $false
    assistant_excerpt = $excerpt
}
Set-JsonFile -Path (Join-Path $statusRoot "gpt_inbox_latest.json") -Payload $inboxPayload
Set-JsonFile -Path (Join-Path $statusRoot "response_watch_state.json") -Payload ([ordered]@{
    last_seen_response_json = $responseJsonPath
    last_inbox_payload = $inboxPayload
})

[pscustomobject]@{
    request_id = $resolvedRequestId
    response_markdown = $responseMdPath
    extracted_files = @($extractedFiles).Count
    published_notes = @($publishedNotes).Count
} | Format-List