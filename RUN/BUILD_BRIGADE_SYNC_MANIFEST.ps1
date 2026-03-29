param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [string]$OutputRoot = "",
    [switch]$PublishToNotes,
    [string]$NoteTitlePrefix = "Manifest spiecia brygad",
    [string]$NoteAuthor = "codex",
    [string]$NoteSourceRole = "local_agent",
    [string[]]$NoteTags = @("brigady", "sync_manifest", "status")
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

function Find-TaskJson {
    param(
        [string]$MailboxRoot,
        [string]$TaskId
    )

    foreach ($stateDir in @("active", "pending", "blocked", "done")) {
        $candidate = Join-Path $MailboxRoot ("coordination\tasks\{0}\{1}.json" -f $stateDir, $TaskId)
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-LatestNoteMetaForAuthor {
    param(
        [string]$NotesInbox,
        [string]$Author
    )

    if (-not (Test-Path -LiteralPath $NotesInbox)) {
        return $null
    }

    foreach ($item in Get-ChildItem -LiteralPath $NotesInbox -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) {
        $meta = Read-JsonFile -Path $item.FullName
        if ($null -eq $meta) {
            continue
        }

        if ([string](Get-OptionalValue -Object $meta -Name "author" -Default "") -eq $Author) {
            return $meta
        }
    }

    return $null
}

function Get-LatestNoteMetaByTitleLike {
    param(
        [string]$NotesInbox,
        [string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $NotesInbox)) {
        return $null
    }

    foreach ($item in Get-ChildItem -LiteralPath $NotesInbox -Filter *.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) {
        $meta = Read-JsonFile -Path $item.FullName
        if ($null -eq $meta) {
            continue
        }

        $title = [string](Get-OptionalValue -Object $meta -Name "title" -Default "")
        if ($title -like $Pattern) {
            return $meta
        }
    }

    return $null
}

function Get-LatestDeliverableNoteMeta {
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

function Get-PromptRelativePath {
    param([string]$BrigadeId)

    switch ($BrigadeId) {
        "ml_migracja_mt5" { return ".github/prompts/wejdz-brygada-ml-migracja-mt5.prompt.md" }
        "audyt_cleanup" { return ".github/prompts/wejdz-brygada-audyt-cleanup.prompt.md" }
        "wdrozenia_mt5" { return ".github/prompts/wejdz-brygada-wdrozenia-mt5.prompt.md" }
        "rozwoj_kodu" { return ".github/prompts/wejdz-brygada-rozwoj-kodu.prompt.md" }
        "architektura_innowacje" { return ".github/prompts/wejdz-brygada-architektura-innowacje.prompt.md" }
        "nadzor_uczenia_rolloutu" { return ".github/prompts/wejdz-brygada-nadzor-uczenia-gonogo.prompt.md" }
        default { return "" }
    }
}

function Get-BrigadeTaskRow {
    param(
        [object]$Taskboard,
        [string]$ActorId
    )

    foreach ($bucket in @("active_rows", "pending_rows", "blocked_rows", "done_rows")) {
        foreach ($row in @(Get-OptionalValue -Object $Taskboard -Name $bucket -Default @())) {
            if ([string](Get-OptionalValue -Object $row -Name "assigned_to" -Default "") -eq $ActorId) {
                return $row
            }
        }
    }

    return $null
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

$taskboardScriptPath = Join-Path $ProjectRoot "RUN\GET_ORCHESTRATOR_TASKBOARD.ps1"
$writeNoteScriptPath = Join-Path $ProjectRoot "RUN\WRITE_ORCHESTRATOR_NOTE.ps1"
if (Test-Path -LiteralPath $taskboardScriptPath) {
    & $taskboardScriptPath -MailboxDir $MailboxDir -RegistryPath $RegistryPath -ByBrigade | Out-Null
}

$workboardScriptPath = Join-Path $ProjectRoot "RUN\GET_ORCHESTRATOR_WORKBOARD.ps1"
if (Test-Path -LiteralPath $workboardScriptPath) {
    & $workboardScriptPath -MailboxDir $MailboxDir | Out-Null
}

$registry = Read-JsonFile -Path $RegistryPath
if ($null -eq $registry) {
    throw "Cannot read brigade registry: $RegistryPath"
}

$taskboardPath = Join-Path $MailboxDir "status\taskboard_latest.json"
$workboardPath = Join-Path $MailboxDir "status\workboard_latest.json"
$taskboard = Read-JsonFile -Path $taskboardPath
$workboard = Read-JsonFile -Path $workboardPath
if ($null -eq $taskboard) {
    throw "Cannot read taskboard status: $taskboardPath"
}
if ($PublishToNotes -and -not (Test-Path -LiteralPath $writeNoteScriptPath)) {
    throw "Missing note script: $writeNoteScriptPath"
}

$notesInbox = Join-Path $MailboxDir "notes\inbox"
$receiptsPath = Join-Path $MailboxDir "status\brigade_note_receipts.json"
$receipts = Read-JsonFile -Path $receiptsPath
$startContextScript = "RUN/GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1"
$startContextScriptExists = Test-Path -LiteralPath (Join-Path $ProjectRoot $startContextScript.Replace('/', '\\'))
$workspaceInstructionsPath = Join-Path $ProjectRoot ".github\copilot-instructions.md"
$workspaceInstructionsExists = Test-Path -LiteralPath $workspaceInstructionsPath

$latestGlobalNote = Get-LatestDeliverableNoteMeta -NotesInbox $notesInbox
$latestGlobalNoteId = [string](Get-OptionalValue -Object $latestGlobalNote -Name "note_id" -Default "")
$latestGlobalNoteTitle = [string](Get-OptionalValue -Object $latestGlobalNote -Name "title" -Default "")

$contractNote = Get-LatestNoteMetaByTitleLike -NotesInbox $notesInbox -Pattern "Kontrakt odczytu i wykonania brygad*"
$workflowNote = Get-LatestNoteMetaByTitleLike -NotesInbox $notesInbox -Pattern "Zasada_wspolnego_czytania_notatek*"
$planNote = Get-LatestNoteMetaByTitleLike -NotesInbox $notesInbox -Pattern "Plan wdrozenia MT5 truth i broker-mirror*"

$policy = Get-OptionalValue -Object $registry -Name "message_handling_policy" -Default $null
$startupProtocol = Get-OptionalValue -Object $registry -Name "startup_protocol" -Default $null
$informationAdminActor = [string](Get-OptionalValue -Object $policy -Name "information_admin_actor_id" -Default "")
$informationAdminBrigadeId = [string](Get-OptionalValue -Object $policy -Name "information_admin_brigade_id" -Default "")
$processingOwnerDeclared = [bool](Get-OptionalValue -Object $policy -Name "processing_owner_must_be_declared" -Default $false)
$reportToDeclared = [bool](Get-OptionalValue -Object $policy -Name "report_to_must_be_declared" -Default $false)

$brigadeRows = @()
foreach ($brigade in @($registry.brigades)) {
    $brigadeId = [string](Get-OptionalValue -Object $brigade -Name "brigade_id" -Default "")
    $actorId = [string](Get-OptionalValue -Object $brigade -Name "actor_id" -Default "")
    $taskRow = Get-BrigadeTaskRow -Taskboard $taskboard -ActorId $actorId
    $taskId = [string](Get-OptionalValue -Object $taskRow -Name "task_id" -Default "")
    $taskPayload = if ([string]::IsNullOrWhiteSpace($taskId)) { $null } else { Read-JsonFile -Path (Find-TaskJson -MailboxRoot $MailboxDir -TaskId $taskId) }
    $latestNoteMeta = Get-LatestNoteMetaForAuthor -NotesInbox $notesInbox -Author $actorId
    $receiptRow = Get-BrigadeReceiptEntry -ReceiptsPayload $receipts -BrigadeId $brigadeId -ActorId $actorId
    $claimRow = @(@(Get-OptionalValue -Object $workboard -Name "active_rows" -Default @()) | Where-Object {
        [string](Get-OptionalValue -Object $_ -Name "actor" -Default "") -eq $actorId
    }) | Select-Object -First 1

    $promptRelativePath = Get-PromptRelativePath -BrigadeId $brigadeId
    $promptFullPath = if ([string]::IsNullOrWhiteSpace($promptRelativePath)) { "" } else { Join-Path $ProjectRoot $promptRelativePath.Replace('/', '\\') }
    $promptExists = if ([string]::IsNullOrWhiteSpace($promptFullPath)) { $false } else { Test-Path -LiteralPath $promptFullPath }

    $contractReached = 
        [bool](Get-OptionalValue -Object $policy -Name "all_brigades_read_every_new_note" -Default $false) -and
        ([string](Get-OptionalValue -Object $policy -Name "default_execution_policy" -Default "") -eq "TARGET_ONLY_AFTER_REVIEW") -and
        $processingOwnerDeclared -and
        $reportToDeclared -and
        -not [string]::IsNullOrWhiteSpace($informationAdminActor) -and
        -not [string]::IsNullOrWhiteSpace($informationAdminBrigadeId) -and
        [bool](Get-OptionalValue -Object $startupProtocol -Name "enabled" -Default $false) -and
        $startContextScriptExists -and
        $workspaceInstructionsExists -and
        $promptExists

    $latestNoteTitle = [string](Get-OptionalValue -Object $latestNoteMeta -Name "title" -Default "")
    $latestNotePath = [string](Get-OptionalValue -Object $latestNoteMeta -Name "note_path" -Default "")
    $latestNoteAt = [string](Get-OptionalValue -Object $latestNoteMeta -Name "written_at_local" -Default "")
    $lastResultOutcome = [string](Get-OptionalValue -Object $taskPayload -Name "last_result_outcome" -Default "")
    $lastResultNotePath = [string](Get-OptionalValue -Object $taskPayload -Name "last_result_note_path" -Default "")
    $lastResultReportedAt = [string](Get-OptionalValue -Object $taskPayload -Name "last_result_reported_at_local" -Default "")
    $taskStatus = [string](Get-OptionalValue -Object $taskRow -Name "state" -Default ([string](Get-OptionalValue -Object $taskPayload -Name "status" -Default "")))
    $wiringState = if ($contractReached -and $taskStatus -eq "ACTIVE" -and -not [string]::IsNullOrWhiteSpace($latestNotePath)) { "LIVE" } elseif ($contractReached) { "PARTIAL" } else { "MISSING" }
    $lastSeenNoteId = [string](Get-OptionalValue -Object $receiptRow -Name "last_seen_note_id" -Default "")
    $noteDeliveryState = if ([string]::IsNullOrWhiteSpace($latestGlobalNoteId)) {
        "NO_NOTES"
    }
    elseif ([string]::IsNullOrWhiteSpace($lastSeenNoteId)) {
        "NO_RECEIPT"
    }
    elseif ($lastSeenNoteId.CompareTo($latestGlobalNoteId) -ge 0) {
        "SYNCED_TO_LATEST"
    }
    else {
        "LAGGING"
    }

    $brigadeRows += [ordered]@{
        brigade_id = $brigadeId
        actor_id = $actorId
        chat_name = [string](Get-OptionalValue -Object $brigade -Name "chat_name" -Default "")
        startup_priority = [string](Get-OptionalValue -Object $brigade -Name "startup_priority" -Default "")
        contract_reached = $contractReached
        wiring_state = $wiringState
        prompt_path = $promptRelativePath
        start_context_script = $startContextScript
        current_task = [ordered]@{
            task_id = $taskId
            title = [string](Get-OptionalValue -Object $taskRow -Name "title" -Default "")
            status = $taskStatus
            last_activity_title = [string](Get-OptionalValue -Object $taskPayload -Name "last_activity_title" -Default "")
            last_activity_at_local = [string](Get-OptionalValue -Object $taskPayload -Name "last_activity_at_local" -Default ([string](Get-OptionalValue -Object $taskRow -Name "last_activity_at_local" -Default "")))
            report_path = [string](Get-OptionalValue -Object $taskPayload -Name "report_path" -Default ([string](Get-OptionalValue -Object $taskRow -Name "report_path" -Default "")))
        }
        latest_public_note = [ordered]@{
            title = $latestNoteTitle
            note_path = $latestNotePath
            written_at_local = $latestNoteAt
        }
        note_delivery = [ordered]@{
            state = $noteDeliveryState
            latest_global_note_id = $latestGlobalNoteId
            latest_global_note_title = $latestGlobalNoteTitle
            last_seen_note_id = $lastSeenNoteId
            last_seen_written_at_local = [string](Get-OptionalValue -Object $receiptRow -Name "last_seen_written_at_local" -Default "")
            last_read_at_local = [string](Get-OptionalValue -Object $receiptRow -Name "last_read_at_local" -Default "")
        }
        last_result = [ordered]@{
            outcome = $lastResultOutcome
            note_path = $lastResultNotePath
            reported_at_local = $lastResultReportedAt
        }
        active_claim = [ordered]@{
            claim_id = [string](Get-OptionalValue -Object $claimRow -Name "claim_id" -Default "")
            work_title = [string](Get-OptionalValue -Object $claimRow -Name "work_title" -Default "")
            report_path = [string](Get-OptionalValue -Object $claimRow -Name "report_path" -Default "")
            expires_at_local = [string](Get-OptionalValue -Object $claimRow -Name "expires_at_local" -Default "")
        }
    }
}

$summary = [ordered]@{
    total_brigades = @($brigadeRows).Count
    contract_reached_count = @($brigadeRows | Where-Object { $_.contract_reached }).Count
    live_lane_count = @($brigadeRows | Where-Object { $_.current_task.status -eq "ACTIVE" }).Count
    brigades_with_public_note = @($brigadeRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.latest_public_note.note_path) }).Count
    brigades_with_result_note = @($brigadeRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.last_result.note_path) }).Count
    brigades_with_receipt = @($brigadeRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.note_delivery.last_seen_note_id) }).Count
    brigades_synced_to_latest_note = @($brigadeRows | Where-Object { $_.note_delivery.state -eq "SYNCED_TO_LATEST" -or $_.note_delivery.state -eq "NO_NOTES" }).Count
    active_claims = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $workboard -Name "summary" -Default $null) -Name "active_claims" -Default 0)
}

