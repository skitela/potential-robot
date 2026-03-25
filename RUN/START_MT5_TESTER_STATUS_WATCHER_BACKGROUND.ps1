param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$PollSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$watcherScript = Join-Path $ProjectRoot "RUN\WATCH_MT5_TESTER_STATUS.ps1"
if (-not (Test-Path -LiteralPath $watcherScript)) {
    throw "MT5 tester watcher script not found: $watcherScript"
}

$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        $_.CommandLine -like "*mt5_tester_status_watcher_wrapper_*"
    }

if ($existing) {
    Write-Host "MT5 tester status watcher is already running."
    return
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $OutputRoot ("mt5_tester_status_watcher_{0}.log" -f $timestamp)
$wrapperPath = Join-Path $env:TEMP ("mt5_tester_status_watcher_wrapper_{0}.ps1" -f $timestamp)

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$watcherScript' -ProjectRoot '$ProjectRoot' -OutputRoot '$OutputRoot' -PollSeconds $PollSeconds
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

Write-Host "MT5 tester status watcher started."
Write-Host "Log: $logPath"
