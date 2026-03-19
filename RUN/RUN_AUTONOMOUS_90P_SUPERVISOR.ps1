param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$CycleSeconds = 300,
    [int]$MaxCycles = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$priorityScript = Join-Path $ProjectRoot "RUN\BUILD_TUNING_PRIORITY_REPORT.ps1"
$snapshotScript = Join-Path $ProjectRoot "RUN\SAVE_LOCAL_OPERATOR_SNAPSHOT.ps1"
$archiverScript = Join-Path $ProjectRoot "RUN\START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1"
$weakestBatchScript = Join-Path $ProjectRoot "RUN\START_WEAKEST_MT5_BATCH_BACKGROUND.ps1"
$qdmWeakestScript = Join-Path $ProjectRoot "RUN\START_QDM_WEAKEST_SYNC_BACKGROUND.ps1"
$mlScript = Join-Path $ProjectRoot "RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1"
$perfScript = Join-Path $ProjectRoot "RUN\APPLY_WORKSTATION_PERF_TUNING.ps1"
$statusDir = Join-Path $ProjectRoot "EVIDENCE\OPS"
$secondaryMt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe"

foreach ($path in @(
    $priorityScript,
    $snapshotScript,
    $archiverScript,
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

function Get-Mt5LabActivityCount {
    param(
        [string]$TerminalExePath
    )

    $wrapperCount = Get-WrapperCount -Pattern "*weakest_mt5_batch_wrapper_*"
    $wrapperCount += Get-WrapperCount -Pattern "*usdchf_fix_retest_*"

    $secondaryTerminalCount = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "terminal64.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                $_.ExecutablePath -eq $TerminalExePath
            }
    ).Count

    $metaTesterCount = @(Get-Process metatester64 -ErrorAction SilentlyContinue).Count

    return ($wrapperCount + $secondaryTerminalCount + $metaTesterCount)
}

function Write-SupervisorStatus {
    param(
        [int]$Cycle,
        [hashtable]$Actions
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

    $status = [ordered]@{
        generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        cycle = $Cycle
        actions = $Actions
        processes = $processes
        top_priority = $priorityHead
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
    ($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
}

& $perfScript -ThrottleInteractiveApps -MlPerfProfile "ConcurrentLab" | Out-Host

$cycle = 0
while ($true) {
    $cycle++

    $actions = [ordered]@{}

    & $priorityScript | Out-Null
    $actions["priority_report"] = "rebuilt"

    & $snapshotScript | Out-Null
    $actions["snapshot"] = "saved"

    $actions["archiver"] = Ensure-BackgroundTask `
        -Label "archiver" `
        -IsRunning { (Get-WrapperCount -Pattern "*local_operator_archiver_*") -gt 0 } `
        -StarterPath $archiverScript

    $actions["qdm"] = Ensure-BackgroundTask `
        -Label "qdm" `
        -IsRunning { (Get-Process -Name qdmcli -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0 } `
        -StarterPath $qdmWeakestScript

    $actions["ml"] = Ensure-BackgroundTask `
        -Label "ml" `
        -IsRunning { (Get-WrapperCount -Pattern "*refresh_and_train_ml_wrapper_*") -gt 0 } `
        -StarterPath $mlScript

    $actions["weakest_mt5"] = Ensure-BackgroundTask `
        -Label "weakest_mt5" `
        -IsRunning { (Get-Mt5LabActivityCount -TerminalExePath $secondaryMt5Exe) -gt 0 } `
        -StarterPath $weakestBatchScript

    Write-SupervisorStatus -Cycle $cycle -Actions $actions

    if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) {
        break
    }

    Start-Sleep -Seconds $CycleSeconds
}
