param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$PollMs = 1200,
    [string]$PrimaryMt5DataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string[]]$AdditionalMt5DataDirs = @(
        "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$guardScript = Join-Path $ProjectRoot "TOOLS\mt5_risk_popup_guard.ps1"
if (-not (Test-Path -LiteralPath $guardScript)) {
    throw "MT5 risk popup guard script not found: $guardScript"
}

$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        $_.CommandLine -like "*mt5_risk_popup_guard_wrapper_*"
    }

if ($existing) {
    Write-Host "MT5 risk popup guard is already running."
    return
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $OutputRoot ("mt5_risk_popup_guard_{0}.log" -f $timestamp)
$wrapperPath = Join-Path $env:TEMP ("mt5_risk_popup_guard_wrapper_{0}.ps1" -f $timestamp)
$additionalLiteral = "@(" + ((@($AdditionalMt5DataDirs) | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ", ") + ")"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$guardScript' -Root '$ProjectRoot' -Mt5DataDir '$PrimaryMt5DataDir' -Mt5DataDirs $additionalLiteral -PollMs $PollMs
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

Write-Host "MT5 risk popup guard started."
Write-Host "Log: $logPath"
