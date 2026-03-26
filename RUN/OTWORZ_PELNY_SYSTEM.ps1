param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$MlPerfProfile = "OfflineMax",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$NearProfitPerfProfile = "ConcurrentLab",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$reportPath = Join-Path $opsRoot "system_open_latest.json"
$reportMdPath = Join-Path $opsRoot "system_open_latest.md"

$perfScript = Join-Path $ProjectRoot "RUN\APPLY_WORKSTATION_PERF_TUNING.ps1"
$haltScript = Join-Path $ProjectRoot "RUN\ZATRZYMAJ_SYSTEM.ps1"
$normalScript = Join-Path $ProjectRoot "RUN\WLACZ_TRYB_NORMALNY_SYSTEMU.ps1"
$snapshotScript = Join-Path $ProjectRoot "RUN\SAVE_LOCAL_OPERATOR_SNAPSHOT.ps1"
$auditScript = Join-Path $ProjectRoot "RUN\START_AUDIT_SUPERVISOR_BACKGROUND.ps1"
$autonomousScript = Join-Path $ProjectRoot "RUN\START_AUTONOMOUS_90P_SUPERVISOR_BACKGROUND.ps1"
$archiverScript = Join-Path $ProjectRoot "RUN\START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1"
$watcherScript = Join-Path $ProjectRoot "RUN\START_MT5_TESTER_STATUS_WATCHER_BACKGROUND.ps1"
$riskGuardScript = Join-Path $ProjectRoot "RUN\START_MT5_RISK_POPUP_GUARD_BACKGROUND.ps1"
$mlScript = Join-Path $ProjectRoot "RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1"
$qdmMissingSyncScript = Join-Path $ProjectRoot "RUN\START_QDM_MISSING_SUPPORTED_SYNC_BACKGROUND.ps1"
$weakestScript = Join-Path $ProjectRoot "RUN\START_WEAKEST_MT5_BATCH_BACKGROUND.ps1"
$nearProfitScript = Join-Path $ProjectRoot "RUN\START_NEAR_PROFIT_OPTIMIZATION_AFTER_IDLE_BACKGROUND.ps1"
$openMt5Script = Join-Path $ProjectRoot "RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1"

foreach ($path in @(
    $perfScript,
    $haltScript,
    $normalScript,
    $snapshotScript,
    $auditScript,
    $autonomousScript,
    $archiverScript,
    $watcherScript,
    $riskGuardScript,
    $mlScript,
    $qdmMissingSyncScript,
    $weakestScript,
    $nearProfitScript,
    $openMt5Script
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

$actions = New-Object System.Collections.Generic.List[object]

function Add-ActionResult {
    param(
        [string]$Step,
        [string]$Status,
        [string]$Message
    )

    $actions.Add([pscustomobject]@{
            step = $Step
            status = $Status
            message = $Message
            ts_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }) | Out-Null
}

function Invoke-Step {
    param(
        [string]$Step,
        [scriptblock]$Operation
    )

    if ($DryRun) {
        Add-ActionResult -Step $Step -Status "dry_run" -Message "planned"
        return
    }

    try {
        $output = @(
            @(& $Operation 2>&1) |
                ForEach-Object { ([string]$_).Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        $message = if ($output.Count -gt 0) { ($output -join " | ") } else { "ok" }
        Add-ActionResult -Step $Step -Status "ok" -Message $message
    }
    catch {
        Add-ActionResult -Step $Step -Status "error" -Message $_.Exception.Message
        throw
    }
}

try {
    Invoke-Step -Step "snapshot_before_boot" -Operation {
        & $snapshotScript -ProjectRoot $ProjectRoot -OutputRoot $opsRoot | Out-Null
    }

    Invoke-Step -Step "set_halt_for_boot" -Operation {
        & $haltScript -ProjectRoot $ProjectRoot | Out-Null
    }

    Invoke-Step -Step "apply_perf_profile" -Operation {
        & $perfScript -ThrottleInteractiveApps -MlPerfProfile $MlPerfProfile
    }

    Invoke-Step -Step "start_audit_supervisor" -Operation {
        & $auditScript -ProjectRoot $ProjectRoot -StopExisting -ApplySafeAutoHeal
    }

    Invoke-Step -Step "start_autonomous_supervisor" -Operation {
        & $autonomousScript -ProjectRoot $ProjectRoot -StopExisting
    }

    Invoke-Step -Step "start_archiver" -Operation {
        & $archiverScript -ProjectRoot $ProjectRoot
    }

    Invoke-Step -Step "start_tester_watcher" -Operation {
        & $watcherScript -ProjectRoot $ProjectRoot
    }

    Invoke-Step -Step "start_risk_guard" -Operation {
        & $riskGuardScript -ProjectRoot $ProjectRoot
    }

    Invoke-Step -Step "start_ml_pipeline" -Operation {
        & $mlScript -ProjectRoot $ProjectRoot -PerfProfile $MlPerfProfile
    }

    Invoke-Step -Step "start_qdm_missing_sync" -Operation {
        & $qdmMissingSyncScript -ProjectRoot $ProjectRoot
    }

    Invoke-Step -Step "start_weakest_batch" -Operation {
        & $weakestScript -ProjectRoot $ProjectRoot
    }

    Invoke-Step -Step "start_near_profit_lane" -Operation {
        & $nearProfitScript -ProjectRoot $ProjectRoot -ResearchPerfProfile $NearProfitPerfProfile
    }

    Invoke-Step -Step "open_oanda_mt5" -Operation {
        & $openMt5Script -AllowBlockedAuditGate
    }

    Invoke-Step -Step "boot_settle_wait" -Operation {
        Start-Sleep -Seconds 8
        "waited_8s"
    }

    Invoke-Step -Step "set_runtime_normal" -Operation {
        & $normalScript -ProjectRoot $ProjectRoot | Out-Null
    }

    $verdict = "SYSTEM_OTWARTY"
}
catch {
    $verdict = "SYSTEM_OTWARCIE_NIEPELNE"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    dry_run = [bool]$DryRun
    ml_perf_profile = $MlPerfProfile
    near_profit_perf_profile = $NearProfitPerfProfile
    verdict = $verdict
    action_count = $actions.Count
    failed_count = @($actions | Where-Object { $_.status -eq "error" }).Count
    actions = $actions.ToArray()
}

$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Otworz Pelny System")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- dry_run: {0}" -f $report.dry_run))
$lines.Add(("- ml_perf_profile: {0}" -f $report.ml_perf_profile))
$lines.Add(("- near_profit_perf_profile: {0}" -f $report.near_profit_perf_profile))
$lines.Add("")
$lines.Add("## Kroki")
$lines.Add("")
foreach ($action in $actions) {
    $lines.Add(("- [{0}] {1}: {2}" -f $action.status, $action.step, $action.message))
}
$lines -join [Environment]::NewLine | Set-Content -LiteralPath $reportMdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 6
