param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [int]$Limit = 50,
    [switch]$ShowReleased,
    [string]$Actor = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$claimsActiveDir = Join-Path $MailboxDir "coordination\claims\active"
$claimsReleasedDir = Join-Path $MailboxDir "coordination\claims\released"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $claimsActiveDir, $claimsReleasedDir, $statusDir | Out-Null

function Get-ClaimPayload {
    param([string]$JsonPath)

    try {
        return Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
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

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$now = Get-Date

$activeRows = Get-ChildItem -LiteralPath $claimsActiveDir -Filter *.json -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object {
        $claim = Get-ClaimPayload -JsonPath $_.FullName
        if ($null -eq $claim) {
            return
        }
        if (-not [string]::IsNullOrWhiteSpace($Actor) -and [string]$claim.actor -ne $Actor) {
            return
        }
        $expiresAt = Get-DateSafe -Text ([string]$claim.expires_at_local)
        $state = if ($null -ne $expiresAt -and $expiresAt -lt $now) { "STALE" } else { "ACTIVE" }
        [pscustomobject]@{
            state = $state
            actor = [string]$claim.actor
            work_title = [string]$claim.work_title
            report_path = [string]$claim.report_path
            scope_count = @($claim.scope_paths).Count
            expires_at_local = [string]$claim.expires_at_local
            claim_id = [string]$claim.claim_id
        }
    } | Select-Object -First $Limit

$releasedRows = @()
if ($ShowReleased) {
    $releasedRows = Get-ChildItem -LiteralPath $claimsReleasedDir -Filter *.json -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            $claim = Get-ClaimPayload -JsonPath $_.FullName
            if ($null -eq $claim) {
                return
            }
            if (-not [string]::IsNullOrWhiteSpace($Actor) -and [string]$claim.actor -ne $Actor) {
                return
            }
            [pscustomobject]@{
                state = [string]$claim.state
                actor = [string]$claim.actor
                work_title = [string]$claim.work_title
                report_path = [string]$claim.report_path
                scope_count = @($claim.scope_paths).Count
                expires_at_local = [string]$claim.expires_at_local
                claim_id = [string]$claim.claim_id
            }
        } | Select-Object -First $Limit
}

$summary = [ordered]@{
    active_claims = @($activeRows | Where-Object { $_.state -eq "ACTIVE" }).Count
    stale_claims = @($activeRows | Where-Object { $_.state -eq "STALE" }).Count
    released_claims_shown = @($releasedRows).Count
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

Write-JsonFile -Path (Join-Path $statusDir "workboard_latest.json") -Payload ([ordered]@{
    summary = $summary
    active_rows = @($activeRows)
    released_rows = @($releasedRows)
})

"ACTIVE / STALE CLAIMS"
@($activeRows) | Format-Table -AutoSize

if ($ShowReleased) {
    ""
    "RELEASED CLAIMS"
    @($releasedRows) | Format-Table -AutoSize
}

""
[pscustomobject]$summary | Format-List