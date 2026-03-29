param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [string]$OutputRoot = "",
    [int]$Limit = 10,
    [switch]$PublishToNotes,
    [string]$NoteTitlePrefix = "Doreczenie informacji z mostu",
    [string]$NoteAuthor = "codex",
    [string]$NoteSourceRole = "local_agent",
    [string[]]$NoteTags = @("brigady", "most", "delivery", "auto")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $ProjectRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50
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

    $Payload | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding UTF8
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

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Get-BrigadeReceiptEntry {
    param(
        [object]$ReceiptsPayload,
        [string]$BrigadeId,
        [string]$ActorId
    )

    if ($null -eq $ReceiptsPayload) {
        return $null
    }

    return @($ReceiptsPayload.brigades | Where-Object {
        [string](Get-OptionalValue -Object $_ -Name "brigade_id" -Default "") -eq $BrigadeId -or
        [string](Get-OptionalValue -Object $_ -Name "actor_id" -Default "") -eq $ActorId
    }) | Select-Object -First 1
}

function Get-LatestNoteMeta {
    param([string]$NotesInbox)

    if (-not (Test-Path -LiteralPath $NotesInbox)) {
        return $null
    }

    foreach ($item in Get-ChildItem -LiteralPath $NotesInbox -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) {
        $meta = Read-JsonFile -Path $item.FullName
        if ($null -eq $meta) {
            continue
        }

        $tags = @((Get-OptionalValue -Object $meta -Name "tags" -Default @()))
        if (@($tags | Where-Object { [string]$_ -eq "auto" }).Count -gt 0) {
            continue
        }

        return $meta
    }

    return $null
}

