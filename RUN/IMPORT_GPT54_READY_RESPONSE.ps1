param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$ResponsePath = "",
    [switch]$ShowContent,
    [switch]$MarkConsumed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$readyDir = Join-Path $MailboxDir "responses\ready"
$consumedDir = Join-Path $MailboxDir "responses\consumed"
$statusDir = Join-Path $MailboxDir "status"

if (-not (Test-Path -LiteralPath $readyDir)) {
    throw "Missing ready responses directory: $readyDir"
}

New-Item -ItemType Directory -Force -Path $statusDir | Out-Null

function Resolve-ResponseJson {
    param(
        [string]$MaybePath,
        [string]$ReadyDir
    )

    if (-not [string]::IsNullOrWhiteSpace($MaybePath)) {
        if (-not (Test-Path -LiteralPath $MaybePath)) {
            throw "Missing response path: $MaybePath"
        }
        if ($MaybePath.ToLowerInvariant().EndsWith(".json")) {
            return (Resolve-Path -LiteralPath $MaybePath).Path
        }
        if ($MaybePath.ToLowerInvariant().EndsWith(".md")) {
            $candidate = [IO.Path]::ChangeExtension((Resolve-Path -LiteralPath $MaybePath).Path, ".json")
            if (-not (Test-Path -LiteralPath $candidate)) {
                throw "Missing response manifest for: $MaybePath"
            }
            return $candidate
        }
        throw "Unsupported response path extension: $MaybePath"
    }

    $latest = Get-ChildItem -LiteralPath $ReadyDir -Filter *_response.json -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $latest) {
        throw "No ready GPT responses found in: $ReadyDir"
    }
    return $latest.FullName
}

