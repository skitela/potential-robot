param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$ResponsePath = "",
    [switch]$RequireExtractedFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$readyDir = Join-Path $MailboxDir "responses\ready"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $statusDir | Out-Null

if (-not (Test-Path -LiteralPath $readyDir)) {
    throw "Missing ready responses directory: $readyDir"
}

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

function Get-SafePropertyString {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return ""
    }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return [string]$Object.$Name
    }
    return ""
}

$responseJsonPath = Resolve-ResponseJson -MaybePath $ResponsePath -ReadyDir $readyDir
$payload = Read-JsonFile -Path $responseJsonPath
if ($null -eq $payload) {
    throw "Unable to parse response manifest: $responseJsonPath"
}

$blockingIssues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$requiredFields = @("request_id", "request_path", "response_path", "extracted_root", "extracted_files", "status")
foreach ($field in $requiredFields) {
    if ($payload.PSObject.Properties.Name -notcontains $field) {
        $blockingIssues.Add("Missing manifest field: $field")
    }
}

$requestId = Get-SafePropertyString -Object $payload -Name "request_id"
$responseMdPath = Get-SafePropertyString -Object $payload -Name "response_path"
$requestMeta = if ($payload.PSObject.Properties.Name -contains "request_meta") { $payload.request_meta } else { $null }
$phase = Get-SafePropertyString -Object $requestMeta -Name "phase"
$title = Get-SafePropertyString -Object $requestMeta -Name "title"
$sourcePath = Get-SafePropertyString -Object $requestMeta -Name "source_path"

$responseBody = ""
if ([string]::IsNullOrWhiteSpace($responseMdPath) -or -not (Test-Path -LiteralPath $responseMdPath)) {
    $blockingIssues.Add("Response markdown file is missing: $responseMdPath")
}
else {
    $responseBody = Get-Content -LiteralPath $responseMdPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($responseBody)) {
        $blockingIssues.Add("Response markdown is empty.")
    }
    elseif ($responseBody.Trim().Length -lt 80) {
        $warnings.Add("Response is very short; verify that it is complete.")
    }
}

$extractedFiles = if ($payload.PSObject.Properties.Name -contains "extracted_files") { @($payload.extracted_files) } else { @() }
$publishedNotes = if ($payload.PSObject.Properties.Name -contains "published_notes") { @($payload.published_notes) } else { @() }

foreach ($item in $extractedFiles) {
    $filePath = Get-SafePropertyString -Object $item -Name "path"
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        $blockingIssues.Add("Extracted file entry is missing path.")
        continue
    }
    if (-not (Test-Path -LiteralPath $filePath)) {
        $blockingIssues.Add("Extracted file is missing on disk: $filePath")
    }
}

if ($RequireExtractedFiles -and @($extractedFiles).Count -eq 0) {
    $blockingIssues.Add("No extracted files were produced, but extracted files are required.")
}
elseif ($phase -eq "implementation" -and @($extractedFiles).Count -eq 0) {
    $warnings.Add("Phase is implementation, but response did not produce extracted files.")
}

if ([string]::IsNullOrWhiteSpace($title)) {
    $warnings.Add("Request title is missing in request_meta.")
}
if ([string]::IsNullOrWhiteSpace($sourcePath)) {
    $warnings.Add("Source path is missing in request_meta.")
}

$responseBodyLower = $responseBody.ToLowerInvariant()
if ($responseBodyLower -match "cannot access|can't access|cannot directly save|don't have access to your local|do not have access to your local") {
    $warnings.Add("Response appears to describe product limitations instead of deliverable implementation output.")
}

$lastRequest = Read-JsonFile -Path (Join-Path $statusDir "codex_last_request.json")
$matchedLatestRequest = $false
if ($null -ne $lastRequest) {
    $latestRequestId = Get-SafePropertyString -Object $lastRequest -Name "request_id"
    if (-not [string]::IsNullOrWhiteSpace($latestRequestId)) {
        $matchedLatestRequest = ($latestRequestId -eq $requestId)
        if (-not $matchedLatestRequest) {
            $warnings.Add("Response request_id does not match status\\codex_last_request.json.")
        }
    }
}

$verdict = if ($blockingIssues.Count -gt 0) { "NOT_READY" } elseif ($warnings.Count -gt 0) { "READY_WITH_WARNINGS" } else { "READY" }
$validatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$summary = [ordered]@{
    request_id = $requestId
    verdict = $verdict
    validated_at_local = $validatedAt
    response_json = $responseJsonPath
    response_markdown = $responseMdPath
    phase = $phase
    title = $title
    source_path = $sourcePath
    matched_latest_request = $matchedLatestRequest
    extracted_files_count = @($extractedFiles).Count
    published_notes_count = @($publishedNotes).Count
    blocking_issues = @($blockingIssues)
    warnings = @($warnings)
}

Write-JsonFile -Path (Join-Path $statusDir "gpt_validation_latest.json") -Payload $summary
[pscustomobject]$summary | Format-List