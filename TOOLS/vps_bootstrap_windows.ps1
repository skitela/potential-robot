param(
    [string]$ProjectRoot = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_LAB_DATA",
    [switch]$InstallPackages
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
    Write-Host ("[VPS_BOOTSTRAP] " + $msg)
}

function Ensure-Dir([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

Write-Step "start"

Ensure-Dir $ProjectRoot
Ensure-Dir $LabDataRoot
Ensure-Dir (Join-Path $LabDataRoot "reports")
Ensure-Dir (Join-Path $LabDataRoot "run")
Ensure-Dir (Join-Path $LabDataRoot "registry")
Ensure-Dir (Join-Path $LabDataRoot "data_curated")
Ensure-Dir (Join-Path $LabDataRoot "snapshots")

Write-Step "folders_ready project=$ProjectRoot lab=$LabDataRoot"

try {
    powercfg /S SCHEME_MIN | Out-Null
    Write-Step "power_plan=high_performance"
} catch {
    Write-Step "power_plan=UNCHANGED reason=$($_.Exception.Message)"
}

$runtimeLog = Join-Path $LabDataRoot "run\vps_bootstrap_runtime.json"
$runtime = [ordered]@{
    schema = "oanda.mt5.vps_bootstrap.v1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    project_root = $ProjectRoot
    lab_data_root = $LabDataRoot
    host = $env:COMPUTERNAME
    user = $env:USERNAME
    install_packages = [bool]$InstallPackages
    python = ""
    git = ""
}

if ($InstallPackages.IsPresent) {
    Write-Step "install_packages=ON"
    try {
        winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements | Out-Null
    } catch {
        Write-Step "python_install_warn=$($_.Exception.Message)"
    }
    try {
        winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements | Out-Null
    } catch {
        Write-Step "git_install_warn=$($_.Exception.Message)"
    }
}

try { $runtime.python = (& py -3.12 --version 2>$null) } catch {}
try { $runtime.git = (& git --version 2>$null) } catch {}

$runtime | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $runtimeLog
Write-Step "done runtime_log=$runtimeLog"

