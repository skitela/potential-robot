param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$CycleSeconds = 300,
    [int]$MaxCycles = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$priorityScript = Join-Path $ProjectRoot "RUN\BUILD_TUNING_PRIORITY_REPORT.ps1"
$qdmProfileScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_WEAKEST_PROFILE.ps1"
$mlHintsScript = Join-Path $ProjectRoot "RUN\BUILD_ML_TUNING_HINTS.ps1"
$profitTrackingScript = Join-Path $ProjectRoot "RUN\BUILD_PROFIT_TRACKING_REPORT.ps1"
$dailySystemReportScript = Join-Path $ProjectRoot "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1"
$paperLiveFeedbackScript = Join-Path $ProjectRoot "RUN\BUILD_CANONICAL_PAPER_LIVE_FEEDBACK.ps1"
$hostingReportScript = Join-Path $ProjectRoot "RUN\BUILD_MT5_HOSTING_DAILY_REPORT.ps1"
$trustButVerifyScript = Join-Path $ProjectRoot "RUN\BUILD_TRUST_BUT_VERIFY_AUDIT.ps1"
$snapshotScript = Join-Path $ProjectRoot "RUN\SAVE_LOCAL_OPERATOR_SNAPSHOT.ps1"
$fullStackAuditScript = Join-Path $ProjectRoot "RUN\BUILD_FULL_STACK_AUDIT.ps1"
$archiverScript = Join-Path $ProjectRoot "RUN\START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1"
$mt5WatcherScript = Join-Path $ProjectRoot "RUN\START_MT5_TESTER_STATUS_WATCHER_BACKGROUND.ps1"
$weakestBatchScript = Join-Path $ProjectRoot "RUN\START_WEAKEST_MT5_BATCH_BACKGROUND.ps1"
$qdmWeakestScript = Join-Path $ProjectRoot "RUN\START_QDM_WEAKEST_SYNC_BACKGROUND.ps1"
$mlScript = Join-Path $ProjectRoot "RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1"
$perfScript = Join-Path $ProjectRoot "RUN\APPLY_WORKSTATION_PERF_TUNING.ps1"
$statusDir = Join-Path $ProjectRoot "EVIDENCE\OPS"
$dailySystemReportPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\raport_dzienny_latest.json"
$secondaryMt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe"

foreach ($path in @(
    $priorityScript,
    $qdmProfileScript,
    $mlHintsScript,
    $profitTrackingScript,
    $dailySystemReportScript,
    $paperLiveFeedbackScript,
    $hostingReportScript,
    $trustButVerifyScript,
    $snapshotScript,
    $fullStackAuditScript,
    $archiverScript,
    $mt5WatcherScript,
    $weakestBatchScript,
    $qdmWeakestScript,
    $mlScript,
    $perfScript
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $statusDir | Out-Null

function Get-WrapperCount {
    param([string]$Pattern)
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like $Pattern
            }
    ).Count
}

function Ensure-BackgroundTask {
    param(
        [string]$Label,
        [scriptblock]$IsRunning,
        [string]$StarterPath
    )

    if (& $IsRunning) {
        return "already_running"
    }

    & $StarterPath | Out-Host
    return "started"
}

function Get-FileAgeSecondsOrMax {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int]::MaxValue
    }

    return [int][math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds)
}

function Invoke-SupervisorAction {
    param(
        [System.Collections.IDictionary]$Actions,
        [string]$Name,
        [scriptblock]$Operation
    )

    try {
        $result = & $Operation
        if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result)) {
            $Actions[$Name] = "ok"
        }
        else {
            $Actions[$Name] = [string]$result
        }
        return $true
    }
    catch {
        $message = $_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $message = (($message -replace '\s+', ' ').Trim())
        }
        else {
            $message = "unknown_error"
        }
        $Actions[$Name] = "failed: $message"
        return $false
    }
}

function Get-Mt5LabActivityCount {
    param(
        [string]$TerminalExePath
    )

    $wrapperCount = Get-WrapperCount -Pattern "*weakest_mt5_batch_wrapper_*"
    $wrapperCount += Get-WrapperCount -Pattern "*usdchf_fix_retest_*"
    $wrapperCount += Get-WrapperCount -Pattern "*silver_baseline_*"
    $wrapperCount += Get-WrapperCount -Pattern "*microbot_retest_after_idle_wrapper_*"
    $wrapperCount += Get-WrapperCount -Pattern "*mt5_retest_queue_wrapper_*"

    $secondaryTerminalCount = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "terminal64.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                ([System.IO.Path]::GetFullPath($_.ExecutablePath).ToLowerInvariant() -eq [System.IO.Path]::GetFullPath($TerminalExePath).ToLowerInvariant())
            }
    ).Count

    $metaTesterExePath = Join-Path (Split-Path -Parent $TerminalExePath) "metatester64.exe"
    $metaTesterCount = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "metatester64.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                ([System.IO.Path]::GetFullPath($_.ExecutablePath).ToLowerInvariant() -eq [System.IO.Path]::GetFullPath($metaTesterExePath).ToLowerInvariant())
            }
    ).Count

    return ($wrapperCount + $secondaryTerminalCount + $metaTesterCount)
}

