param(
    [string]$TaskName = "OANDA_MT5_RUNTIME_WATCHDOG_USER"
)

$ErrorActionPreference = "Stop"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "RUNTIME_WATCHDOG_TASK_REMOVED: $TaskName"
} else {
    Write-Host "RUNTIME_WATCHDOG_TASK_NOT_FOUND: $TaskName"
}
