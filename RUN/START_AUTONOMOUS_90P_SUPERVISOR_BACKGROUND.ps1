param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$CycleSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$supervisorScript = Join-Path $ProjectRoot "RUN\RUN_AUTONOMOUS_90P_SUPERVISOR.ps1"
if (-not (Test-Path -LiteralPath $supervisorScript)) {
    throw "Supervisor script not found: $supervisorScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "autonomous_90p_supervisor_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "autonomous_90p_supervisor_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$supervisorScript' -ProjectRoot '$ProjectRoot' -CycleSeconds $CycleSeconds
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

Write-Host "Autonomous 90P supervisor started."
Write-Host "Log: $logPath"
