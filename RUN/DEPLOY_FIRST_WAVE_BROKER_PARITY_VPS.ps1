param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ConfigPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\first_wave_final_deployment_v1.json",
    [switch]$SkipMigration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
}

function Invoke-Step {
    param(
        [string]$Label,
        [scriptblock]$Action
    )

    $result = [ordered]@{
        label = $Label
        ok = $false
        message = ""
    }

    try {
        $output = & $Action 2>&1 | Out-String
        $result.ok = $true
        $result.message = ($output -replace '\s+', ' ').Trim()
    }
    catch {
        $result.message = $_.Exception.Message
    }

    return [pscustomobject]$result
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

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$config = Read-JsonSafe -Path $ConfigPath
if ($null -eq $config) {
    throw "Brak konfiguracji wdrozenia pierwszej fali: $ConfigPath"
}

$opsRoot = Join-Path $projectRootResolved "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null
$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$jsonPath = Join-Path $opsRoot ("first_wave_final_deploy_{0}.json" -f $stamp)
$jsonLatestPath = Join-Path $opsRoot "first_wave_final_deploy_latest.json"
$mdLatestPath = Join-Path $opsRoot "first_wave_final_deploy_latest.md"

$steps = New-Object System.Collections.Generic.List[object]

$runtimeProfile = [string](Get-OptionalValue -Object $config -Name "runtime_profile" -Default "BROKER_PARITY_FIRST_WAVE")
$applyRuntimeProfile = [bool](Get-OptionalValue -Object $config -Name "apply_runtime_profile_before_preflight" -Default $true)
$validateCoordinator = [bool](Get-OptionalValue -Object $config -Name "validate_session_capital_after_runtime_apply" -Default $true)
$migrationConfig = Get-OptionalValue -Object $config -Name "migration" -Default $null
$migrationEnabled = [bool](Get-OptionalValue -Object $migrationConfig -Name "enabled" -Default $true)
$applySafeRepairAfterMigration = [bool](Get-OptionalValue -Object $migrationConfig -Name "apply_safe_repair_after_migration" -Default $true)
$vpsSyncTimeoutSec = [int](Get-OptionalValue -Object $migrationConfig -Name "vps_sync_timeout_sec" -Default 240)
$postStartupAuditDelaySec = [int](Get-OptionalValue -Object $migrationConfig -Name "post_startup_audit_delay_sec" -Default 180)
$postStartupContinuitySamples = [int](Get-OptionalValue -Object $migrationConfig -Name "post_startup_continuity_samples" -Default 3)
$postStartupIntervalSec = [int](Get-OptionalValue -Object $migrationConfig -Name "post_startup_interval_sec" -Default 20)

if ($applyRuntimeProfile) {
    $steps.Add((Invoke-Step -Label "apply_runtime_profile" -Action {
        & (Join-Path $projectRootResolved "RUN\APPLY_FIRST_WAVE_BROKER_PARITY_RUNTIME.ps1") -ProjectRoot $projectRootResolved
    })) | Out-Null
}

if ($validateCoordinator) {
    $steps.Add((Invoke-Step -Label "validate_session_capital" -Action {
        & (Join-Path $projectRootResolved "TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1") -ProjectRoot $projectRootResolved
    })) | Out-Null
}

$refreshScripts = @(
    "RUN\BUILD_TRADE_TRANSITION_AUDIT.ps1",
    "RUN\BUILD_QDM_CUSTOM_SYMBOL_REALISM_AUDIT.ps1",
    "RUN\BUILD_MT5_PRETRADE_EXECUTION_TRUTH_STATUS.ps1",
    "RUN\BUILD_LOCAL_MODEL_READINESS_AUDIT.ps1",
    "RUN\BUILD_MT5_FIRST_WAVE_SERVER_PARITY_AUDIT.ps1",
    "RUN\BUILD_MT5_FIRST_WAVE_RUNTIME_ACTIVITY_AUDIT.ps1",
    "RUN\BUILD_FIRST_WAVE_LESSON_CLOSURE_AUDIT.ps1"
)

foreach ($relativeScript in $refreshScripts) {
    $scriptPath = Join-Path $projectRootResolved $relativeScript
    $label = [System.IO.Path]::GetFileNameWithoutExtension($relativeScript)
    $steps.Add((Invoke-Step -Label $label -Action {
        & $scriptPath -ProjectRoot $projectRootResolved
    })) | Out-Null
}

$parityAudit = Read-JsonSafe -Path (Join-Path $opsRoot "mt5_first_wave_server_parity_latest.json")
$runtimeAudit = Read-JsonSafe -Path (Join-Path $opsRoot "mt5_first_wave_runtime_activity_latest.json")
$closureAudit = Read-JsonSafe -Path (Join-Path $opsRoot "first_wave_lesson_closure_latest.json")
$wellbeing = Read-JsonSafe -Path (Join-Path $opsRoot "learning_wellbeing_latest.json")
$fullStack = Read-JsonSafe -Path (Join-Path $opsRoot "full_stack_audit_latest.json")

$preflight = [ordered]@{
    runtime_profile_target = $runtimeProfile
    parity_verdict = [string](Get-OptionalValue -Object $parityAudit -Name "verdict" -Default "")
    runtime_activity_verdict = [string](Get-OptionalValue -Object $runtimeAudit -Name "verdict" -Default "")
    lesson_closure_verdict = [string](Get-OptionalValue -Object $closureAudit -Name "verdict" -Default "")
    wellbeing_verdict = [string](Get-OptionalValue -Object $wellbeing -Name "verdict" -Default "")
    release_gate_verdict = [string](Get-OptionalValue -Object (Get-OptionalValue -Object $fullStack -Name "release_gate" -Default $null) -Name "verdict" -Default "")
    runtime_profile_match = [bool](Get-OptionalValue -Object (Get-OptionalValue -Object $parityAudit -Name "summary" -Default $null) -Name "runtime_profile_match" -Default $false)
    capital_isolation_ready = [bool](Get-OptionalValue -Object (Get-OptionalValue -Object $parityAudit -Name "summary" -Default $null) -Name "capital_isolation_ready" -Default $false)
    truth_hook_ready_count = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $parityAudit -Name "summary" -Default $null) -Name "truth_hook_ready_count" -Default 0)
    local_model_ready_count = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $parityAudit -Name "summary" -Default $null) -Name "local_model_ready_count" -Default 0)
    broker_mirror_ready_count = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $fullStack -Name "lab_health" -Default $null).qdm_custom_symbol_realism -Name "broker_mirror_ready_count" -Default 0)
    fresh_lesson_chain_count = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $closureAudit -Name "summary" -Default $null) -Name "fresh_chain_ready_count" -Default 0)
    historical_lesson_chain_count = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $closureAudit -Name "summary" -Default $null) -Name "historical_chain_ready_count" -Default 0)
}