function Write-SupervisorStatus {
    param(
        [int]$Cycle,
        [System.Collections.IDictionary]$Actions
    )

    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -in @("terminal64", "metatester64", "qdmcli", "python") } |
        Sort-Object ProcessName, Id |
        ForEach-Object {
            [pscustomobject]@{
                process = $_.ProcessName
                id = $_.Id
                priority = [string]$_.PriorityClass
                ram_mb = [math]::Round($_.WorkingSet64 / 1MB, 1)
            }
        }

    $priorityReportPath = Join-Path $statusDir "tuning_priority_latest.json"
    $priorityHead = @()
    if (Test-Path -LiteralPath $priorityReportPath) {
        $priorityReport = Get-Content -LiteralPath $priorityReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $priorityHead = @($priorityReport.ranked_instruments | Select-Object -First 6)
    }

    $mlHintsPath = Join-Path $statusDir "ml_tuning_hints_latest.json"
    $mlHintHead = @()
    if (Test-Path -LiteralPath $mlHintsPath) {
        $mlHints = Get-Content -LiteralPath $mlHintsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $mlHintHead = @($mlHints.items | Select-Object -First 4)
    }

    $qdmProfilePath = Join-Path $statusDir "qdm_weakest_profile_latest.json"
    $qdmHead = @()
    if (Test-Path -LiteralPath $qdmProfilePath) {
        $qdmProfile = Get-Content -LiteralPath $qdmProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $qdmHead = @($qdmProfile.included | Select-Object -First 4)
    }

    $trustButVerifyPath = Join-Path $statusDir "trust_but_verify_latest.json"
    $trustButVerify = $null
    if (Test-Path -LiteralPath $trustButVerifyPath) {
        $trustButVerify = Get-Content -LiteralPath $trustButVerifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $mt5QueuePath = Join-Path $statusDir "mt5_retest_queue_latest.json"
    $mt5Queue = $null
    if (Test-Path -LiteralPath $mt5QueuePath) {
        $mt5Queue = Get-Content -LiteralPath $mt5QueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $status = [ordered]@{
        generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        cycle = $Cycle
        actions = $Actions
        processes = $processes
        top_priority = $priorityHead
        top_ml_hints = $mlHintHead
        top_qdm_profile = $qdmHead
        trust_but_verify = $trustButVerify
        mt5_retest_queue = $mt5Queue
    }

    $jsonLatest = Join-Path $statusDir "autonomous_90p_latest.json"
    $mdLatest = Join-Path $statusDir "autonomous_90p_latest.md"
    $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Autonomous 90P Latest")
    $lines.Add("")
    $lines.Add(("- generated_at_local: {0}" -f $status.generated_at_local))
    $lines.Add(("- cycle: {0}" -f $Cycle))
    $lines.Add("")
    $lines.Add("## Actions")
    $lines.Add("")
    foreach ($key in $Actions.Keys | Sort-Object) {
        $lines.Add(("- {0}: {1}" -f $key, $Actions[$key]))
    }
    $lines.Add("")
    $lines.Add("## Processes")
    $lines.Add("")
    foreach ($proc in $processes) {
        $lines.Add(("- {0} #{1}: priority={2}, ram_mb={3}" -f $proc.process, $proc.id, $proc.priority, $proc.ram_mb))
    }
    $lines.Add("")
    $lines.Add("## Top Priority")
    $lines.Add("")
    foreach ($item in $priorityHead) {
        $lines.Add(("- #{0} {1}: score={2}, trust={3}, cost={4}, sample={5}, live_net_24h={6}, action={7}" -f
            $item.rank,
            $item.symbol_alias,
            $item.priority_score,
            $item.trust_state,
            $item.cost_state,
            $item.learning_sample_count,
            $item.live_net_24h,
            $item.recommended_action))
    }
    $lines.Add("")
    $lines.Add("## Top ML Hints")
    $lines.Add("")
    foreach ($item in $mlHintHead) {
        $firstHint = if (@($item.hints).Count -gt 0) { [string]$item.hints[0] } else { "none" }
        $lines.Add(("- #{0} {1}: ml_risk_score={2}, hint={3}" -f
            $item.rank,
            $item.symbol_alias,
            $item.ml_risk_score,
            $firstHint))
    }
    $lines.Add("")
    $lines.Add("## Top QDM Weakest Profile")
    $lines.Add("")
    foreach ($item in $qdmHead) {
        $lines.Add(("- #{0} {1}: qdm_symbol={2}, datasource={3}, export={4}" -f
            $item.rank,
            $item.symbol_alias,
            $item.qdm_symbol,
            $item.datasource,
            $item.mt5_export_name))
    }
    $lines.Add("")
    $lines.Add("## Trust But Verify")
    $lines.Add("")
    if ($null -ne $trustButVerify) {
        $lines.Add(("- verdict: {0}" -f $trustButVerify.verdict))
        $lines.Add(("- needs_manual_eye: {0}" -f $trustButVerify.needs_manual_eye))
        foreach ($finding in @($trustButVerify.findings | Select-Object -First 3)) {
            $lines.Add(("- [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message))
        }
    }
    else {
        $lines.Add("- trust-but-verify report not available")
    }
    $lines.Add("")
    $lines.Add("## MT5 Retest Queue")
    $lines.Add("")
    if ($null -ne $mt5Queue) {
        $lines.Add(("- state: {0}" -f $mt5Queue.state))
        $lines.Add(("- current_symbol: {0}" -f $mt5Queue.current_symbol))
        $completed = @($mt5Queue.completed)
        $pending = @($mt5Queue.pending)
        $lines.Add(("- completed: {0}" -f $(if ($completed.Count -gt 0) { $completed -join ", " } else { "none" })))
        $lines.Add(("- pending: {0}" -f $(if ($pending.Count -gt 0) { $pending -join ", " } else { "none" })))
    }
    else {
        $lines.Add("- queue status not available")
    }
    ($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
}

& $perfScript -ThrottleInteractiveApps -MlPerfProfile "ConcurrentLab" | Out-Host

$cycle = 0
while ($true) {
    $cycle++

    $actions = [ordered]@{}

    Invoke-SupervisorAction -Actions $actions -Name "perf_tuning" -Operation {
        & $perfScript -ThrottleInteractiveApps -MlPerfProfile "ConcurrentLab" | Out-Null
        "applied"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "daily_system_report" -Operation {
        $dailyReportAge = Get-FileAgeSecondsOrMax -Path $dailySystemReportPath
        if ($dailyReportAge -le 3600) {
            return ("fresh age_s={0}" -f $dailyReportAge)
        }

        & $dailySystemReportScript | Out-Null
        $dailyReportAge = Get-FileAgeSecondsOrMax -Path $dailySystemReportPath
        "rebuilt age_s=$dailyReportAge"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "paper_live_feedback" -Operation {
        & $paperLiveFeedbackScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "hosting_report" -Operation {
        & $hostingReportScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "priority_report" -Operation {
        & $priorityScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "qdm_profile" -Operation {
        & $qdmProfileScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "ml_hints" -Operation {
        & $mlHintsScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "profit_tracking" -Operation {
        & $profitTrackingScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "archiver" -Operation {
        Ensure-BackgroundTask `
            -Label "archiver" `
            -IsRunning { (Get-WrapperCount -Pattern "*local_operator_archiver_*") -gt 0 } `
            -StarterPath $archiverScript
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "mt5_status_watcher" -Operation {
        Ensure-BackgroundTask `
            -Label "mt5_status_watcher" `
            -IsRunning { (Get-WrapperCount -Pattern "*mt5_tester_status_watcher_wrapper_*") -gt 0 } `
            -StarterPath $mt5WatcherScript
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "qdm" -Operation {
        Ensure-BackgroundTask `
            -Label "qdm" `
            -IsRunning { (Get-Process -Name qdmcli -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0 } `
            -StarterPath $qdmWeakestScript
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "ml" -Operation {
        Ensure-BackgroundTask `
            -Label "ml" `
            -IsRunning { (Get-WrapperCount -Pattern "*refresh_and_train_ml_wrapper_*") -gt 0 } `
            -StarterPath $mlScript
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "weakest_mt5" -Operation {
        Ensure-BackgroundTask `
            -Label "weakest_mt5" `
            -IsRunning { (Get-Mt5LabActivityCount -TerminalExePath $secondaryMt5Exe) -gt 0 } `
            -StarterPath $weakestBatchScript
    } | Out-Null

    Write-SupervisorStatus -Cycle $cycle -Actions $actions

    Invoke-SupervisorAction -Actions $actions -Name "trust_but_verify" -Operation {
        & $trustButVerifyScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "full_stack_audit" -Operation {
        & $fullStackAuditScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "snapshot" -Operation {
        & $snapshotScript | Out-Null
        "saved"
    } | Out-Null

    Write-SupervisorStatus -Cycle $cycle -Actions $actions

    if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) {
        break
    }

    Start-Sleep -Seconds $CycleSeconds
}
