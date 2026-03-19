param(
    [switch]$ThrottleInteractiveApps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:changes = @()
$script:errors = @()

function Set-ProcessPriority {
    param(
        [System.Diagnostics.Process[]]$Processes,
        [System.Diagnostics.ProcessPriorityClass]$Priority,
        [string]$Reason
    )

    foreach ($proc in $Processes) {
        if ($null -eq $proc) {
            continue
        }

        try {
            if ($proc.HasExited) {
                continue
            }

            $before = $proc.PriorityClass
            if ($before -ne $Priority) {
                $proc.PriorityClass = $Priority
            }

            $script:changes += [pscustomobject]@{
                process = $proc.ProcessName
                id = $proc.Id
                before = [string]$before
                after = [string]$proc.PriorityClass
                reason = $Reason
            }
        }
        catch {
            $script:errors += [pscustomobject]@{
                process = $proc.ProcessName
                id = $proc.Id
                priority = [string]$Priority
                reason = $Reason
                error = $_.Exception.Message
            }
        }
    }
}

$labProcessNames = @("terminal64", "metatester64", "qdmcli", "python")
Set-ProcessPriority -Processes (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in $labProcessNames }) -Priority AboveNormal -Reason "lab-core"

$wrapperPatterns = @(
    "fx_mt5_batch_wrapper_",
    "fx_qdm_pipeline_wrapper_",
    "refresh_and_train_ml_wrapper_",
    "qdm_focus_sync_wrapper_",
    "qdm_export_after_sync_wrapper_",
    "mt5_retest_queue_wrapper_",
    "microbot_retest_after_idle_wrapper_",
    "autonomous_90p_supervisor_wrapper_",
    "local_operator_archiver_"
)

$wrapperIds = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $commandLine = $_.CommandLine
        $_.Name -eq "powershell.exe" -and
        ($wrapperPatterns | Where-Object { $commandLine -like "*$_*" } | Measure-Object).Count -gt 0
    } |
    Select-Object -ExpandProperty ProcessId

if ($wrapperIds) {
    $wrapperProcesses = foreach ($wrapperId in $wrapperIds) {
        Get-Process -Id $wrapperId -ErrorAction SilentlyContinue
    }
    Set-ProcessPriority -Processes $wrapperProcesses -Priority AboveNormal -Reason "lab-wrapper"
}

if ($ThrottleInteractiveApps) {
    $interactiveNames = @("Code", "chrome")
    Set-ProcessPriority -Processes (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in $interactiveNames }) -Priority Normal -Reason "interactive-throttle"
}

[pscustomobject]@{
    changed = $script:changes
    errors = $script:errors
}