$requiredTruthHooks = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $config -Name "success_contract" -Default $null) -Name "require_truth_hooks_ready_count" -Default 4)
$requiredLocalModels = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $config -Name "success_contract" -Default $null) -Name "require_local_model_ready_count" -Default 4)
$requiredBrokerMirrors = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $config -Name "success_contract" -Default $null) -Name "require_broker_mirror_ready_count" -Default 4)
$requireRuntimeProfileMatch = [bool](Get-OptionalValue -Object (Get-OptionalValue -Object $config -Name "success_contract" -Default $null) -Name "require_runtime_profile_match" -Default $true)
$requireCapitalIsolationReady = [bool](Get-OptionalValue -Object (Get-OptionalValue -Object $config -Name "success_contract" -Default $null) -Name "require_capital_isolation_ready" -Default $true)

$preflightIssues = New-Object System.Collections.Generic.List[string]
if ($preflight.truth_hook_ready_count -lt $requiredTruthHooks) { $preflightIssues.Add("BRAK_PELNYCH_HAKOW_PRAWDY") | Out-Null }
if ($preflight.local_model_ready_count -lt $requiredLocalModels) { $preflightIssues.Add("BRAK_PELNEJ_GOTOWOSCI_MODELI_LOKALNYCH") | Out-Null }
if ($preflight.broker_mirror_ready_count -lt $requiredBrokerMirrors) { $preflightIssues.Add("BRAK_PELNEGO_LUSTRA_BROKERA") | Out-Null }
if ($requireRuntimeProfileMatch -and -not $preflight.runtime_profile_match) { $preflightIssues.Add("NIEZGODNY_PROFIL_WYKONAWCZY") | Out-Null }
if ($requireCapitalIsolationReady -and -not $preflight.capital_isolation_ready) { $preflightIssues.Add("BRAK_ODSEPAROWANIA_KAPITALU") | Out-Null }

