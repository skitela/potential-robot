param(
    [switch]$IncludeOneDrive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$targets = @(
    "PhoneExperienceHost",
    "CrossDeviceService",
    "M365Copilot"
)

if ($IncludeOneDrive) {
    $targets += "OneDrive"
}

$results = foreach ($name in $targets) {
    $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        [pscustomobject]@{
            process = $name
            action = "not_running"
            freed_ram_mb = 0
        }
        continue
    }

    $freed = [math]::Round((($processes | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB), 1)
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        process = $name
        action = "stopped"
        freed_ram_mb = $freed
    }
}

$results
