param(
    [string]$LegacyRoot = "C:\OANDA_MT5_SYSTEM",
    [string]$UserStartupFolder = "",
    [switch]$StopRunningLegacyProcesses
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($UserStartupFolder)) {
    $UserStartupFolder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
}

$startupLinkName = "OANDA Operator Panel.lnk"
$startupLinkPath = Join-Path $UserStartupFolder $startupLinkName
$disabledDir = Join-Path $LegacyRoot "STATE\disabled_autostart"
$reportDir = Join-Path $LegacyRoot "EVIDENCE\autostart"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportJson = Join-Path $reportDir ("legacy_autostart_disable_{0}.json" -f $timestamp)
$reportMd = Join-Path $reportDir ("legacy_autostart_disable_{0}.md" -f $timestamp)
$latestJson = Join-Path $reportDir "legacy_autostart_disable_latest.json"
$latestMd = Join-Path $reportDir "legacy_autostart_disable_latest.md"

$legacyTasks = @(
    "OANDA_MT5_FX_NEXT_WINDOW_AUDIT_DAILY_USER",
    "OANDA_MT5_LAB_DAILY",
    "OANDA_MT5_LAB_INSIGHTS_Q3H",
    "OANDA_MT5_LATENCY_AUDIT_DAILY_USER",
    "OANDA_MT5_NIGHTLY_TESTBOOK_USER",
    "OANDA_MT5_STAGE1_LEARNING_DAILY_USER",
    "OANDA_MT5_STAGE1_SHADOW_PLUS_HOURLY_USER",
    "OANDA_MT5_WEEKLY_BACKUP"
)

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Ensure-Dir -Path $disabledDir
Ensure-Dir -Path $reportDir

$result = [ordered]@{
    timestamp = (Get-Date).ToString("s")
    legacy_root = $LegacyRoot
    startup_link = $startupLinkPath
    startup_link_action = ""
    startup_link_destination = ""
    tasks = @()
    stopped_processes = @()
}

if (Test-Path -LiteralPath $startupLinkPath) {
    $targetPath = Join-Path $disabledDir $startupLinkName
    if (Test-Path -LiteralPath $targetPath) {
        $targetPath = Join-Path $disabledDir ("OANDA Operator Panel_{0}.lnk" -f $timestamp)
    }
    Move-Item -LiteralPath $startupLinkPath -Destination $targetPath -Force
    $result.startup_link_action = "moved_to_disabled_autostart"
    $result.startup_link_destination = $targetPath
}
else {
    $result.startup_link_action = "not_present"
}

foreach ($taskName in $legacyTasks) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        $result.tasks += [pscustomobject]@{
            task_name = $taskName
            exists = $false
            action = "not_found"
            prior_state = ""
            final_state = ""
        }
        continue
    }

    $priorState = [string]$task.State
    if ($task.State -eq "Running") {
        try {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
        }
        catch {
        }
    }

    Disable-ScheduledTask -TaskName $taskName | Out-Null
    $finalTask = Get-ScheduledTask -TaskName $taskName

    $result.tasks += [pscustomobject]@{
        task_name = $taskName
        exists = $true
        action = "disabled"
        prior_state = $priorState
        final_state = [string]$finalTask.State
    }
}

if ($StopRunningLegacyProcesses) {
    $legacyProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.CommandLine -like "*C:\OANDA_MT5_SYSTEM\TOOLS\START_OPERATOR_PANEL.ps1*") -or
            ($_.CommandLine -like "*C:\OANDA_MT5_SYSTEM\TOOLS\run_*") -or
            ($_.CommandLine -like "*C:\OANDA_MT5_SYSTEM\TOOLS\fx_runtime_audit*")
        }

    foreach ($proc in $legacyProcesses) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            $result.stopped_processes += [pscustomobject]@{
                pid = $proc.ProcessId
                name = $proc.Name
                command_line = $proc.CommandLine
                action = "stopped"
            }
        }
        catch {
            $result.stopped_processes += [pscustomobject]@{
                pid = $proc.ProcessId
                name = $proc.Name
                command_line = $proc.CommandLine
                action = "stop_failed"
            }
        }
    }
}

$json = $result | ConvertTo-Json -Depth 6
$json | Set-Content -LiteralPath $reportJson -Encoding UTF8
$json | Set-Content -LiteralPath $latestJson -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Legacy OANDA MT5 Autostart Disable")
$lines.Add("")
$lines.Add(("Timestamp: {0}" -f $result.timestamp))
$lines.Add(("Legacy root: {0}" -f $LegacyRoot))
$lines.Add("")
$lines.Add("## Startup Link")
$lines.Add("")
$lines.Add(("- action: {0}" -f $result.startup_link_action))
if (-not [string]::IsNullOrWhiteSpace([string]$result.startup_link_destination)) {
    $lines.Add(("- destination: {0}" -f $result.startup_link_destination))
}
$lines.Add("")
$lines.Add("## Scheduled Tasks")
$lines.Add("")
foreach ($taskResult in $result.tasks) {
    $lines.Add(("- {0} -> {1} (before: {2}, after: {3})" -f
        $taskResult.task_name, $taskResult.action, $taskResult.prior_state, $taskResult.final_state))
}
$lines.Add("")
if ($result.stopped_processes.Count -gt 0) {
    $lines.Add("## Stopped Processes")
    $lines.Add("")
    foreach ($proc in $result.stopped_processes) {
        $lines.Add(("- {0} #{1} -> {2}" -f $proc.name, $proc.pid, $proc.action))
    }
    $lines.Add("")
}

$md = $lines -join "`r`n"
$md | Set-Content -LiteralPath $reportMd -Encoding UTF8
$md | Set-Content -LiteralPath $latestMd -Encoding UTF8

$result
