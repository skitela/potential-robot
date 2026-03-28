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

    $pathsToMove = @($responseJsonPath, $responseMdPath)
    if ($payload.PSObject.Properties.Name -contains "html_path") {
        $pathsToMove += [string]$payload.html_path
    }

    foreach ($path in $pathsToMove) {
        if (Test-Path -LiteralPath $path) {
            Move-Item -LiteralPath $path -Destination (Join-Path $targetDir ([IO.Path]::GetFileName($path))) -Force
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($extractedRoot) -and (Test-Path -LiteralPath $extractedRoot)) {
        Move-Item -LiteralPath $extractedRoot -Destination (Join-Path $targetDir "extracted") -Force
    }

    Write-Output ("Consumed response archived to: {0}" -f $targetDir)
}