function New-BridgeDeliveryNoteText {
    param(
        [string]$GeneratedAtLocal,
        [string]$OverallVerdict,
        [object]$Summary,
        [object]$LatestNote,
        [object[]]$BrigadeRows,
        [string]$MarkdownReportPath
    )

    $noteLines = New-Object System.Collections.Generic.List[string]
    $noteLines.Add(("Doreczenie informacji z mostu {0}" -f $GeneratedAtLocal))
    $noteLines.Add("")
    $noteLines.Add(("Werdykt: {0}" -f $OverallVerdict))
    $noteLines.Add(("Brygady zsynchronizowane do latest note: {0}/{1}" -f $Summary.brigades_synced_to_latest, $Summary.total_brigades))
    $noteLines.Add(("Brygady z receipt: {0}/{1}" -f $Summary.brigades_with_receipt, $Summary.total_brigades))
    $noteLines.Add(("Unread przed sync: {0}" -f $Summary.total_unread_before_sync))
    $noteLines.Add(("Unread targeted przed sync: {0}" -f $Summary.total_targeted_unread_before_sync))
    $noteLines.Add("")
    $noteLines.Add(("Latest note: {0}" -f [string](Get-OptionalValue -Object $LatestNote -Name "title" -Default "")))
    $noteLines.Add(("Latest note id: {0}" -f [string](Get-OptionalValue -Object $LatestNote -Name "note_id" -Default "")))

    $lagging = @(
        $BrigadeRows |
            Where-Object { [string](Get-OptionalValue -Object (Get-OptionalValue -Object $_ -Name "note_delivery" -Default $null) -Name "state" -Default "") -ne "SYNCED_TO_LATEST" } |
            ForEach-Object { [string](Get-OptionalValue -Object $_ -Name "brigade_id" -Default "") } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($lagging.Count -gt 0) {
        $noteLines.Add("")
        $noteLines.Add(("Brygady wymagajace uwagi: {0}" -f ($lagging -join ", ")))
    }

    $noteLines.Add("")
    $noteLines.Add(("Pelny raport: {0}" -f $MarkdownReportPath))
    return ($noteLines -join [Environment]::NewLine)
}

$registry = Read-JsonFile -Path $RegistryPath
if ($null -eq $registry) {
    throw "Cannot read brigade registry: $RegistryPath"
}

$readNotesScriptPath = Join-Path $ProjectRoot "RUN\READ_ORCHESTRATOR_BRIGADE_NOTES.ps1"
$writeNoteScriptPath = Join-Path $ProjectRoot "RUN\WRITE_ORCHESTRATOR_NOTE.ps1"
$notesInbox = Join-Path $MailboxDir "notes\inbox"
$receiptsPath = Join-Path $MailboxDir "status\brigade_note_receipts.json"

if (-not (Test-Path -LiteralPath $readNotesScriptPath)) {
    throw "Missing brigade note sync script: $readNotesScriptPath"
}

if ($PublishToNotes -and -not (Test-Path -LiteralPath $writeNoteScriptPath)) {
    throw "Missing note writer script: $writeNoteScriptPath"
}

$syncSeedRows = @()
foreach ($brigade in @($registry.brigades)) {
    $syncPayload = & $readNotesScriptPath -BrigadeId ([string]$brigade.brigade_id) -MailboxDir $MailboxDir -RegistryPath $RegistryPath -Limit $Limit -AsJson | ConvertFrom-Json -Depth 30
    $syncSeedRows += [pscustomobject]@{
        brigade_id = [string](Get-OptionalValue -Object $syncPayload.brigade -Name "brigade_id" -Default "")
        actor_id = [string](Get-OptionalValue -Object $syncPayload.brigade -Name "actor_id" -Default "")
        chat_name = [string](Get-OptionalValue -Object $syncPayload.brigade -Name "chat_name" -Default "")
        total_notes = [int](Get-OptionalValue -Object $syncPayload.inbox -Name "total_notes" -Default 0)
        showing_count = [int](Get-OptionalValue -Object $syncPayload.inbox -Name "showing_count" -Default 0)
        unread_before_sync = [int](Get-OptionalValue -Object $syncPayload.inbox -Name "unread_total" -Default 0)
        unread_targeted_before_sync = [int](Get-OptionalValue -Object $syncPayload.inbox -Name "unread_targeted" -Default 0)
        unread_broadcast_before_sync = [int](Get-OptionalValue -Object $syncPayload.inbox -Name "unread_broadcast" -Default 0)
        unread_observe_before_sync = [int](Get-OptionalValue -Object $syncPayload.inbox -Name "unread_observe" -Default 0)
        marked_read = [bool](Get-OptionalValue -Object $syncPayload.inbox -Name "marked_read" -Default $false)
    }
}

$receipts = Read-JsonFile -Path $receiptsPath
$latestNote = Get-LatestNoteMeta -NotesInbox $notesInbox
$latestNoteId = [string](Get-OptionalValue -Object $latestNote -Name "note_id" -Default "")
$latestNoteTitle = [string](Get-OptionalValue -Object $latestNote -Name "title" -Default "")
$totalNotesInInbox = @(Get-ChildItem -LiteralPath $notesInbox -Filter *.json -ErrorAction SilentlyContinue).Count

$brigadeRows = @()
foreach ($row in $syncSeedRows) {
    $receipt = Get-BrigadeReceiptEntry -ReceiptsPayload $receipts -BrigadeId ([string]$row.brigade_id) -ActorId ([string]$row.actor_id)
    $lastSeenNoteId = [string](Get-OptionalValue -Object $receipt -Name "last_seen_note_id" -Default "")
    $deliveryState = if ($totalNotesInInbox -le 0) {
        "NO_NOTES"
    }
    elseif ([string]::IsNullOrWhiteSpace($lastSeenNoteId)) {
        "NO_RECEIPT"
    }
    elseif ($lastSeenNoteId.CompareTo($latestNoteId) -ge 0) {
        "SYNCED_TO_LATEST"
    }
    else {
        "LAGGING"
    }

    $brigadeRows += [pscustomobject]@{
        brigade_id = [string]$row.brigade_id
        actor_id = [string]$row.actor_id
        chat_name = [string]$row.chat_name
        unread_before_sync = [int]$row.unread_before_sync
        unread_targeted_before_sync = [int]$row.unread_targeted_before_sync
        unread_broadcast_before_sync = [int]$row.unread_broadcast_before_sync
        unread_observe_before_sync = [int]$row.unread_observe_before_sync
        note_delivery = [ordered]@{
            state = $deliveryState
            latest_global_note_id = $latestNoteId
            latest_global_note_title = $latestNoteTitle
            last_seen_note_id = $lastSeenNoteId
            last_seen_written_at_local = [string](Get-OptionalValue -Object $receipt -Name "last_seen_written_at_local" -Default "")
            last_read_at_local = [string](Get-OptionalValue -Object $receipt -Name "last_read_at_local" -Default "")
            marked_read = [bool]$row.marked_read
        }
    }
}

$summary = [ordered]@{
    total_brigades = @($brigadeRows).Count
    total_notes_in_inbox = $totalNotesInInbox
    latest_note_id = $latestNoteId
    latest_note_title = $latestNoteTitle
    brigades_with_receipt = @($brigadeRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.note_delivery.last_seen_note_id) }).Count
    brigades_synced_to_latest = @($brigadeRows | Where-Object { $_.note_delivery.state -eq "SYNCED_TO_LATEST" -or $_.note_delivery.state -eq "NO_NOTES" }).Count
    brigades_with_unread_before_sync = @($brigadeRows | Where-Object { $_.unread_before_sync -gt 0 }).Count
    brigades_with_targeted_unread_before_sync = @($brigadeRows | Where-Object { $_.unread_targeted_before_sync -gt 0 }).Count
    total_unread_before_sync = @($brigadeRows | Measure-Object unread_before_sync -Sum).Sum
    total_targeted_unread_before_sync = @($brigadeRows | Measure-Object unread_targeted_before_sync -Sum).Sum
}

