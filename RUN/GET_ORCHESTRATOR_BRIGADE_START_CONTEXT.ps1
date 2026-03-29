param(
    [string]$BrigadeId = "",
    [string]$ActorId = "",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [int]$NotesLimit = 5,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

function Read-JsonFile {
    param([string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        return $null
    }
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

function Get-NoteRows {
    param(
        [string]$NotesInbox,
        [object]$Brigade,
        [int]$Limit
    )

    if (-not (Test-Path -LiteralPath $NotesInbox)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $NotesInbox -Filter *.json -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Limit |
            ForEach-Object {
                $meta = Read-JsonFile -Path $_.FullName
                if ($null -eq $meta) {
                    return
                }

                $targetActor = [string](Get-OptionalValue -Object $meta -Name "target_actor" -Default "")
                $targetBrigadeId = [string](Get-OptionalValue -Object $meta -Name "target_brigade_id" -Default "")
                $relevance = if (
                    [string]::IsNullOrWhiteSpace($targetActor) -and [string]::IsNullOrWhiteSpace($targetBrigadeId)
                ) {
                    "BROADCAST"
                }
                elseif ($targetActor -eq [string]$Brigade.actor_id -or $targetBrigadeId -eq [string]$Brigade.brigade_id) {
                    "TARGETED"
                }
                else {
                    "OBSERVE"
                }

                [pscustomobject]@{
                    written_at_local = [string](Get-OptionalValue -Object $meta -Name "written_at_local" -Default "")
                    author = [string](Get-OptionalValue -Object $meta -Name "author" -Default "")
                    title = [string](Get-OptionalValue -Object $meta -Name "title" -Default "")
                    relevance = $relevance
                    target_actor = $targetActor
                    target_brigade_id = $targetBrigadeId
                    execution_intent = [string](Get-OptionalValue -Object $meta -Name "execution_intent" -Default "")
                    execution_policy = [string](Get-OptionalValue -Object $meta -Name "execution_policy" -Default "")
                    note_path = [string](Get-OptionalValue -Object $meta -Name "note_path" -Default "")
                }
            }
    )
}

function Get-BrigadeRecommendation {
    param(
        [object]$BrigadeRow,
        [object[]]$PendingRows,
        [object[]]$ActiveRows,
        [object[]]$TargetedNotes
    )

    $pendingCount = @($PendingRows | Where-Object { $null -ne $_ }).Count
    $activeCount = @($ActiveRows | Where-Object { $null -ne $_ }).Count
    $targetedCount = @($TargetedNotes | Where-Object { $null -ne $_ }).Count

    if ($targetedCount -gt 0 -and $pendingCount -gt 0 -and $activeCount -eq 0) {
        return "Przeczytaj targetowane note, wez claim z TaskId i podnies task do ACTIVE."
    }

    if ($pendingCount -gt 0 -and $activeCount -eq 0) {
        return "Masz pending taski; wystartuj claim albo activity z TaskId po safety review."
    }

    if ($activeCount -gt 0) {
        return "Lane jest aktywny; utrzymuj heartbeat i raportuj wynik przez RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1."
    }

    if ($targetedCount -gt 0) {
        return "Sa nowe note targetowane; wykonaj review i zdecyduj: wykonanie, blokada albo handoff."
    }

    if ($null -ne $BrigadeRow -and [int](Get-OptionalValue -Object $BrigadeRow -Name "blocked" -Default 0) -gt 0) {
        return "Lane ma blokady; opisz je i wykonaj handoff albo note eskalacyjny."
    }

    return "Czytaj nowe note i czekaj na jawne przypisanie lub bezpieczny task w lane."
}

function New-CommandExamples {
    param(
        [object]$Brigade,
        [object[]]$PendingRows
    )

    $claimExample = ""
    $resultExample = 'pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 -TaskId <task_id> -Actor {0} -Outcome STATUS -Summary "Krotki status brygady." -NextAction "Co dalej."' -f [string]$Brigade.actor_id
    $completeExample = 'pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -TaskId <task_id> -Actor {0} -Outcome COMPLETED -Notes "Zadanie domkniete." -PublishResultNote -ResultSummary "Wynik przekazany wszystkim brygadom."' -f [string]$Brigade.actor_id

    $firstPending = @($PendingRows | Select-Object -First 1)
    if (@($firstPending).Count -gt 0) {
        $taskId = [string]$firstPending[0].task_id
        $title = [string]$firstPending[0].title
        $claimExample = 'pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\CLAIM_ORCHESTRATOR_WORK.ps1 -Actor {0} -TaskId {1} -WorkTitle "{2}" -Notes "Start po review bezpieczenstwa."' -f [string]$Brigade.actor_id, $taskId, $title.Replace('"', "'")
    }

    return [ordered]@{
        read_notes = 'pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId {0} -Limit 10 -ShowContent' -f [string]$Brigade.brigade_id
        list_notes = 'pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_NOTES.ps1 -Limit 10'
        claim_work = $claimExample
        write_result = $resultExample
        complete_task = $completeExample
    }
}

$registry = Read-JsonFile -Path $RegistryPath
if ($null -eq $registry) {
    throw "Cannot read brigade registry: $RegistryPath"
}

$brigade = Resolve-Brigade -Registry $registry -RequestedBrigadeId $BrigadeId -RequestedActorId $ActorId

$taskboardScriptPath = Join-Path $PSScriptRoot "GET_ORCHESTRATOR_TASKBOARD.ps1"
if (-not (Test-Path -LiteralPath $taskboardScriptPath)) {
    throw "Missing taskboard script: $taskboardScriptPath"
}

& $taskboardScriptPath -MailboxDir $MailboxDir -RegistryPath $RegistryPath -ByBrigade | Out-Null

$taskboardPath = Join-Path $MailboxDir "status\taskboard_latest.json"
$taskboard = if (Test-Path -LiteralPath $taskboardPath) { Read-JsonFile -Path $taskboardPath } else { $null }

$brigadeRows = @()
$pendingRows = @()
$activeRows = @()
$blockedRows = @()
if ($null -ne $taskboard) {
    $brigadeRows = @(Get-OptionalValue -Object $taskboard -Name "brigade_rows" -Default @())
    $pendingRows = @(@(Get-OptionalValue -Object $taskboard -Name "pending_rows" -Default @()) | Where-Object { [string]$_.assigned_to -eq [string]$brigade.actor_id })
    $activeRows = @(@(Get-OptionalValue -Object $taskboard -Name "active_rows" -Default @()) | Where-Object { [string]$_.assigned_to -eq [string]$brigade.actor_id })
    $blockedRows = @(@(Get-OptionalValue -Object $taskboard -Name "blocked_rows" -Default @()) | Where-Object { [string]$_.assigned_to -eq [string]$brigade.actor_id })
}

$brigadeRow = @($brigadeRows | Where-Object {
    [string]$_.brigade_id -eq [string]$brigade.brigade_id -or [string]$_.actor_id -eq [string]$brigade.actor_id
}) | Select-Object -First 1

$notesInbox = Join-Path $MailboxDir "notes\inbox"
$noteRows = @(Get-NoteRows -NotesInbox $notesInbox -Brigade $brigade -Limit $NotesLimit)
$targetedNotes = @($noteRows | Where-Object { [string]$_.relevance -eq "TARGETED" })

$policy = Get-OptionalValue -Object $registry -Name "message_handling_policy" -Default $null
$startupProtocol = Get-OptionalValue -Object $registry -Name "startup_protocol" -Default $null
$commandExamples = New-CommandExamples -Brigade $brigade -PendingRows $pendingRows

$payload = [ordered]@{
    brigade = [ordered]@{
        brigade_id = [string]$brigade.brigade_id
        actor_id = [string]$brigade.actor_id
        chat_name = [string]$brigade.chat_name
        primary_focus = [string]$brigade.primary_focus
        startup_priority = [string]$brigade.startup_priority
    }
    lane_status = $brigadeRow
    pending_rows = @($pendingRows)
    active_rows = @($activeRows)
    blocked_rows = @($blockedRows)
    latest_notes = @($noteRows)
    recommendation = Get-BrigadeRecommendation -BrigadeRow $brigadeRow -PendingRows $pendingRows -ActiveRows $activeRows -TargetedNotes $targetedNotes
    message_policy = [ordered]@{
        all_brigades_read_every_new_note = [bool](Get-OptionalValue -Object $policy -Name "all_brigades_read_every_new_note" -Default $false)
        default_execution_policy = [string](Get-OptionalValue -Object $policy -Name "default_execution_policy" -Default "")
        default_non_target_policy = [string](Get-OptionalValue -Object $policy -Name "default_non_target_policy" -Default "")
        delegation_requires_handoff = [bool](Get-OptionalValue -Object $policy -Name "delegation_requires_handoff" -Default $false)
        delegation_allowed_for_targeted_owner_only = [bool](Get-OptionalValue -Object $policy -Name "delegation_allowed_for_targeted_owner_only" -Default $false)
        completion_report_required = [bool](Get-OptionalValue -Object $policy -Name "completion_report_required" -Default $false)
        completion_report_visibility = [string](Get-OptionalValue -Object $policy -Name "completion_report_visibility" -Default "")
        completion_report_audience = [string](Get-OptionalValue -Object $policy -Name "completion_report_audience" -Default "")
        handoff_rule = [string](Get-OptionalValue -Object $policy -Name "handoff_rule" -Default "")
        completion_report_rule = [string](Get-OptionalValue -Object $policy -Name "completion_report_rule" -Default "")
    }
    startup_protocol = [ordered]@{
        enabled = [bool](Get-OptionalValue -Object $startupProtocol -Name "enabled" -Default $false)
        start_context_script = [string](Get-OptionalValue -Object $startupProtocol -Name "start_context_script" -Default "")
        required_steps = @(Get-OptionalValue -Object $startupProtocol -Name "required_steps" -Default @())
    }
    mailbox_paths = [ordered]@{
        notes_inbox = Join-Path $MailboxDir "notes\inbox"
        task_pending = Join-Path $MailboxDir "coordination\tasks\pending"
        task_active = Join-Path $MailboxDir "coordination\tasks\active"
        task_blocked = Join-Path $MailboxDir "coordination\tasks\blocked"
        task_done = Join-Path $MailboxDir "coordination\tasks\done"
        claim_active = Join-Path $MailboxDir "coordination\claims\active"
        activity = Join-Path $MailboxDir "coordination\activity"
        note_receipts = Join-Path $MailboxDir "status\brigade_note_receipts.json"
    }
    command_examples = $commandExamples
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

if ($AsJson) {
    $payload | ConvertTo-Json -Depth 20
    return
}

"BRIGADE START CONTEXT"
[pscustomobject]$payload.brigade | Format-List

if ($null -ne $payload.lane_status) {
    "LANE STATUS"
    [pscustomobject]$payload.lane_status | Format-List
}

"PENDING TASKS"
@($payload.pending_rows) | Select-Object state, priority, title, task_id, last_activity_at_local | Format-Table -AutoSize
""
"ACTIVE TASKS"
@($payload.active_rows) | Select-Object state, priority, title, task_id, last_activity_at_local | Format-Table -AutoSize
""
"BLOCKED TASKS"
@($payload.blocked_rows) | Select-Object state, priority, title, task_id, last_activity_at_local | Format-Table -AutoSize
""
"LATEST NOTES"
@($payload.latest_notes) | Select-Object written_at_local, author, relevance, title, execution_intent, execution_policy | Format-Table -AutoSize
""
"MESSAGE POLICY"
[pscustomobject]$payload.message_policy | Format-List
""
"STARTUP PROTOCOL"
[pscustomobject]@{
    enabled = $payload.startup_protocol.enabled
    start_context_script = $payload.startup_protocol.start_context_script
} | Format-List
@($payload.startup_protocol.required_steps) | ForEach-Object { "- {0}" -f [string]$_ }
""
"MAILBOX PATHS"
[pscustomobject]$payload.mailbox_paths | Format-List
""
"COMMAND EXAMPLES"
[pscustomobject]$payload.command_examples | Format-List
""
"RECOMMENDATION"
$payload.recommendation