$migrationResult = $null
if (-not $SkipMigration -and $migrationEnabled -and $preflightIssues.Count -eq 0) {
    $migrationResult = Invoke-Step -Label "migrate_first_wave_to_vps" -Action {
        & (Join-Path $projectRootResolved "RUN\MIGRATE_OANDA_MT5_VPS_CLEAN.ps1") `
            -ProjectRoot $projectRootResolved `
            -VpsSyncTimeoutSec $vpsSyncTimeoutSec `
            -PostStartupAuditDelaySec $postStartupAuditDelaySec `
            -PostStartupAuditContinuitySamples $postStartupContinuitySamples `
            -PostStartupAuditIntervalSec $postStartupIntervalSec
    }
    $steps.Add($migrationResult) | Out-Null
}

$postMigrationRefresh = New-Object System.Collections.Generic.List[object]
if (-not $SkipMigration -and $migrationEnabled -and $preflightIssues.Count -eq 0) {
    $postMigrationRefresh.Add((Invoke-Step -Label "post_migration_startup_audit" -Action {
        & (Join-Path $projectRootResolved "RUN\AUDIT_POST_MIGRATION_STARTUP.ps1") `
            -ProjectRoot $projectRootResolved `
            -SkipWait `
            -ApplySafeRepair:$applySafeRepairAfterMigration
    })) | Out-Null
    $postMigrationRefresh.Add((Invoke-Step -Label "learning_wellbeing_after_migration" -Action {
        & (Join-Path $projectRootResolved "RUN\MAINTAIN_LEARNING_WELLBEING.ps1") -ProjectRoot $projectRootResolved -AutoHealLevel Safe
    })) | Out-Null
    $postMigrationRefresh.Add((Invoke-Step -Label "full_stack_after_migration" -Action {
        & (Join-Path $projectRootResolved "RUN\BUILD_FULL_STACK_AUDIT.ps1") -ProjectRoot $projectRootResolved
    })) | Out-Null
}

$postMigrationAudit = Read-JsonSafe -Path (Join-Path $opsRoot "post_migration_startup_audit_latest.json")

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectRootResolved
    config_path = $ConfigPath
    skip_migration = [bool]$SkipMigration
    preflight = [pscustomobject]@{
        summary = $preflight
        issues = @($preflightIssues.ToArray())
        ok = ($preflightIssues.Count -eq 0)
    }
    steps = @($steps.ToArray())
    post_migration_refresh = @($postMigrationRefresh.ToArray())
    post_migration_audit = $postMigrationAudit
    verdict = if ($preflightIssues.Count -gt 0) {
        "PREFLIGHT_BLOCKED"
    }
    elseif ($SkipMigration -or -not $migrationEnabled) {
        "PLAN_GOTOWY_DO_MIGRACJI"
    }
    elseif ($null -ne $postMigrationAudit -and [bool](Get-OptionalValue -Object $postMigrationAudit -Name "ok" -Default $false)) {
        "MIGRACJA_I_ROZRUCH_OK"
    }
    else {
        "MIGRACJA_WYMAGA_DALSZEGO_DOPELCENIA"
    }
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatestPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# First Wave Final Deploy")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- preflight_ok: {0}" -f ([string]$report.preflight.ok).ToLowerInvariant()))
$lines.Add(("- skip_migration: {0}" -f ([string]$report.skip_migration).ToLowerInvariant()))
$lines.Add(("- runtime_profile_target: {0}" -f $report.preflight.summary.runtime_profile_target))
$lines.Add(("- runtime_profile_match: {0}" -f ([string]$report.preflight.summary.runtime_profile_match).ToLowerInvariant()))
$lines.Add(("- parity_verdict: {0}" -f $report.preflight.summary.parity_verdict))
$lines.Add(("- runtime_activity_verdict: {0}" -f $report.preflight.summary.runtime_activity_verdict))
$lines.Add(("- lesson_closure_verdict: {0}" -f $report.preflight.summary.lesson_closure_verdict))
$lines.Add(("- wellbeing_verdict: {0}" -f $report.preflight.summary.wellbeing_verdict))
$lines.Add(("- release_gate_verdict: {0}" -f $report.preflight.summary.release_gate_verdict))
$lines.Add("")
$lines.Add("## Preflight Issues")
$lines.Add("")
if (@($report.preflight.issues).Count -eq 0) {
    $lines.Add("- brak")
}
else {
    foreach ($issue in @($report.preflight.issues)) {
        $lines.Add(("- {0}" -f $issue))
    }
}
$lines.Add("")
$lines.Add("## Steps")
$lines.Add("")
foreach ($step in @($report.steps)) {
    $lines.Add(("- {0}: {1}" -f $step.label, $(if ($step.ok) { "ok" } else { $step.message })))
}
$lines | Set-Content -LiteralPath $mdLatestPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
