param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$IntervalMinutes = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$saveScript = Join-Path $ProjectRoot "RUN\SAVE_LOCAL_OPERATOR_SNAPSHOT.ps1"
if (-not (Test-Path -LiteralPath $saveScript)) {
    throw "Snapshot script not found: $saveScript"
}

$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        $_.CommandLine -like "*local_operator_archiver_wrapper_*"
    }

if ($existing) {
    Write-Host "Local operator archiver is already running."
    return
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $OutputRoot ("local_operator_archiver_{0}.log" -f $timestamp)
$wrapperPath = Join-Path $env:TEMP ("local_operator_archiver_wrapper_{0}.ps1" -f $timestamp)

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    while (`$true) {
        & '$saveScript' -ProjectRoot '$ProjectRoot' -OutputRoot '$OutputRoot' | Out-Null
        Start-Sleep -Seconds $($IntervalMinutes * 60)
    }
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

Write-Host "Local operator archiver started."
Write-Host "Log: $logPath"
