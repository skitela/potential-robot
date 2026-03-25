param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$CycleSeconds = 300,
    [int]$HeavySweepEveryCycles = 36,
    [switch]$ApplySafeAutoHeal,
    [switch]$StopExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$supervisorScript = Join-Path $ProjectRoot "RUN\RUN_AUDIT_SUPERVISOR.ps1"
if (-not (Test-Path -LiteralPath $supervisorScript)) {
    throw "Audit supervisor script not found: $supervisorScript"
}

$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
        $_.CommandLine -like "*audit_supervisor_wrapper_*"
    }

if ($StopExisting -and $existing) {
    foreach ($proc in @($existing)) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
        }
        catch {
        }
    }

    Start-Sleep -Seconds 1
    $existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "powershell.exe" -and
            -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
            $_.CommandLine -like "*audit_supervisor_wrapper_*"
        }
}

if ($existing) {
    Write-Host "Audit supervisor is already running."
    return
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot ("audit_supervisor_{0}.log" -f $timestamp)
$wrapperPath = Join-Path $env:TEMP ("audit_supervisor_wrapper_{0}.ps1" -f $timestamp)
$autoHealFlag = if ($PSBoundParameters.ContainsKey("ApplySafeAutoHeal")) {
    if ($ApplySafeAutoHeal) { "-ApplySafeAutoHeal" } else { "" }
}
else {
    "-ApplySafeAutoHeal"
}

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$supervisorScript' -ProjectRoot '$ProjectRoot' -Mode Loop -CycleSeconds $CycleSeconds -HeavySweepEveryCycles $HeavySweepEveryCycles $autoHealFlag
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

Write-Host "Audit supervisor started."
Write-Host "Log: $logPath"
