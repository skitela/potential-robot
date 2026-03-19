param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$refreshScript = Join-Path $ProjectRoot "RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1"
$openScript = Join-Path $ProjectRoot "RUN\OPEN_MICROBOT_RESEARCH_LAB.ps1"

if (-not (Test-Path -LiteralPath $refreshScript)) {
    throw "Refresh script not found: $refreshScript"
}
if (-not (Test-Path -LiteralPath $openScript)) {
    throw "Open lab script not found: $openScript"
}

& $refreshScript
& $openScript
