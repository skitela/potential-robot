param(
    [string]$TaskName = "OANDA_MT5_WEEKLY_BACKUP"
)

$ErrorActionPreference = "Stop"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "WEEKLY_BACKUP_TASK_UNREGISTERED"
    Write-Host "TaskName: $TaskName"
} else {
    Write-Host "WEEKLY_BACKUP_TASK_NOT_FOUND"
    Write-Host "TaskName: $TaskName"
}

