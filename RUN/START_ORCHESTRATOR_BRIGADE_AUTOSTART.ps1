param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [string]$SourceActor = "codex_workspace_bootstrap"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

$assignScriptPath = Join-Path $PSScriptRoot "ASSIGN_ORCHESTRATOR_BRIGADE_TASK.ps1"
if (-not (Test-Path -LiteralPath $assignScriptPath)) {
    throw "Missing brigade assign script: $assignScriptPath"
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )

    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-StateFilePath {
    param(
        [string]$MailboxRoot,
        [object]$Registry
    )

    $relativePath = "status\brigade_runtime_state.json"
    if ($null -ne $Registry.autostart_policy -and -not [string]::IsNullOrWhiteSpace([string]$Registry.autostart_policy.mailbox_state_path)) {
        $relativePath = ([string]$Registry.autostart_policy.mailbox_state_path).Replace('/', '\')
    }

    return Join-Path $MailboxRoot $relativePath
}

function Get-AutostartStatusPath {
    param(
        [string]$MailboxRoot,
        [object]$Registry
    )

    $relativePath = "status\brigade_autostart_latest.json"
    if ($null -ne $Registry.autostart_policy -and -not [string]::IsNullOrWhiteSpace([string]$Registry.autostart_policy.mailbox_autostart_status_path)) {
        $relativePath = ([string]$Registry.autostart_policy.mailbox_autostart_status_path).Replace('/', '\')
    }

    return Join-Path $MailboxRoot $relativePath
}

function New-BrigadeStateEntry {
    param([object]$Brigade)

    return [ordered]@{
        brigade_id = [string]$Brigade.brigade_id
        actor_id = [string]$Brigade.actor_id
        chat_name = [string]$Brigade.chat_name
        state = if ([string]::IsNullOrWhiteSpace([string]$Brigade.default_runtime_state)) { "RUNNING" } else { [string]$Brigade.default_runtime_state }
        autostart_enabled = [bool]$Brigade.autostart_enabled
        pause_reason = ""
        updated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Initialize-StatePayload {
    param(
        [object]$Registry,
        [object]$ExistingState
    )

    $rows = New-Object System.Collections.ArrayList
    foreach ($brigade in @($Registry.brigades)) {
        $existing = if ($null -ne $ExistingState) {
            @($ExistingState.brigades | Where-Object { [string]$_.brigade_id -eq [string]$brigade.brigade_id }) | Select-Object -First 1
        }
        else {
            $null
        }

        if ($null -eq $existing) {
            [void]$rows.Add((New-BrigadeStateEntry -Brigade $brigade))
        }
        else {
            [void]$rows.Add([ordered]@{
                brigade_id = [string]$existing.brigade_id
                actor_id = [string]$existing.actor_id
                chat_name = [string]$existing.chat_name
                state = if ([string]::IsNullOrWhiteSpace([string]$existing.state)) { if ([string]::IsNullOrWhiteSpace([string]$brigade.default_runtime_state)) { "RUNNING" } else { [string]$brigade.default_runtime_state } } else { [string]$existing.state }
                autostart_enabled = if ($null -ne $existing.autostart_enabled) { [bool]$existing.autostart_enabled } else { [bool]$brigade.autostart_enabled }
                pause_reason = [string]$existing.pause_reason
                updated_at_local = [string]$existing.updated_at_local
            })
        }
    }

    return [ordered]@{
        written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        brigades = @($rows)
    }
}

function Get-OpenTaskCount {
    param(
        [string]$MailboxRoot,
        [string]$ActorId
    )

    $count = 0
    foreach ($stateDir in @("pending", "active", "blocked")) {
        $root = Join-Path $MailboxRoot ("coordination\tasks\{0}" -f $stateDir)
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        $count += @(Get-ChildItem -LiteralPath $root -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $task = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
                if ([string]$task.assigned_to -eq $ActorId) {
                    $_
                }
            }
            catch {
            }
        }).Count
    }

    return $count
}

function Get-StartupProtocolText {
    param([object]$Registry)

    if ($null -eq $Registry -or $null -eq $Registry.startup_protocol) {
        return ""
    }

    if (-not [bool]$Registry.startup_protocol.enabled) {
        return ""
    }

    $steps = @($Registry.startup_protocol.required_steps | Where-Object {
        $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_)
    } | ForEach-Object { "- {0}" -f [string]$_ })

    if (@($steps).Count -eq 0) {
        return ""
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Startup protocol:")
    foreach ($step in $steps) {
        $lines.Add($step)
    }

    $scriptPath = [string]$Registry.startup_protocol.start_context_script
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        $lines.Add("")
        $lines.Add(("Start context script: {0} -BrigadeId <brigade_id>" -f $scriptPath))
    }

    return $lines -join [Environment]::NewLine
}

$registry = Read-JsonFile -Path $RegistryPath
$statePath = Get-StateFilePath -MailboxRoot $MailboxDir -Registry $registry
$autostartStatusPath = Get-AutostartStatusPath -MailboxRoot $MailboxDir -Registry $registry

New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($statePath)) | Out-Null
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($autostartStatusPath)) | Out-Null

