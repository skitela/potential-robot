param(
    [Parameter(Mandatory = $true)]
    [string]$ClaimId,
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$Outcome = "RELEASED",
    [string]$ReleaseNotes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$claimsActiveDir = Join-Path $MailboxDir "coordination\claims\active"
$claimsReleasedDir = Join-Path $MailboxDir "coordination\claims\released"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $claimsActiveDir, $claimsReleasedDir, $statusDir | Out-Null

function Read-JsonFile {
    param([string]$Path)

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

$sourceJsonPath = Join-Path $claimsActiveDir ("{0}.json" -f $ClaimId)
$sourceMdPath = Join-Path $claimsActiveDir ("{0}.md" -f $ClaimId)
if (-not (Test-Path -LiteralPath $sourceJsonPath)) {
    throw "Missing active claim: $sourceJsonPath"
}

$payload = Read-JsonFile -Path $sourceJsonPath
if ($null -eq $payload) {
    throw "Unable to parse claim JSON: $sourceJsonPath"
}

$releasedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$payload.state = $Outcome
$payload | Add-Member -NotePropertyName released_at_local -NotePropertyValue $releasedAt -Force
$payload | Add-Member -NotePropertyName release_notes -NotePropertyValue $ReleaseNotes -Force
$payload | Add-Member -NotePropertyName outcome -NotePropertyValue $Outcome -Force

$targetJsonPath = Join-Path $claimsReleasedDir ([IO.Path]::GetFileName($sourceJsonPath))
$targetMdPath = Join-Path $claimsReleasedDir ([IO.Path]::GetFileName($sourceMdPath))

Write-JsonFile -Path $targetJsonPath -Payload $payload
Remove-Item -LiteralPath $sourceJsonPath -Force

if (Test-Path -LiteralPath $sourceMdPath) {
    $body = Get-Content -LiteralPath $sourceMdPath -Raw -Encoding UTF8
    $body += [Environment]::NewLine + [Environment]::NewLine + "## Release" + [Environment]::NewLine
    $body += "Released at: $releasedAt" + [Environment]::NewLine
    $body += "Outcome: $Outcome" + [Environment]::NewLine
    if (-not [string]::IsNullOrWhiteSpace($ReleaseNotes)) {
        $body += "Notes: $ReleaseNotes" + [Environment]::NewLine
    }
    Set-Content -LiteralPath $targetMdPath -Value $body -Encoding UTF8
    Remove-Item -LiteralPath $sourceMdPath -Force
}

Write-JsonFile -Path (Join-Path $statusDir "work_claim_latest.json") -Payload ([ordered]@{
    action = "release"
    claim_id = $ClaimId
    actor = [string]$payload.actor
    work_title = [string]$payload.work_title
    released_at_local = $releasedAt
    outcome = $Outcome
    release_notes = $ReleaseNotes
    claim_path = $targetJsonPath
})

[pscustomobject]@{
    claim_id = $ClaimId
    actor = [string]$payload.actor
    work_title = [string]$payload.work_title
    released_at_local = $releasedAt
    outcome = $Outcome
    claim_path = $targetJsonPath
} | Format-List