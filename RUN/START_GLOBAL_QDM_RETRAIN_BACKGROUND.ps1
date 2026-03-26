param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$LogRoot = "C:\TRADING_DATA\RESEARCH\reports",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "Light"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$trainerScript = Join-Path $ProjectRoot "RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1"
$refreshProfileScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_VISIBILITY_REFRESH_PROFILE.ps1"
$retrainAuditScript = Join-Path $ProjectRoot "RUN\BUILD_GLOBAL_QDM_RETRAIN_AUDIT.ps1"

foreach ($path in @($trainerScript, $refreshProfileScript, $retrainAuditScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "global_qdm_retrain_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "global_qdm_retrain_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$trainerScript' -PerfProfile '$PerfProfile'
    & '$refreshProfileScript' -ProjectRoot '$ProjectRoot' -ResearchRoot '$ResearchRoot' | Out-Null
    & '$retrainAuditScript' -ProjectRoot '$ProjectRoot' -ResearchRoot '$ResearchRoot' | Out-Null
}
finally {
    Stop-Transcript
}
"@

Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8

$proc = Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperPath) `
    -WorkingDirectory $ProjectRoot `
    -WindowStyle Hidden `
    -PassThru

try {
    $proc.PriorityClass = "AboveNormal"
}
catch {
}

Write-Host "Background global QDM retrain started."
Write-Host "Log: $logPath"
Write-Host "Perf profile: $PerfProfile"
