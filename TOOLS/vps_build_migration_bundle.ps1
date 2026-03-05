param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$OutDir = "C:\OANDA_MT5_SYSTEM\EVIDENCE\vps_prep",
    [string]$BundleName = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Root not found: $Root"
}

if ([string]::IsNullOrWhiteSpace($BundleName)) {
    $BundleName = "oanda_mt5_bundle_" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ") + ".zip"
}

$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$stage = Join-Path $env:TEMP ("oanda_vps_bundle_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stage -Force | Out-Null

try {
    $includeDirs = @("BIN","TOOLS","RUN","CONFIG","MQL5","tests")
    foreach ($d in $includeDirs) {
        $src = Join-Path $Root $d
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $stage $d
        robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP /XF "*.pyc" "*.pyo" "*.log" "*.tmp" /XD "__pycache__" ".pytest_cache" ".git" "EVIDENCE" "DB" "venv" ".venv" | Out-Null
    }

    foreach ($f in @("requirements.txt","AGENTS.md","README.md")) {
        $src = Join-Path $Root $f
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $stage $f) -Force
        }
    }

    $zipPath = Join-Path $OutDir $BundleName
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "VPS_BUNDLE_DONE path=$zipPath"
}
finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