$overallVerdict = "DELIVERY_GAPS"
if ($summary.total_notes_in_inbox -le 0) {
    $overallVerdict = "NO_NOTES"
}
elseif ($summary.brigades_synced_to_latest -eq $summary.total_brigades) {
    $overallVerdict = "DELIVERY_CONFIRMED"
}
elseif ($summary.brigades_with_receipt -gt 0) {
    $overallVerdict = "PARTIAL_SYNC"
}

$payload = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    overall_verdict = $overallVerdict
    summary = $summary
    brigades = @($brigadeRows)
    sources = [ordered]@{
        mailbox_dir = $MailboxDir
        notes_inbox_path = $notesInbox
        receipts_path = $receiptsPath
    }
}

$jsonPath = Join-Path $OutputRoot "bridge_note_delivery_latest.json"
$mdPath = Join-Path $OutputRoot "bridge_note_delivery_latest.md"
Write-JsonFile -Path $jsonPath -Payload $payload

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# DORECZENIE INFORMACJI Z MOSTU")
$lines.Add("")
$lines.Add(("Wygenerowano: {0}" -f $payload.generated_at_local))
$lines.Add(("Werdykt: {0}" -f $payload.overall_verdict))
$lines.Add("")
$lines.Add("## Podsumowanie")
$lines.Add("")
$lines.Add(("- brygady: {0}" -f $summary.total_brigades))
$lines.Add(("- noty w inboxie: {0}" -f $summary.total_notes_in_inbox))
$lines.Add(("- latest note id: {0}" -f $summary.latest_note_id))
$lines.Add(("- latest note title: {0}" -f $summary.latest_note_title))
$lines.Add(("- brygady z receipt: {0}/{1}" -f $summary.brigades_with_receipt, $summary.total_brigades))
$lines.Add(("- brygady synced_to_latest: {0}/{1}" -f $summary.brigades_synced_to_latest, $summary.total_brigades))
$lines.Add(("- unread przed sync: {0}" -f $summary.total_unread_before_sync))
$lines.Add(("- unread targeted przed sync: {0}" -f $summary.total_targeted_unread_before_sync))
$lines.Add("")
$lines.Add("## Brygady")
$lines.Add("")
$lines.Add("| brygada | state | unread | targeted | broadcast | observe | last_read | last_seen_note_id |")
$lines.Add("| --- | --- | ---: | ---: | ---: | ---: | --- | --- |")

foreach ($row in $brigadeRows) {
    $lines.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |" -f
        [string]$row.brigade_id,
        [string]$row.note_delivery.state,
        [int]$row.unread_before_sync,
        [int]$row.unread_targeted_before_sync,
        [int]$row.unread_broadcast_before_sync,
        [int]$row.unread_observe_before_sync,
        [string]$row.note_delivery.last_read_at_local,
        [string]$row.note_delivery.last_seen_note_id
    ))
}

$lines.Add("")
$lines.Add("## Zrodla")
$lines.Add("")
$lines.Add(("- notes inbox: {0}" -f $notesInbox))
$lines.Add(("- receipts: {0}" -f $receiptsPath))
Set-Content -LiteralPath $mdPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8

$publishedNotePath = ""
$publishedNoteTitle = ""
if ($PublishToNotes) {
    $publishedNoteTitle = "{0} {1}" -f $NoteTitlePrefix, ((Get-Date).ToString("yyyyMMdd_HHmmss"))
    $noteText = New-BridgeDeliveryNoteText -GeneratedAtLocal $payload.generated_at_local -OverallVerdict $payload.overall_verdict -Summary $payload.summary -LatestNote $latestNote -BrigadeRows $payload.brigades -MarkdownReportPath $mdPath
    $publishedNotePath = (& $writeNoteScriptPath -Title $publishedNoteTitle -Text $noteText -MailboxDir $MailboxDir -Author $NoteAuthor -SourceRole $NoteSourceRole -Visibility "ALL_BRIGADES_READ" -ExecutionIntent "STATUS" -ExecutionPolicy "BROADCAST_READ_ONLY" -NonTargetPolicy "READ_ONLY" -RequiresSafetyReview $false -Tags $NoteTags | Select-Object -Last 1)
    if (-not [string]::IsNullOrWhiteSpace($publishedNotePath)) {
        $payload["published_note_title"] = $publishedNoteTitle
        $payload["published_note_path"] = [string]$publishedNotePath
        Write-JsonFile -Path $jsonPath -Payload $payload
    }
}

[pscustomobject]@{
    generated_at_local = $payload.generated_at_local
    overall_verdict = $payload.overall_verdict
    receipts_path = $receiptsPath
    markdown_report = $mdPath
    json_report = $jsonPath
    published_note_title = $publishedNoteTitle
    published_note_path = $publishedNotePath
    brigades_synced_to_latest = $summary.brigades_synced_to_latest
    total_brigades = $summary.total_brigades
} | Format-List