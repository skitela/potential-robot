param(
    [string]$TaskName = "OANDA_MT5_LAB_DAILY"
)

$ErrorActionPreference = "Stop"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "LAB_TASK_UNREGISTERED"
    Write-Host "TaskName: $TaskName"
} else {
    Write-Host "LAB_TASK_NOT_FOUND"
    Write-Host "TaskName: $TaskName"
}
