param(
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$Profile = "ConcurrentLab",
    [string]$TempRoot = "C:\TRADING_DATA\RESEARCH\perf",
    [int]$LogicalProcessorsOverride = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$tmpPath = Join-Path $TempRoot "tmp"
$cachePath = Join-Path $TempRoot "cache"
$joblibPath = Join-Path $TempRoot "joblib"
$pycachePath = Join-Path $TempRoot "pycache"

@($tmpPath, $cachePath, $joblibPath, $pycachePath) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

$logicalProcessors = if ($LogicalProcessorsOverride -gt 0) {
    $LogicalProcessorsOverride
}
else {
    (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
}

if (-not $logicalProcessors -or $logicalProcessors -lt 1) {
    $logicalProcessors = 4
}

switch ($Profile) {
    "ConcurrentLab" {
        $threads = [Math]::Min(5, [Math]::Max(4, $logicalProcessors - 7))
    }
    "OfflineMax" {
        $threads = [Math]::Max(2, $logicalProcessors - 2)
    }
    "Light" {
        $threads = [Math]::Max(2, [Math]::Floor($logicalProcessors / 3))
    }
}

$envMap = [ordered]@{
    OMP_NUM_THREADS        = $threads
    OPENBLAS_NUM_THREADS   = $threads
    MKL_NUM_THREADS        = $threads
    NUMEXPR_NUM_THREADS    = $threads
    VECLIB_MAXIMUM_THREADS = $threads
    POLARS_MAX_THREADS     = $threads
    OMP_WAIT_POLICY        = "PASSIVE"
    JOBLIB_TEMP_FOLDER     = $joblibPath
    PYTHONPYCACHEPREFIX    = $pycachePath
    TMP                    = $tmpPath
    TEMP                   = $tmpPath
    TMPDIR                 = $tmpPath
    MICROBOT_RESEARCH_TMP  = $tmpPath
    MICROBOT_RESEARCH_CACHE = $cachePath
}

foreach ($entry in $envMap.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, "Process")
}

[pscustomobject]@{
    profile = $Profile
    logical_processors = $logicalProcessors
    worker_threads = $threads
    temp_root = $TempRoot
    tmp = $tmpPath
    cache = $cachePath
    joblib = $joblibPath
    pycache = $pycachePath
}
