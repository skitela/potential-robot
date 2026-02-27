param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [switch]$EnablePopups
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspace = (Resolve-Path $Root).Path
$obsRoot = Join-Path $workspace "OBSERVERS_IMPLEMENTATION_CANDIDATE"
$toolsDir = Join-Path $obsRoot "tools"
$runtimeScript = Join-Path $toolsDir "operator_runtime_service.py"
$jobsDir = Join-Path $obsRoot "outputs\operator"

if (-not (Test-Path $runtimeScript)) { throw "Missing runtime script: $runtimeScript" }
New-Item -ItemType Directory -Force -Path $jobsDir | Out-Null

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

function Find-ProcByNeedle {
    param([string]$Needle)
    @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match "python" -and $_.CommandLine -and $_.CommandLine -match [regex]::Escape($Needle)
    })
}

$pythonExe = Resolve-PythonExe
$existing = Find-ProcByNeedle -Needle "operator_runtime_service.py"
if ($existing.Count -gt 0) {
    Write-Output ("runtime_service_already_running_pid=" + $existing[0].ProcessId)
    exit 0
}

$argList = @($runtimeScript, "--poll-sec", "5", "--ops-every-sec", "60", "--guardian-every-sec", "300", "--rd-rec-every-sec", "1800")
if ($EnablePopups) { $argList += "--popup-enabled" }

$outLog = Join-Path $jobsDir ("runtime_service_" + (Get-Date -Format "yyyyMMdd_HHmmss") + "_out.log")
$errLog = Join-Path $jobsDir ("runtime_service_" + (Get-Date -Format "yyyyMMdd_HHmmss") + "_err.log")
$p = Start-Process -FilePath $pythonExe -ArgumentList $argList -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
Write-Output ("runtime_service_started_pid=" + $p.Id)
exit 0

