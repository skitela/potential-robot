param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Profile = "OANDA_HYBRID_AUTO",
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [ValidateSet("ANY", "FX", "METAL", "INDEX", "CRYPTO", "EQUITY")]
    [string]$FocusGroup = "ANY",
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PythonExe {
    param([string]$RuntimeRoot)
    $candidates = @(
        "C:\OANDA_VENV\.venv\Scripts\python.exe",
        (Join-Path $RuntimeRoot ".venv\Scripts\python.exe"),
        "C:\Program Files\Python312\python.exe"
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [string]$candidate
        }
    }
    try {
        $py312 = (& py -3.12 -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace([string]$py312)) {
            $resolved = [string]$py312
            if (Test-Path -LiteralPath $resolved.Trim()) {
                return $resolved.Trim()
            }
        }
    } catch {
        # fallback below
    }
    return "python"
}

$rootResolved = (Resolve-Path -Path $Root).Path
$scriptPath = Join-Path $rootResolved "TOOLS\setup_mt5_hybrid_profile.py"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing script: $scriptPath"
}

$pythonExe = Get-PythonExe -RuntimeRoot $rootResolved
$args = @(
    "-B",
    $scriptPath,
    "--root", $rootResolved,
    "--profile", $Profile,
    "--mt5-exe", $Mt5Exe,
    "--focus-group", $FocusGroup
)
if ($NoLaunch) {
    $args += "--no-launch"
}

& $pythonExe @args
$rc = [int]$LASTEXITCODE
exit $rc
