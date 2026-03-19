param(
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$NotebookRoot = "C:\TRADING_DATA\RESEARCH\notebooks"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pythonExe = Join-Path $EnvRoot "Scripts\python.exe"
if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Research python not found: $pythonExe"
}

New-Item -ItemType Directory -Force -Path $NotebookRoot | Out-Null

Start-Process -FilePath $pythonExe -ArgumentList @("-m","jupyterlab","--notebook-dir",$NotebookRoot) -WorkingDirectory $NotebookRoot