$overallVerdict = "GAPS_PRESENT"
if (
    $summary.contract_reached_count -eq $summary.total_brigades -and
    $summary.live_lane_count -eq $summary.total_brigades -and
    $summary.brigades_with_public_note -eq $summary.total_brigades -and
    $summary.brigades_synced_to_latest_note -eq $summary.total_brigades
) {
    $overallVerdict = "READY_FOR_CODEX_CHECK"
}

function New-BrigadeSyncManifestNoteText {
    param(
        [string]$GeneratedAtLocal,
        [string]$OverallVerdict,
        [object]$Summary,
        [object]$Contract,
        [object]$KeyNotes,
        [object[]]$BrigadeRows,
        [string]$MarkdownReportPath
    )

    $noteLines = New-Object System.Collections.Generic.List[string]
    $noteLines.Add(("Manifest spiecia brygad {0}" -f $GeneratedAtLocal))
    $noteLines.Add("")
    $noteLines.Add(("Werdykt: {0}" -f $OverallVerdict))
    $noteLines.Add(("Kontrakt ogolny: {0}/{1}" -f $Summary.contract_reached_count, $Summary.total_brigades))
    $noteLines.Add(("Lane active: {0}/{1}" -f $Summary.live_lane_count, $Summary.total_brigades))
    $noteLines.Add(("Public note: {0}/{1}" -f $Summary.brigades_with_public_note, $Summary.total_brigades))
    $noteLines.Add(("Result note: {0}/{1}" -f $Summary.brigades_with_result_note, $Summary.total_brigades))
    $noteLines.Add(("Claimy active: {0}" -f $Summary.active_claims))
    $noteLines.Add("")
    $noteLines.Add(("Execution policy: {0}" -f [string](Get-OptionalValue -Object $Contract -Name "default_execution_policy" -Default "")))
    $noteLines.Add(("Non-target policy: {0}" -f [string](Get-OptionalValue -Object $Contract -Name "default_non_target_policy" -Default "")))
    $noteLines.Add(("Information admin actor: {0}" -f [string](Get-OptionalValue -Object $Contract -Name "information_admin_actor_id" -Default "")))
    $noteLines.Add(("Information admin brigade id: {0}" -f [string](Get-OptionalValue -Object $Contract -Name "information_admin_brigade_id" -Default "")))
    $noteLines.Add(("Addressing rule: {0}" -f [string](Get-OptionalValue -Object $Contract -Name "addressing_rule" -Default "")))
    $noteLines.Add(("Completion report rule: {0}" -f [string](Get-OptionalValue -Object $Contract -Name "completion_report_rule" -Default "")))
    $noteLines.Add("")
    $noteLines.Add(("Kontrakt note: {0}" -f $KeyNotes.contract_note_title))
    $noteLines.Add(("Workflow note: {0}" -f $KeyNotes.workflow_note_title))
    $noteLines.Add(("Plan lane: {0}" -f $KeyNotes.plan_note_title))

    $missingResult = @(
        $BrigadeRows |
            Where-Object { [string]::IsNullOrWhiteSpace((Get-OptionalValue -Object (Get-OptionalValue -Object $_ -Name "last_result" -Default $null) -Name "note_path" -Default "")) } |
            ForEach-Object { [string](Get-OptionalValue -Object $_ -Name "brigade_id" -Default "") } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($missingResult.Count -gt 0) {
        $noteLines.Add("")
        $noteLines.Add(("Bez result note: {0}" -f ($missingResult -join ", ")))
    }

    $nonLive = @(
        $BrigadeRows |
            Where-Object { [string](Get-OptionalValue -Object $_ -Name "wiring_state" -Default "") -ne "LIVE" } |
            ForEach-Object { [string](Get-OptionalValue -Object $_ -Name "brigade_id" -Default "") } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($nonLive.Count -gt 0) {
        $noteLines.Add(("Lane nie-LIVE: {0}" -f ($nonLive -join ", ")))
    }

    $noteLines.Add("")
    $noteLines.Add(("Pelny manifest: {0}" -f $MarkdownReportPath))
    return ($noteLines -join [Environment]::NewLine)
}

$payload = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    overall_verdict = $overallVerdict
    summary = $summary
    contract = [ordered]@{
        registry_path = $RegistryPath
        workspace_instructions_path = if ($workspaceInstructionsExists) { $workspaceInstructionsPath } else { "" }
        start_context_script = $startContextScript
        all_brigades_read_every_new_note = [bool](Get-OptionalValue -Object $policy -Name "all_brigades_read_every_new_note" -Default $false)
        default_execution_policy = [string](Get-OptionalValue -Object $policy -Name "default_execution_policy" -Default "")
        default_non_target_policy = [string](Get-OptionalValue -Object $policy -Name "default_non_target_policy" -Default "")
        information_admin_actor_id = $informationAdminActor
        information_admin_brigade_id = $informationAdminBrigadeId
        processing_owner_must_be_declared = $processingOwnerDeclared
        report_to_must_be_declared = $reportToDeclared
        addressing_rule = if ($processingOwnerDeclared -and $reportToDeclared) { "PROCESSING_OWNER_AND_REPORT_TO_REQUIRED" } elseif ($processingOwnerDeclared) { "PROCESSING_OWNER_REQUIRED" } elseif ($reportToDeclared) { "REPORT_TO_REQUIRED" } else { "OPTIONAL" }
        completion_report_rule = [string](Get-OptionalValue -Object $policy -Name "completion_report_rule" -Default "")
    }
    key_notes = [ordered]@{
        contract_note_title = [string](Get-OptionalValue -Object $contractNote -Name "title" -Default "")
        contract_note_path = [string](Get-OptionalValue -Object $contractNote -Name "note_path" -Default "")
        workflow_note_title = [string](Get-OptionalValue -Object $workflowNote -Name "title" -Default "")
        workflow_note_path = [string](Get-OptionalValue -Object $workflowNote -Name "note_path" -Default "")
        plan_note_title = [string](Get-OptionalValue -Object $planNote -Name "title" -Default "")
        plan_note_path = [string](Get-OptionalValue -Object $planNote -Name "note_path" -Default "")
    }
    brigades = @($brigadeRows)
    sources = [ordered]@{
        mailbox_dir = $MailboxDir
        receipts_path = $receiptsPath
        taskboard_status_path = $taskboardPath
        workboard_status_path = $workboardPath
    }
}

$jsonPath = Join-Path $OutputRoot "brigade_sync_manifest_latest.json"
$mdPath = Join-Path $OutputRoot "brigade_sync_manifest_latest.md"

Write-JsonFile -Path $jsonPath -Payload $payload

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# MANIFEST SPIECIA BRYGAD")
$lines.Add("")
$lines.Add(("Wygenerowano: {0}" -f $payload.generated_at_local))
$lines.Add(("Werdykt: {0}" -f $payload.overall_verdict))
$lines.Add("")
$lines.Add("## Kontrakt ogolny")
$lines.Add("")
$lines.Add(("- registry: {0}" -f $payload.contract.registry_path))
$lines.Add(("- workspace instructions: {0}" -f $payload.contract.workspace_instructions_path))
$lines.Add(("- start context script: {0}" -f $payload.contract.start_context_script))
$lines.Add(("- wszystkie brygady czytaja nowe note: {0}" -f $payload.contract.all_brigades_read_every_new_note))
$lines.Add(("- execution policy: {0}" -f $payload.contract.default_execution_policy))
$lines.Add(("- non-target policy: {0}" -f $payload.contract.default_non_target_policy))
$lines.Add(("- completion report rule: {0}" -f $payload.contract.completion_report_rule))
$lines.Add("")
$lines.Add("## Kluczowe noty")
$lines.Add("")
$lines.Add(("- kontrakt: {0}" -f $payload.key_notes.contract_note_title))
$lines.Add(("- sciezka: {0}" -f $payload.key_notes.contract_note_path))
$lines.Add(("- workflow: {0}" -f $payload.key_notes.workflow_note_title))
$lines.Add(("- sciezka: {0}" -f $payload.key_notes.workflow_note_path))
$lines.Add(("- plan lane: {0}" -f $payload.key_notes.plan_note_title))
$lines.Add(("- sciezka: {0}" -f $payload.key_notes.plan_note_path))
$lines.Add("")
$lines.Add("## Podsumowanie")
$lines.Add("")
$lines.Add(("- brygady z kontraktem ogolnym: {0}/{1}" -f $payload.summary.contract_reached_count, $payload.summary.total_brigades))
$lines.Add(("- aktywne lane: {0}/{1}" -f $payload.summary.live_lane_count, $payload.summary.total_brigades))
$lines.Add(("- brygady z publiczna nota: {0}/{1}" -f $payload.summary.brigades_with_public_note, $payload.summary.total_brigades))
$lines.Add(("- brygady z result note: {0}/{1}" -f $payload.summary.brigades_with_result_note, $payload.summary.total_brigades))
$lines.Add(("- brygady z receipt: {0}/{1}" -f $payload.summary.brigades_with_receipt, $payload.summary.total_brigades))
$lines.Add(("- brygady synced_to_latest_note: {0}/{1}" -f $payload.summary.brigades_synced_to_latest_note, $payload.summary.total_brigades))
$lines.Add(("- aktywne claimy: {0}" -f $payload.summary.active_claims))
$lines.Add("")
$lines.Add("## Brygady")

foreach ($row in $payload.brigades) {
    $lines.Add("")
    $lines.Add(("### {0}" -f $row.brigade_id))
    $lines.Add("")
    $lines.Add(("- actor_id: {0}" -f $row.actor_id))
    $lines.Add(("- startup priority: {0}" -f $row.startup_priority))
    $lines.Add(("- contract reached: {0}" -f $row.contract_reached))
    $lines.Add(("- wiring state: {0}" -f $row.wiring_state))
    $lines.Add(("- prompt path: {0}" -f $row.prompt_path))
    $lines.Add(("- task: {0} :: {1}" -f $row.current_task.status, $row.current_task.title))
    $lines.Add(("- task_id: {0}" -f $row.current_task.task_id))
    $lines.Add(("- last activity: {0} :: {1}" -f $row.current_task.last_activity_at_local, $row.current_task.last_activity_title))
    $lines.Add(("- task report path: {0}" -f $row.current_task.report_path))
    $lines.Add(("- latest public note: {0}" -f $row.latest_public_note.title))
    $lines.Add(("- latest public note path: {0}" -f $row.latest_public_note.note_path))
    $lines.Add(("- latest public note at: {0}" -f $row.latest_public_note.written_at_local))
    $lines.Add(("- note delivery state: {0}" -f $row.note_delivery.state))
    $lines.Add(("- latest global note: {0}" -f $row.note_delivery.latest_global_note_title))
    $lines.Add(("- last seen note id: {0}" -f $row.note_delivery.last_seen_note_id))
    $lines.Add(("- last read at: {0}" -f $row.note_delivery.last_read_at_local))
    $lines.Add(("- last result outcome: {0}" -f $row.last_result.outcome))
    $lines.Add(("- last result note path: {0}" -f $row.last_result.note_path))
    $lines.Add(("- last result reported at: {0}" -f $row.last_result.reported_at_local))
    $lines.Add(("- active claim id: {0}" -f $row.active_claim.claim_id))
    $lines.Add(("- active claim report path: {0}" -f $row.active_claim.report_path))
}

Set-Content -LiteralPath $mdPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8

$publishedNotePath = ""
$publishedNoteTitle = ""
if ($PublishToNotes) {
    $publishedNoteTitle = "{0} {1}" -f $NoteTitlePrefix, ((Get-Date).ToString("yyyyMMdd_HHmmss"))
    $noteText = New-BrigadeSyncManifestNoteText -GeneratedAtLocal $payload.generated_at_local -OverallVerdict $payload.overall_verdict -Summary $payload.summary -Contract $payload.contract -KeyNotes $payload.key_notes -BrigadeRows $payload.brigades -MarkdownReportPath $mdPath
    $publishedNotePath = (& $writeNoteScriptPath -Title $publishedNoteTitle -Text $noteText -MailboxDir $MailboxDir -Author $NoteAuthor -SourceRole $NoteSourceRole -Visibility "ALL_BRIGADES_READ" -ExecutionIntent "STATUS" -ExecutionPolicy "BROADCAST_READ_ONLY" -NonTargetPolicy "READ_ONLY" -RequiresSafetyReview $false -Tags $NoteTags | Select-Object -Last 1)
    if (-not [string]::IsNullOrWhiteSpace($publishedNotePath)) {
        $payload["published_note_title"] = $publishedNoteTitle
        $payload["published_note_path"] = [string]$publishedNotePath
        Write-JsonFile -Path $jsonPath -Payload $payload
    }
}

[pscustomobject]@{
    overall_verdict = $payload.overall_verdict
    summary = [pscustomobject]$payload.summary
    md_path = $mdPath
    json_path = $jsonPath
    published_note_title = $publishedNoteTitle
    published_note_path = $publishedNotePath
} | Format-List