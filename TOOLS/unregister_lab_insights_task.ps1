param(
    [string]$TaskName = "OANDA_MT5_LAB_INSIGHTS_Q3H"
)

$ErrorActionPreference = "Stop"

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "LAB_INSIGHTS_TASK_UNREGISTERED"
    Write-Host "TaskName: $TaskName"
} else {
    Write-Host "LAB_INSIGHTS_TASK_NOT_FOUND"
    Write-Host "TaskName: $TaskName"
}
