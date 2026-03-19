param(
    [switch]$ThrottleInteractiveApps,
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$MlPerfProfile = "ConcurrentLab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$currentPlan = powercfg /GETACTIVESCHEME
if ($currentPlan -notlike "*$highPerfGuid*") {
    powercfg /SETACTIVE $highPerfGuid | Out-Null
    $currentPlan = powercfg /GETACTIVESCHEME
}

$perfRoot = "C:\TRADING_DATA\RESEARCH\perf"
$tmpPath = Join-Path $perfRoot "tmp"
$cachePath = Join-Path $perfRoot "cache"
$joblibPath = Join-Path $perfRoot "joblib"
$pycachePath = Join-Path $perfRoot "pycache"

@($perfRoot, $tmpPath, $cachePath, $joblibPath, $pycachePath) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

[Environment]::SetEnvironmentVariable("MICROBOT_RESEARCH_TMP", $tmpPath, "User")
[Environment]::SetEnvironmentVariable("MICROBOT_RESEARCH_CACHE", $cachePath, "User")
[Environment]::SetEnvironmentVariable("MICROBOT_RESEARCH_JOBLIB_TEMP", $joblibPath, "User")
[Environment]::SetEnvironmentVariable("MICROBOT_RESEARCH_PYCACHE", $pycachePath, "User")

$pageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | Select-Object -First 1
$pageFileWarning = $null
if ($pageFile -and $pageFile.AllocatedBaseSize -lt 8192) {
    $pageFileWarning = "Pagefile is only $($pageFile.AllocatedBaseSize) MB. This is safe for current work, but large parallel labs may benefit from a larger or system-managed pagefile on C: later."
}

$priorityScript = Join-Path $PSScriptRoot "APPLY_LAB_PROCESS_PRIORITIES.ps1"
$priorityResult = & $priorityScript -ThrottleInteractiveApps:$ThrottleInteractiveApps

$envScript = Join-Path $PSScriptRoot "SET_MICROBOT_RESEARCH_PERF_ENV.ps1"
$envResult = & $envScript -Profile $MlPerfProfile

[pscustomobject]@{
    power_plan = $currentPlan
    perf_root = $perfRoot
    ml_profile = $MlPerfProfile
    pagefile_warning = $pageFileWarning
    env = $envResult
    priority = $priorityResult
}
