param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$AssignedTo = "",
    [int]$Limit = 50,
    [int]$StaleMinutes = 30,
    [string]$RegistryPath = "",
    [switch]$ByBrigade,
    [switch]$ShowDone
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

$tasksPendingDir = Join-Path $MailboxDir "coordination\tasks\pending"
$tasksActiveDir = Join-Path $MailboxDir "coordination\tasks\active"
$tasksBlockedDir = Join-Path $MailboxDir "coordination\tasks\blocked"
$tasksDoneDir = Join-Path $MailboxDir "coordination\tasks\done"
$statusDir = Join-Path $MailboxDir "status"
New-Item -ItemType Directory -Force -Path $tasksPendingDir, $tasksActiveDir, $tasksBlockedDir, $tasksDoneDir, $statusDir | Out-Null

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

function Get-BrigadeStateFilePath {
    param(
        [string]$MailboxRoot,
        [object]$Registry
    )

    $relativePath = "status\brigade_runtime_state.json"
    if ($null -ne $Registry -and $null -ne $Registry.autostart_policy -and -not [string]::IsNullOrWhiteSpace([string]$Registry.autostart_policy.mailbox_state_path)) {
        $relativePath = ([string]$Registry.autostart_policy.mailbox_state_path).Replace('/', '\')
    }

    return Join-Path $MailboxRoot $relativePath
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

function Get-TaskRows {
    param(
        [string]$DirectoryPath,
        [string]$BaseState,
        [int]$Limit,
        [int]$StaleMinutes,
        [string]$AssignedToFilter
    )

    $now = Get-Date
    return Get-ChildItem -LiteralPath $DirectoryPath -Filter *.json -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            $task = Read-JsonFile -Path $_.FullName
            if ($null -eq $task) {
                return
            }
            if (-not [string]::IsNullOrWhiteSpace($AssignedToFilter) -and [string]$task.assigned_to -ne $AssignedToFilter) {
                return
            }
            $displayState = $BaseState
            if ($BaseState -eq "ACTIVE") {
                $lastActivityAt = Get-DateSafe -Text ([string]$task.last_activity_at_local)
                if ($null -ne $lastActivityAt -and $lastActivityAt -lt $now.AddMinutes(-1 * $StaleMinutes)) {
                    $displayState = "STALE_ACTIVE"
                }
            }
            [pscustomobject]@{
                state = $displayState
                assigned_to = [string]$task.assigned_to
                title = [string]$task.title
                priority = [string]$task.priority
                report_path = [string]$task.report_path
                updated_at_local = [string]$task.updated_at_local
                last_activity_at_local = [string]$task.last_activity_at_local
                task_id = [string]$task.task_id
            }
        } | Select-Object -First $Limit
}

$pendingRows = @(Get-TaskRows -DirectoryPath $tasksPendingDir -BaseState "PENDING" -Limit $Limit -StaleMinutes $StaleMinutes -AssignedToFilter $AssignedTo)
$activeRows = @(Get-TaskRows -DirectoryPath $tasksActiveDir -BaseState "ACTIVE" -Limit $Limit -StaleMinutes $StaleMinutes -AssignedToFilter $AssignedTo)
$blockedRows = @(Get-TaskRows -DirectoryPath $tasksBlockedDir -BaseState "BLOCKED" -Limit $Limit -StaleMinutes $StaleMinutes -AssignedToFilter $AssignedTo)
$doneRows = @()
if ($ShowDone) {
    $doneRows = @(Get-TaskRows -DirectoryPath $tasksDoneDir -BaseState "DONE" -Limit $Limit -StaleMinutes $StaleMinutes -AssignedToFilter $AssignedTo)
}

$brigadeRows = @()
if ($ByBrigade -and (Test-Path -LiteralPath $RegistryPath)) {
    $registry = Read-JsonFile -Path $RegistryPath
    if ($null -ne $registry) {
        $statePath = Get-BrigadeStateFilePath -MailboxRoot $MailboxDir -Registry $registry
        $statePayload = if (Test-Path -LiteralPath $statePath) { Read-JsonFile -Path $statePath } else { $null }
        $stateBrigades = @()
        if ($null -ne $statePayload -and $statePayload.PSObject.Properties.Name -contains "brigades") {
            $stateBrigades = @($statePayload.brigades)
        }
        foreach ($brigade in @($registry.brigades)) {
            $brigadeState = @($stateBrigades | Where-Object { [string]$_.brigade_id -eq [string]$brigade.brigade_id -or [string]$_.actor_id -eq [string]$brigade.actor_id }) | Select-Object -First 1
            $assignedActor = [string]$brigade.actor_id
            $brigadeRows += [pscustomobject]@{
                brigade_id = [string]$brigade.brigade_id
                actor_id = $assignedActor
                state = if ($null -ne $brigadeState -and -not [string]::IsNullOrWhiteSpace([string]$brigadeState.state)) { [string]$brigadeState.state } else { if ([string]::IsNullOrWhiteSpace([string]$brigade.default_runtime_state)) { "RUNNING" } else { [string]$brigade.default_runtime_state } }
                autostart = if ($null -ne $brigadeState -and $brigadeState.PSObject.Properties.Name -contains "autostart_enabled") { if ($brigadeState.autostart_enabled) { "ON" } else { "OFF" } } else { if ($brigade.autostart_enabled) { "ON" } else { "OFF" } }
                pending = @($pendingRows | Where-Object { $_.assigned_to -eq $assignedActor }).Count
                active = @($activeRows | Where-Object { $_.assigned_to -eq $assignedActor -and $_.state -eq "ACTIVE" }).Count
                stale_active = @($activeRows | Where-Object { $_.assigned_to -eq $assignedActor -and $_.state -eq "STALE_ACTIVE" }).Count
                blocked = @($blockedRows | Where-Object { $_.assigned_to -eq $assignedActor }).Count
                done_shown = @($doneRows | Where-Object { $_.assigned_to -eq $assignedActor }).Count
                startup_priority = [string]$brigade.startup_priority
            }
        }
    }
}

$summary = [ordered]@{
    pending_tasks = @($pendingRows).Count
    active_tasks = @($activeRows | Where-Object { $_.state -eq "ACTIVE" }).Count
    stale_active_tasks = @($activeRows | Where-Object { $_.state -eq "STALE_ACTIVE" }).Count
    blocked_tasks = @($blockedRows).Count
    done_tasks_shown = @($doneRows).Count
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

Write-JsonFile -Path (Join-Path $statusDir "taskboard_latest.json") -Payload ([ordered]@{
    summary = $summary
    pending_rows = @($pendingRows)
    active_rows = @($activeRows)
    blocked_rows = @($blockedRows)
    done_rows = @($doneRows)
    brigade_rows = @($brigadeRows)
})

"PENDING TASKS"
@($pendingRows) | Format-Table -AutoSize
""
"ACTIVE TASKS"
@($activeRows) | Format-Table -AutoSize
""
"BLOCKED TASKS"
@($blockedRows) | Format-Table -AutoSize

if ($ShowDone) {
    ""
    "DONE TASKS"
    @($doneRows) | Format-Table -AutoSize
}

if ($ByBrigade -and @($brigadeRows).Count -gt 0) {
    ""
    "BRIGADE TASKBOARD"
    @($brigadeRows) | Format-Table -AutoSize
}

""
[pscustomobject]$summary | Format-List