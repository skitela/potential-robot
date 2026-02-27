param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$PollSec = 5,
    [int]$OpsEverySec = 60,
    [int]$GuardianEverySec = 300,
    [int]$RdRecEverySec = 1800,
    [switch]$EnablePopups
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspace = (Resolve-Path $Root).Path
$obsRoot = Join-Path $workspace "OBSERVERS_IMPLEMENTATION_CANDIDATE"
$toolsDir = Join-Path $obsRoot "tools"
$jobsDir = Join-Path $obsRoot "outputs\operator"
New-Item -ItemType Directory -Force -Path $jobsDir | Out-Null

$runtimeScript = Join-Path $toolsDir "operator_runtime_service.py"
$consoleScript = Join-Path $toolsDir "operator_console.py"
if (-not (Test-Path $runtimeScript)) { throw "Missing runtime script: $runtimeScript" }
if (-not (Test-Path $consoleScript)) { throw "Missing console script: $consoleScript" }

function Resolve-PythonExe {
    $default = "python"
    try {
        $resolved = (& $default -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1).Trim()
        if (-not [string]::IsNullOrWhiteSpace($resolved) -and (Test-Path $resolved)) {
            return $resolved
        }
    } catch {
        # fallback below
    }
    return $default
}

$pythonExe = Resolve-PythonExe

function Find-ProcByNeedle {
    param([string]$Needle)
    @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match "python" -and $_.CommandLine -and $_.CommandLine -match [regex]::Escape($Needle)
    })
}

$existing = Find-ProcByNeedle -Needle "operator_runtime_service.py"
if ($existing.Count -eq 0) {
    $argList = @(
        $runtimeScript,
        "--poll-sec", ([string]$PollSec),
        "--ops-every-sec", ([string]$OpsEverySec),
        "--guardian-every-sec", ([string]$GuardianEverySec),
        "--rd-rec-every-sec", ([string]$RdRecEverySec)
    )
    if ($EnablePopups) {
        $argList += "--popup-enabled"
    }
    $outLog = Join-Path $jobsDir ("runtime_service_" + (Get-Date -Format "yyyyMMdd_HHmmss") + "_out.log")
    $errLog = Join-Path $jobsDir ("runtime_service_" + (Get-Date -Format "yyyyMMdd_HHmmss") + "_err.log")
    $p = Start-Process -FilePath $pythonExe -ArgumentList $argList -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    Write-Output ("runtime_service_started_pid=" + $p.Id)
} else {
    Write-Output ("runtime_service_already_running_pid=" + $existing[0].ProcessId)
}

Write-Output "starting_operator_console..."
& $pythonExe $consoleScript
