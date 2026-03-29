param(
    [Parameter(Mandatory = $true)]
    [string]$BrigadeId,
    [ValidateSet("RUNNING", "PAUSED")]
    [string]$DesiredState = "RUNNING",
    [string]$Reason = "",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
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

function Resolve-Brigade {
    param(
        [object]$Registry,
        [string]$Lookup
    )

    return @($Registry.brigades | Where-Object {
        [string]$_.brigade_id -eq $Lookup -or [string]$_.actor_id -eq $Lookup
    }) | Select-Object -First 1
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

$registry = Read-JsonFile -Path $RegistryPath
$brigade = Resolve-Brigade -Registry $registry -Lookup $BrigadeId
if ($null -eq $brigade) {
    throw "Unknown brigade id or actor id: $BrigadeId"
}

$statePath = Get-StateFilePath -MailboxRoot $MailboxDir -Registry $registry
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($statePath)) | Out-Null

$statePayload = if (Test-Path -LiteralPath $statePath) { Read-JsonFile -Path $statePath } else { $null }
if ($null -eq $statePayload) {
    $statePayload = [ordered]@{
        written_at_local = ""
        brigades = @()
    }
}

$stateRows = New-Object System.Collections.ArrayList
foreach ($registryBrigade in @($registry.brigades)) {
    $existing = @($statePayload.brigades | Where-Object { [string]$_.brigade_id -eq [string]$registryBrigade.brigade_id }) | Select-Object -First 1
    if ($null -eq $existing) {
        [void]$stateRows.Add((New-BrigadeStateEntry -Brigade $registryBrigade))
    }
    else {
        [void]$stateRows.Add([ordered]@{
            brigade_id = [string]$existing.brigade_id
            actor_id = [string]$existing.actor_id
            chat_name = [string]$existing.chat_name
            state = if ([string]::IsNullOrWhiteSpace([string]$existing.state)) { "RUNNING" } else { [string]$existing.state }
            autostart_enabled = [bool]$existing.autostart_enabled
            pause_reason = [string]$existing.pause_reason
            updated_at_local = [string]$existing.updated_at_local
        })
    }
}

$updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
foreach ($stateRow in $stateRows) {
    if ([string]$stateRow.brigade_id -eq [string]$brigade.brigade_id) {
        $stateRow.state = $DesiredState
        $stateRow.autostart_enabled = [bool]$brigade.autostart_enabled
        $stateRow.pause_reason = if ($DesiredState -eq "PAUSED") { $Reason } else { "" }
        $stateRow.updated_at_local = $updatedAt
    }
}

$payload = [ordered]@{
    written_at_local = $updatedAt
    brigades = @($stateRows)
}

Write-JsonFile -Path $statePath -Payload $payload

[pscustomobject]@{
    brigade_id = [string]$brigade.brigade_id
    actor_id = [string]$brigade.actor_id
    state = $DesiredState
    autostart_enabled = [bool]$brigade.autostart_enabled
    reason = if ($DesiredState -eq "PAUSED") { $Reason } else { "" }
    state_path = $statePath
    updated_at_local = $updatedAt
} | Format-List