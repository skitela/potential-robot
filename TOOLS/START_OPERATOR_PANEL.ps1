param(
    [string]$Root = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

$panelScript = Join-Path $Root "TOOLS\OANDA_OPERATOR_PANEL.py"
if (-not (Test-Path $panelScript)) {
    throw "Missing panel script: $panelScript"
}

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
Start-Process -FilePath $pythonExe -ArgumentList @($panelScript) -WorkingDirectory $Root | Out-Null
Write-Output "OPERATOR_PANEL_STARTED"

