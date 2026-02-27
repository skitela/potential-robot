param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspace = (Resolve-Path $Root).Path
$obsRoot = Join-Path $workspace "OBSERVERS_IMPLEMENTATION_CANDIDATE"
$toolsDir = Join-Path $obsRoot "tools"

function Stop-ByNeedle {
    param([string]$Needle)
    $procs = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match "python" -and $_.CommandLine -and $_.CommandLine -match [regex]::Escape($Needle)
    })
    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            Write-Output ("stopped " + $Needle + " pid=" + $p.ProcessId)
        } catch {
            Write-Output ("stop_failed " + $Needle + " pid=" + $p.ProcessId + " err=" + $_.Exception.Message)
        }
    }
    if ($procs.Count -eq 0) {
        Write-Output ("not_running " + $Needle)
    }
}

Stop-ByNeedle -Needle "operator_console.py"
Stop-ByNeedle -Needle "operator_runtime_service.py"