function Read-JsonFile {
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

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-InboxPayloadFromManifest {
    param(
        [object]$Manifest,
        [string]$ManifestJsonPath
    )

    $requestMeta = if ($null -ne $Manifest -and $Manifest.PSObject.Properties.Name -contains "request_meta") { $Manifest.request_meta } else { $null }
    $responsePath = if ($null -ne $Manifest -and $Manifest.PSObject.Properties.Name -contains "response_path") { [string]$Manifest.response_path } else { "" }
    $assistantExcerpt = ""
    if (-not [string]::IsNullOrWhiteSpace($responsePath) -and (Test-Path -LiteralPath $responsePath)) {
        $assistantExcerpt = Get-Content -LiteralPath $responsePath -Raw -Encoding UTF8
        if ($assistantExcerpt.Length -gt 1200) {
            $assistantExcerpt = $assistantExcerpt.Substring(0, 1200)
        }
    }

    return [ordered]@{
        has_response = $true
        request_id = if ($null -ne $Manifest) { [string]$Manifest.request_id } else { "" }
        title = if ($null -ne $requestMeta) { [string]$requestMeta.title } else { "" }
        source_path = if ($null -ne $requestMeta) { [string]$requestMeta.source_path } else { "" }
        response_json = $ManifestJsonPath
        response_markdown = $responsePath
        extracted_root = if ($null -ne $Manifest) { [string]$Manifest.extracted_root } else { "" }
        extracted_files_count = if ($null -ne $Manifest) { @($Manifest.extracted_files).Count } else { 0 }
        published_notes_count = if ($null -ne $Manifest -and $Manifest.PSObject.Properties.Name -contains "published_notes") { @($Manifest.published_notes).Count } else { 0 }
        html_snapshot_saved = if ($null -ne $Manifest -and $Manifest.PSObject.Properties.Name -contains "html_snapshot_saved") { [bool]$Manifest.html_snapshot_saved } else { $false }
        assistant_excerpt = $assistantExcerpt
    }
}

$responseJsonPath = Resolve-ResponseJson -MaybePath $ResponsePath -ReadyDir $readyDir
$payload = Get-Content -LiteralPath $responseJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
$responseMdPath = [string]$payload.response_path
$requestId = [string]$payload.request_id
$requestMeta = $payload.request_meta
$extractedRoot = [string]$payload.extracted_root

$summary = [pscustomobject]@{
    request_id = $requestId
    title = $requestMeta.title
    source_path = $requestMeta.source_path
    response_markdown = $responseMdPath
    extracted_root = $extractedRoot
    extracted_files = @($payload.extracted_files).Count
    html_snapshot_saved = [bool]$payload.html_snapshot_saved
}

$summary | Format-List

if ($ShowContent) {
    ""
    "----- GPT RESPONSE BEGIN -----"
    Get-Content -LiteralPath $responseMdPath -Raw -Encoding UTF8
    "----- GPT RESPONSE END -----"
}

if ($MarkConsumed) {
    $targetDir = Join-Path $consumedDir $requestId
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    $archivedResponseJsonPath = Join-Path $targetDir ([IO.Path]::GetFileName($responseJsonPath))
    $archivedResponseMdPath = Join-Path $targetDir ([IO.Path]::GetFileName($responseMdPath))

    $pathsToMove = @($responseJsonPath, $responseMdPath)
    if ($payload.PSObject.Properties.Name -contains "html_path") {
        $pathsToMove += [string]$payload.html_path
    }

    foreach ($path in $pathsToMove) {
        if (Test-Path -LiteralPath $path) {
            Move-Item -LiteralPath $path -Destination (Join-Path $targetDir ([IO.Path]::GetFileName($path))) -Force
        }
    }

    $archivedExtractedRoot = ""
    if (-not [string]::IsNullOrWhiteSpace($extractedRoot) -and (Test-Path -LiteralPath $extractedRoot)) {
        $archivedExtractedRoot = Join-Path $targetDir "extracted"
        Move-Item -LiteralPath $extractedRoot -Destination $archivedExtractedRoot -Force
    }

    $consumedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-JsonFile -Path (Join-Path $statusDir "gpt_last_consumed_response.json") -Payload ([ordered]@{
        request_id = $requestId
        consumed_dir = $targetDir
        response_json = $archivedResponseJsonPath
        response_markdown = $archivedResponseMdPath
        extracted_root = $archivedExtractedRoot
        consumed_at_local = $consumedAt
    })

    Write-JsonFile -Path (Join-Path $statusDir "gpt_last_response.json") -Payload ([ordered]@{
        request_id = $requestId
        response_path = $archivedResponseMdPath
        response_json = $archivedResponseJsonPath
        request_meta = $requestMeta
        written_at_local = $consumedAt
        consumed = $true
        consumed_dir = $targetDir
    })

    $latestReadyJson = Get-ChildItem -LiteralPath $readyDir -Filter *_response.json -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -ne $latestReadyJson) {
        $latestReadyPayload = Read-JsonFile -Path $latestReadyJson.FullName
        $inboxPayload = New-InboxPayloadFromManifest -Manifest $latestReadyPayload -ManifestJsonPath $latestReadyJson.FullName
        $lastSeenResponseJson = $latestReadyJson.FullName
    }
    else {
        $inboxPayload = [ordered]@{
            has_response = $false
            request_id = ""
            title = ""
            source_path = ""
            response_json = ""
            response_markdown = ""
            extracted_root = ""
            extracted_files_count = 0
            published_notes_count = 0
            html_snapshot_saved = $false
            assistant_excerpt = ""
            last_consumed_request_id = $requestId
            consumed_at_local = $consumedAt
        }
        $lastSeenResponseJson = ""
    }

    Write-JsonFile -Path (Join-Path $statusDir "gpt_inbox_latest.json") -Payload $inboxPayload
    Write-JsonFile -Path (Join-Path $statusDir "response_watch_state.json") -Payload ([ordered]@{
        last_seen_response_json = $lastSeenResponseJson
        last_inbox_payload = $inboxPayload
    })

    Write-Output ("Consumed response archived to: {0}" -f $targetDir)
}