$existingState = if (Test-Path -LiteralPath $statePath) { Read-JsonFile -Path $statePath } else { $null }
$statePayload = Initialize-StatePayload -Registry $registry -ExistingState $existingState
Write-JsonFile -Path $statePath -Payload $statePayload

$startedRows = New-Object System.Collections.ArrayList
$skippedRows = New-Object System.Collections.ArrayList

foreach ($brigade in @($registry.brigades)) {
    $stateRow = @($statePayload.brigades | Where-Object { [string]$_.brigade_id -eq [string]$brigade.brigade_id }) | Select-Object -First 1
    if ($null -eq $stateRow) {
        continue
    }

    if (-not [bool]$stateRow.autostart_enabled) {
        [void]$skippedRows.Add([ordered]@{
            brigade_id = [string]$brigade.brigade_id
            actor_id = [string]$brigade.actor_id
            reason = "AUTOSTART_DISABLED"
        })
        continue
    }

    if ([string]$stateRow.state -eq "PAUSED") {
        [void]$skippedRows.Add([ordered]@{
            brigade_id = [string]$brigade.brigade_id
            actor_id = [string]$brigade.actor_id
            reason = if ([string]::IsNullOrWhiteSpace([string]$stateRow.pause_reason)) { "PAUSED" } else { "PAUSED: {0}" -f [string]$stateRow.pause_reason }
        })
        continue
    }

    $openTaskCount = Get-OpenTaskCount -MailboxRoot $MailboxDir -ActorId ([string]$brigade.actor_id)
    if ($openTaskCount -gt 0) {
        [void]$skippedRows.Add([ordered]@{
            brigade_id = [string]$brigade.brigade_id
            actor_id = [string]$brigade.actor_id
            reason = "OPEN_TASK_EXISTS:{0}" -f $openTaskCount
        })
        continue
    }

    $priority = if ([string]::IsNullOrWhiteSpace([string]$brigade.startup_priority)) { "NORMAL" } else { [string]$brigade.startup_priority }
    $title = if ([string]::IsNullOrWhiteSpace([string]$brigade.startup_task_title)) { "Autostart backlog dla brygady" } else { [string]$brigade.startup_task_title }
    $instructionsBase = if ([string]::IsNullOrWhiteSpace([string]$brigade.startup_instructions)) { [string]$brigade.mission } else { [string]$brigade.startup_instructions }
    $startupProtocolText = Get-StartupProtocolText -Registry $registry
    $instructions = if ([string]::IsNullOrWhiteSpace($startupProtocolText)) {
        $instructionsBase
    }
    else {
        @(
            $instructionsBase,
            "",
            $startupProtocolText
        ) -join [Environment]::NewLine
    }

    & $assignScriptPath `
        -BrigadeId ([string]$brigade.brigade_id) `
        -Title $title `
        -SourceActor $SourceActor `
        -MailboxDir $MailboxDir `
        -ScopePaths @($brigade.default_claim_roots) `
        -Instructions $instructions `
        -Priority $priority | Out-Null

    [void]$startedRows.Add([ordered]@{
        brigade_id = [string]$brigade.brigade_id
        actor_id = [string]$brigade.actor_id
        priority = $priority
        title = $title
    })
}

$writtenAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$statusPayload = [ordered]@{
    written_at_local = $writtenAt
    mailbox_dir = $MailboxDir
    source_actor = $SourceActor
    started_rows = @($startedRows)
    skipped_rows = @($skippedRows)
}

Write-JsonFile -Path $autostartStatusPath -Payload $statusPayload

[pscustomobject]@{
    source_actor = $SourceActor
    started_brigades = @($startedRows).Count
    skipped_brigades = @($skippedRows).Count
    state_path = $statePath
    autostart_status_path = $autostartStatusPath
    written_at_local = $writtenAt
} | Format-List