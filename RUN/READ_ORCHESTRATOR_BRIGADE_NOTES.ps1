param(
    [string]$BrigadeId = "",
    [string]$ActorId = "",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [int]$Limit = 10,
    [switch]$ShowContent,
    [switch]$NoMarkRead,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

$notesInbox = Join-Path $MailboxDir "notes\inbox"
$statusDir = Join-Path $MailboxDir "status"
$receiptsPath = Join-Path $statusDir "brigade_note_receipts.json"
New-Item -ItemType Directory -Force -Path $statusDir | Out-Null

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

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $value = $Object.$Name
        if ($null -ne $value) {
            return $value
        }
    }

    return $Default
}

function Resolve-Brigade {
    param(
        [object]$Registry,
        [string]$RequestedBrigadeId,
        [string]$RequestedActorId
    )

    $brigades = @($Registry.brigades)
    if (-not [string]::IsNullOrWhiteSpace($RequestedBrigadeId)) {
        $match = @($brigades | Where-Object { [string]$_.brigade_id -eq $RequestedBrigadeId -or [string]$_.actor_id -eq $RequestedBrigadeId }) | Select-Object -First 1
        if ($null -ne $match) {
            return $match
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedActorId)) {
        $match = @($brigades | Where-Object { [string]$_.actor_id -eq $RequestedActorId -or [string]$_.brigade_id -eq $RequestedActorId }) | Select-Object -First 1
        if ($null -ne $match) {
            return $match
        }
    }

    throw "Pass -BrigadeId or -ActorId for an existing brigade."
}

function Get-Relevance {
    param(
        [object]$Meta,
        [object]$Brigade
    )

    $targetActor = [string](Get-OptionalValue -Object $Meta -Name "target_actor" -Default "")
    $targetBrigadeId = [string](Get-OptionalValue -Object $Meta -Name "target_brigade_id" -Default "")

    if ([string]::IsNullOrWhiteSpace($targetActor) -and [string]::IsNullOrWhiteSpace($targetBrigadeId)) {
        return "BROADCAST"
    }

    if ($targetActor -eq [string]$Brigade.actor_id -or $targetBrigadeId -eq [string]$Brigade.brigade_id) {
        return "TARGETED"
    }

    return "OBSERVE"
}

function Get-ReceiptEntry {
    param(
        [object]$ReceiptsPayload,
        [object]$Brigade
    )

    if ($null -eq $ReceiptsPayload) {
        return $null
    }

    return @($ReceiptsPayload.brigades | Where-Object {
        [string]$_.brigade_id -eq [string]$Brigade.brigade_id -or [string]$_.actor_id -eq [string]$Brigade.actor_id
    }) | Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $notesInbox)) {
    throw "Missing notes inbox: $notesInbox"
}

$registry = Read-JsonFile -Path $RegistryPath
if ($null -eq $registry) {
    throw "Cannot read brigade registry: $RegistryPath"
}

$brigade = Resolve-Brigade -Registry $registry -RequestedBrigadeId $BrigadeId -RequestedActorId $ActorId
$receipts = Read-JsonFile -Path $receiptsPath
$receiptEntry = Get-ReceiptEntry -ReceiptsPayload $receipts -Brigade $brigade
$lastSeenNoteId = [string](Get-OptionalValue -Object $receiptEntry -Name "last_seen_note_id" -Default "")

$allRows = @(
    Get-ChildItem -LiteralPath $notesInbox -Filter *.json -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            $meta = Read-JsonFile -Path $_.FullName
            if ($null -eq $meta) {
                return
            }

            $noteId = [string](Get-OptionalValue -Object $meta -Name "note_id" -Default "")
            $notePath = [string](Get-OptionalValue -Object $meta -Name "note_path" -Default "")
            $relevance = Get-Relevance -Meta $meta -Brigade $brigade
            $isUnread = $true
            if (-not [string]::IsNullOrWhiteSpace($lastSeenNoteId)) {
                $isUnread = ($noteId.CompareTo($lastSeenNoteId) -gt 0)
            }

            [pscustomobject]@{
                note_id = $noteId
                written_at_local = [string](Get-OptionalValue -Object $meta -Name "written_at_local" -Default "")
                author = [string](Get-OptionalValue -Object $meta -Name "author" -Default "")
                title = [string](Get-OptionalValue -Object $meta -Name "title" -Default "")
                relevance = $relevance
                unread = [bool]$isUnread
                request_owner_actor = [string](Get-OptionalValue -Object $meta -Name "request_owner_actor" -Default "")
                request_owner_brigade_id = [string](Get-OptionalValue -Object $meta -Name "request_owner_brigade_id" -Default "")
                target_actor = [string](Get-OptionalValue -Object $meta -Name "target_actor" -Default "")
                target_brigade_id = [string](Get-OptionalValue -Object $meta -Name "target_brigade_id" -Default "")
                report_to_actor = [string](Get-OptionalValue -Object $meta -Name "report_to_actor" -Default "")
                report_to_brigade_id = [string](Get-OptionalValue -Object $meta -Name "report_to_brigade_id" -Default "")
                execution_intent = [string](Get-OptionalValue -Object $meta -Name "execution_intent" -Default "")
                execution_policy = [string](Get-OptionalValue -Object $meta -Name "execution_policy" -Default "")
                note_path = $notePath
            }
        }
)

