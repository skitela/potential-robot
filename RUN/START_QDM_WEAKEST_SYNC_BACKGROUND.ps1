param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_only_pack_latest.csv",
    [int]$MinStartGapMinutes = 360
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$syncRunnerScript = Join-Path $ProjectRoot "RUN\RUN_QDM_MISSING_SUPPORTED_SYNC.ps1"
$buildProfileScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_MISSING_ONLY_PROFILE.ps1"
if (-not (Test-Path -LiteralPath $syncRunnerScript)) {
    throw "QDM sync runner not found: $syncRunnerScript"
}
if (-not (Test-Path -LiteralPath $buildProfileScript)) {
    throw "QDM missing-only profile builder not found: $buildProfileScript"
}

& $buildProfileScript -ProjectRoot $ProjectRoot -OutputPath $ProfilePath | Out-Null
if (-not (Test-Path -LiteralPath $ProfilePath)) {
    throw "QDM missing-only profile was not generated: $ProfilePath"
}

$profileRows = @(
    Import-Csv -LiteralPath $ProfilePath |
        Where-Object { [string]$_.enabled -eq "1" -and -not [string]::IsNullOrWhiteSpace([string]$_.symbol) }
)

if ($profileRows.Count -eq 0) {
    & $syncRunnerScript -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath | Out-Null
    Write-Host "Skipping QDM missing-only sync start: no missing symbols detected."
    return
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$latestWeakestLog = Get-ChildItem -LiteralPath $LogRoot -Filter "qdm_weakest_sync_*.log" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($latestWeakestLog) {
    $ageMinutes = ((Get-Date) - $latestWeakestLog.LastWriteTime).TotalMinutes
    if ($ageMinutes -lt $MinStartGapMinutes) {
        Write-Host ("Skipping QDM weakest sync start: latest run {0} is only {1:N1} minutes old (threshold {2} minutes)." -f
            $latestWeakestLog.Name,
            $ageMinutes,
            $MinStartGapMinutes)
        return
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "qdm_weakest_sync_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "qdm_weakest_sync_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$syncRunnerScript' -ProjectRoot '$ProjectRoot' -ProfilePath '$ProfilePath'
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
