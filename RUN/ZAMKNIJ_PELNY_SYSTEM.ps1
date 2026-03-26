param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$reportPath = Join-Path $opsRoot "system_close_latest.json"
$reportMdPath = Join-Path $opsRoot "system_close_latest.md"
$haltScript = Join-Path $ProjectRoot "RUN\ZATRZYMAJ_SYSTEM.ps1"
$snapshotScript = Join-Path $ProjectRoot "RUN\SAVE_LOCAL_OPERATOR_SNAPSHOT.ps1"

foreach ($path in @($haltScript, $snapshotScript)) {
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
        $result = & $Operation
        $message = if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result)) { "ok" } else { [string]$result }
        Add-ActionResult -Step $Step -Status "ok" -Message $message
    }
    catch {
        Add-ActionResult -Step $Step -Status "error" -Message $_.Exception.Message
        throw
    }
}

function Get-CimProcessesByCommandLinePatterns {
    param([string[]]$Patterns)

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $row = $_
                if ($row.Name -ne "powershell.exe" -or [string]::IsNullOrWhiteSpace($row.CommandLine)) {
                    return $false
                }

                foreach ($pattern in $Patterns) {
                    if ($row.CommandLine -like $pattern) {
                        return $true
                    }
                }

                return $false
            }
    )
}

function Stop-CimProcessRows {
    param(
        [object[]]$Rows,
        [string]$Label
    )

    if ($Rows.Count -le 0) {
        return "$Label:0"
    }

    $stopped = 0
    foreach ($row in $Rows) {
        try {
            Stop-Process -Id $row.ProcessId -Force -ErrorAction Stop
            $stopped++
        }
        catch {
        }
    }

    return ("{0}:{1}" -f $Label, $stopped)
}

function Get-ProjectPythonRows {
    param([string]$ProjectRootPath)

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -eq "python.exe" -or $_.Name -eq "pythonw.exe") -and
                (
                    ($_.ExecutablePath -eq "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe") -or
                    (
                        -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                        (
                            $_.CommandLine -like "*$ProjectRootPath*" -or
                            $_.CommandLine -like "*C:\\TRADING_DATA\\RESEARCH*"
                        )
                    )
                )
            }
    )
}

function Get-Mt5RuntimeRows {
    $roots = @(
        "C:\Program Files\OANDA TMS MT5 Terminal",
        "C:\Program Files\MetaTrader 5",
        "C:\TRADING_TOOLS\MT5_NEAR_PROFIT_LAB"
    ) | ForEach-Object { ([System.IO.Path]::GetFullPath($_)).TrimEnd('\').ToLowerInvariant() + "\" }

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $row = $_
                if ($row.Name -notin @("terminal64.exe", "metatester64.exe", "metaeditor64.exe")) {
                    return $false
                }
                if ([string]::IsNullOrWhiteSpace($row.ExecutablePath)) {
                    return $false
                }

                $fullPath = [System.IO.Path]::GetFullPath($row.ExecutablePath).ToLowerInvariant()
                return @($roots | Where-Object { $fullPath.StartsWith($_) }).Count -gt 0
            }
    )
}

function Stop-Mt5RuntimeRows {
    param([object[]]$Rows)

    if ($Rows.Count -le 0) {
        return "mt5_runtime:0"
    }

    $graceful = 0
    $forced = 0

    foreach ($row in $Rows | Where-Object { $_.Name -in @("terminal64.exe", "metaeditor64.exe") }) {
        try {
            $proc = Get-Process -Id $row.ProcessId -ErrorAction Stop
            if ($proc.CloseMainWindow()) {
                $graceful++
            }
        }
        catch {
        }
    }

    Start-Sleep -Seconds 8

    $remainingIds = @($Rows | Select-Object -ExpandProperty ProcessId)
    foreach ($id in $remainingIds) {
        try {
            $proc = Get-Process -Id $id -ErrorAction Stop
            Stop-Process -Id $id -Force -ErrorAction Stop
            $forced++
        }
        catch {
        }
    }

    return ("mt5_runtime:graceful={0};forced={1}" -f $graceful, $forced)
}

try {
    Invoke-Step -Step "snapshot_before_stop" -Operation {
        & $snapshotScript -ProjectRoot $ProjectRoot -OutputRoot $opsRoot | Out-Null
        "saved"
    }

    Invoke-Step -Step "set_halt" -Operation {
        & $haltScript -ProjectRoot $ProjectRoot | Out-Null
        "halt_set"
    }

    Invoke-Step -Step "halt_settle_wait" -Operation {
        Start-Sleep -Seconds 3
        "waited_3s"
    }

    $supervisorPatterns = @(
        "*audit_supervisor_wrapper_*",
        "*autonomous_90p_supervisor_wrapper_*"
    )
    Invoke-Step -Step "stop_supervisors" -Operation {
        Stop-CimProcessRows -Rows (Get-CimProcessesByCommandLinePatterns -Patterns $supervisorPatterns) -Label "supervisors"
    }

    $workerPatterns = @(
        "*local_operator_archiver_wrapper_*",
        "*mt5_tester_status_watcher_wrapper_*",
        "*mt5_risk_popup_guard_wrapper_*",
        "*refresh_and_train_ml_wrapper_*",
        "*qdm_missing_supported_sync_wrapper_*",
        "*weakest_mt5_batch_wrapper_*",
        "*mt5_retest_queue_wrapper_*",
        "*microbot_retest_after_idle_wrapper_*",
        "*near_profit_optimization_after_idle_wrapper_*",
        "*near_profit_mt5_risk_popup_guard_wrapper_*",
        "*qdm_weakest_sync_wrapper_*"
    )
    Invoke-Step -Step "stop_worker_wrappers" -Operation {
        Stop-CimProcessRows -Rows (Get-CimProcessesByCommandLinePatterns -Patterns $workerPatterns) -Label "workers"
    }

    Invoke-Step -Step "stop_python_workers" -Operation {
        Stop-CimProcessRows -Rows (Get-ProjectPythonRows -ProjectRootPath $ProjectRoot) -Label "python"
    }

    Invoke-Step -Step "stop_qdmcli" -Operation {
        $rows = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq "qdmcli.exe" }
        )
        Stop-CimProcessRows -Rows $rows -Label "qdmcli"
    }

    Invoke-Step -Step "stop_mt5_runtime" -Operation {
        Stop-Mt5RuntimeRows -Rows (Get-Mt5RuntimeRows)
    }

    $verdict = "SYSTEM_ZAMKNIETY"
}
catch {
    $verdict = "SYSTEM_ZAMKNIECIE_NIEPELNE"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    dry_run = [bool]$DryRun
    verdict = $verdict
    action_count = $actions.Count
    failed_count = @($actions | Where-Object { $_.status -eq "error" }).Count
    actions = $actions.ToArray()
}

$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Zamknij Pelny System")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- dry_run: {0}" -f $report.dry_run))
$lines.Add("")
$lines.Add("## Kroki")
$lines.Add("")
foreach ($action in $actions) {
    $lines.Add(("- [{0}] {1}: {2}" -f $action.status, $action.step, $action.message))
}
$lines -join [Environment]::NewLine | Set-Content -LiteralPath $reportMdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 6
