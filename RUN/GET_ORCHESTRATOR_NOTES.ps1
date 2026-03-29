param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [int]$Limit = 20,
    [switch]$ShowContent,
    [string]$NotePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$notesInbox = Join-Path $MailboxDir "notes\inbox"
if (-not (Test-Path -LiteralPath $notesInbox)) {
    throw "Missing notes inbox: $notesInbox"
}

function Get-NoteMeta {
    param([string]$JsonPath)

    try {
        return Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        return $null
    }
}

if (-not [string]::IsNullOrWhiteSpace($NotePath)) {
    if (-not (Test-Path -LiteralPath $NotePath)) {
        throw "Missing note path: $NotePath"
    }
    $jsonPath = [IO.Path]::ChangeExtension((Resolve-Path -LiteralPath $NotePath).Path, ".json")
    $meta = Get-NoteMeta -JsonPath $jsonPath
    if ($null -ne $meta) {
        $meta | Format-List
    }
    if ($ShowContent) {
        ""
        Get-Content -LiteralPath $NotePath -Raw -Encoding UTF8
    }
    return
}

$notes = Get-ChildItem -LiteralPath $notesInbox -Filter *.json -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $Limit

$rows = foreach ($item in $notes) {
    $meta = Get-NoteMeta -JsonPath $item.FullName
    if ($null -eq $meta) {
        continue
    }
    $requestId = ""
    if ($meta.PSObject.Properties.Name -contains "request_id") {
        $requestId = [string]$meta.request_id
    }
    $targetActor = ""
    if ($meta.PSObject.Properties.Name -contains "target_actor") {
        $targetActor = [string]$meta.target_actor
    }
    $executionIntent = ""
    if ($meta.PSObject.Properties.Name -contains "execution_intent") {
        $executionIntent = [string]$meta.execution_intent
    }
    $executionPolicy = ""
    if ($meta.PSObject.Properties.Name -contains "execution_policy") {
        $executionPolicy = [string]$meta.execution_policy
    }
    [pscustomobject]@{
        written_at_local = [string]$meta.written_at_local
        author = [string]$meta.author
        title = [string]$meta.title
        target_actor = $targetActor
        execution_intent = $executionIntent
        execution_policy = $executionPolicy
        request_id = $requestId
        note_path = [string]$meta.note_path
    }
}

$rows | Format-Table -AutoSize

if ($ShowContent -and @($rows).Count -gt 0) {
    $first = $rows[0].note_path
    ""
    Get-Content -LiteralPath $first -Raw -Encoding UTF8
}
