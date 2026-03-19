param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_weakest_pack.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$syncScript = Join-Path $ProjectRoot "RUN\SYNC_QDM_FOCUS_PACK.ps1"
$buildProfileScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_WEAKEST_PROFILE.ps1"
if (-not (Test-Path -LiteralPath $syncScript)) {
    throw "QDM sync script not found: $syncScript"
}
if (-not (Test-Path -LiteralPath $buildProfileScript)) {
    throw "QDM weakest profile builder not found: $buildProfileScript"
}

& $buildProfileScript -ProjectRoot $ProjectRoot -OutputPath $ProfilePath | Out-Null
if (-not (Test-Path -LiteralPath $ProfilePath)) {
    throw "QDM weakest profile was not generated: $ProfilePath"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "qdm_weakest_sync_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "qdm_weakest_sync_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$syncScript' -ProfilePath '$ProfilePath'
}
finally {
    Stop-Transcript
}
"@

Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8

$proc = Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperPath) `
    -WorkingDirectory $ProjectRoot `
    -PassThru

try {
    $proc.PriorityClass = "AboveNormal"
}
catch {
}

Write-Host "Background QDM weakest sync started."
Write-Host "Log: $logPath"
