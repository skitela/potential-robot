param(
    [string]$RegistryPath = "",
    [string]$BrigadeId = "",
    [string]$ActorId = "",
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
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
}

function Test-RegistryItemPath {
    param([string]$CandidatePath)
    if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
        return $false
    }

    $workspacePath = Join-Path $repoRoot ($CandidatePath -replace '/', '\')
    return Test-Path -LiteralPath $workspacePath
}

$registry = Read-JsonFile -Path $RegistryPath
$brigades = @($registry.brigades)

if (-not [string]::IsNullOrWhiteSpace($BrigadeId)) {
    $brigades = @($brigades | Where-Object { [string]$_.brigade_id -eq $BrigadeId })
}

if (-not [string]::IsNullOrWhiteSpace($ActorId)) {
    $brigades = @($brigades | Where-Object { [string]$_.actor_id -eq $ActorId })
}

if (@($brigades).Count -eq 0) {
    throw "No brigade matched the given filters."
}

if ($AsJson) {
    [pscustomobject]@{
        registry_path = $RegistryPath
        brigade_count = @($brigades).Count
        brigades = @($brigades)
    } | ConvertTo-Json -Depth 20
    return
}

if (@($brigades).Count -gt 1) {
    $rows = @(
        $brigades | ForEach-Object {
            [pscustomobject]@{
                brigade_id = [string]$_.brigade_id
                actor_id = [string]$_.actor_id
                chat_name = [string]$_.chat_name
                primary_focus = [string]$_.primary_focus
                autostart = if ($_.autostart_enabled) { "ON" } else { "OFF" }
                runtime_state = if ([string]::IsNullOrWhiteSpace([string]$_.default_runtime_state)) { "RUNNING" } else { [string]$_.default_runtime_state }
                claim_roots = @($_.default_claim_roots).Count
                handoff_targets = @($_.handoff_targets).Count
            }
        }
    )

    "ORCHESTRATOR BRIGADES"
    $rows | Format-Table -AutoSize
    ""
    [pscustomobject]@{
        registry_path = $RegistryPath
        brigade_count = @($brigades).Count
        actor_field_policy = [string]$registry.actor_field_policy
    } | Format-List
    return
}

$brigade = $brigades[0]
$claimRows = @(
    @($brigade.default_claim_roots) | ForEach-Object {
        [pscustomobject]@{
            path = [string]$_
            exists = Test-RegistryItemPath -CandidatePath ([string]$_)
        }
    }
)

$contractRows = @(
    @($brigade.shared_contracts) | ForEach-Object {
        [pscustomobject]@{
            path = [string]$_
            exists = Test-RegistryItemPath -CandidatePath ([string]$_)
        }
    }
)

$objectiveRows = @(
    @($registry.primary_objectives) | ForEach-Object {
        [pscustomobject]@{ objective = [string]$_ }
    }
)

$policyRows = @(
    @($registry.universal_execution_policy) | ForEach-Object {
        [pscustomobject]@{ policy = [string]$_ }
    }
)

"BRIGADE"
[pscustomobject]@{
    brigade_id = [string]$brigade.brigade_id
    actor_id = [string]$brigade.actor_id
    chat_name = [string]$brigade.chat_name
    primary_focus = [string]$brigade.primary_focus
    specialization_summary = [string]$brigade.specialization_summary
    mission = [string]$brigade.mission
    autostart_enabled = [bool]$brigade.autostart_enabled
    default_runtime_state = if ([string]::IsNullOrWhiteSpace([string]$brigade.default_runtime_state)) { "RUNNING" } else { [string]$brigade.default_runtime_state }
    startup_priority = [string]$brigade.startup_priority
    startup_task_title = [string]$brigade.startup_task_title
} | Format-List

if (@($objectiveRows).Count -gt 0) {
    "GLOBAL OBJECTIVES"
    $objectiveRows | Format-Table -AutoSize
}

if (@($policyRows).Count -gt 0) {
    "UNIVERSAL EXECUTION POLICY"
    $policyRows | Format-Table -AutoSize
}

"DEFAULT CLAIM ROOTS"
$claimRows | Format-Table -AutoSize

"SHARED CONTRACTS"
$contractRows | Format-Table -AutoSize

"TASK EXAMPLES"
@($brigade.task_examples) | ForEach-Object {
    [pscustomobject]@{ task = [string]$_ }
} | Format-Table -AutoSize

"HANDOFF TARGETS"
@($brigade.handoff_targets) | ForEach-Object {
    [pscustomobject]@{ actor_id = [string]$_ }
} | Format-Table -AutoSize