$selectedRows = @($allRows | Select-Object -First $Limit)
$unreadRows = @($allRows | Where-Object { $_.unread })
$unreadTargetedCount = @($unreadRows | Where-Object { $_.relevance -eq "TARGETED" }).Count
$unreadBroadcastCount = @($unreadRows | Where-Object { $_.relevance -eq "BROADCAST" }).Count
$unreadObserveCount = @($unreadRows | Where-Object { $_.relevance -eq "OBSERVE" }).Count

if (-not $NoMarkRead -and @($allRows).Count -gt 0) {
    if ($null -eq $receipts) {
        $receipts = [ordered]@{
            schema_version = "1.0"
            kind = "brigade_note_receipts"
            brigades = @()
        }
    }

    $brigadeReceipts = @($receipts.brigades)
    $existing = Get-ReceiptEntry -ReceiptsPayload $receipts -Brigade $brigade
    $newEntry = [ordered]@{
        brigade_id = [string]$brigade.brigade_id
        actor_id = [string]$brigade.actor_id
        last_seen_note_id = [string]$allRows[0].note_id
        last_seen_written_at_local = [string]$allRows[0].written_at_local
        last_read_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        unread_before_mark = @($unreadRows).Count
        unread_targeted_before_mark = $unreadTargetedCount
        unread_broadcast_before_mark = $unreadBroadcastCount
        unread_observe_before_mark = $unreadObserveCount
    }

    if ($null -eq $existing) {
        $brigadeReceipts += [pscustomobject]$newEntry
    }
    else {
        $brigadeReceipts = @(
            $brigadeReceipts | ForEach-Object {
                if ([string]$_.brigade_id -eq [string]$brigade.brigade_id -or [string]$_.actor_id -eq [string]$brigade.actor_id) {
                    [pscustomobject]$newEntry
                }
                else {
                    $_
                }
            }
        )
    }

    $receipts = [ordered]@{
        schema_version = "1.0"
        kind = "brigade_note_receipts"
        written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        brigades = @($brigadeReceipts)
    }
    Write-JsonFile -Path $receiptsPath -Payload $receipts
}

$payload = [ordered]@{
    brigade = [ordered]@{
        brigade_id = [string]$brigade.brigade_id
        actor_id = [string]$brigade.actor_id
        chat_name = [string]$brigade.chat_name
    }
    inbox = [ordered]@{
        notes_inbox_path = $notesInbox
        receipts_path = $receiptsPath
        showing_count = @($selectedRows).Count
        total_notes = @($allRows).Count
        unread_total = @($unreadRows).Count
        unread_targeted = $unreadTargetedCount
        unread_broadcast = $unreadBroadcastCount
        unread_observe = $unreadObserveCount
        marked_read = (-not $NoMarkRead)
    }
    notes = @($selectedRows)
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

if ($AsJson) {
    $payload | ConvertTo-Json -Depth 20
    return
}

"BRIGADE NOTE INBOX"
[pscustomobject]$payload.brigade | Format-List

"INBOX STATUS"
[pscustomobject]$payload.inbox | Format-List

"LATEST NOTES"
@($payload.notes) | Select-Object unread, relevance, written_at_local, author, title, request_owner_actor, target_actor, report_to_actor, execution_intent, execution_policy | Format-Table -AutoSize

if ($ShowContent) {
    foreach ($row in @($payload.notes)) {
        if ([string]::IsNullOrWhiteSpace([string]$row.note_path) -or -not (Test-Path -LiteralPath [string]$row.note_path)) {
            continue
        }

        ""
        ("=" * 80)
        "NOTE: $([string]$row.title)"
        "PATH: $([string]$row.note_path)"
        ("-" * 80)
        Get-Content -LiteralPath [string]$row.note_path -Raw -Encoding UTF8
    }
}
