param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$CycleSeconds = 180,
    [switch]$StopExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$supervisorScript = Join-Path $ProjectRoot "RUN\RUN_AUTONOMOUS_90P_SUPERVISOR.ps1"
if (-not (Test-Path -LiteralPath $supervisorScript)) {
    throw "Supervisor script not found: $supervisorScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

if ($StopExisting) {
    $existing = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*autonomous_90p_supervisor_wrapper_*"
            }
    )

    foreach ($proc in $existing) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
        }
        catch {
        }
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "autonomous_90p_supervisor_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "autonomous_90p_supervisor_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
function Write-WrapperLog {
    param([string]`$Message)

    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath '$logPath' -Value ('[' + `$timestamp + '] ' + `$Message) -Encoding UTF8
}

Write-WrapperLog 'wrapper_start'
try {
    & '$supervisorScript' -ProjectRoot '$ProjectRoot' -CycleSeconds $CycleSeconds *>&1 | ForEach-Object {
        if (`$_ -is [System.Management.Automation.ErrorRecord]) {
            Write-WrapperLog ('stream_error=' + (`$_.ToString() -replace '\s+', ' ').Trim())
        }
        else {
            `$line = [string]`$_
            if (-not [string]::IsNullOrWhiteSpace(`$line)) {
                Write-WrapperLog (`$line)
            }
        }
    }
}
catch {
    Write-WrapperLog ('wrapper_exception=' + `$_.Exception.Message)
    if (`$null -ne `$_.InvocationInfo -and -not [string]::IsNullOrWhiteSpace(`$_.InvocationInfo.PositionMessage)) {
        Write-WrapperLog ('wrapper_position=' + ((`$_.InvocationInfo.PositionMessage -replace '\s+', ' ').Trim()))
    }
    if (-not [string]::IsNullOrWhiteSpace(`$_.ScriptStackTrace)) {
        Write-WrapperLog ('wrapper_stack=' + ((`$_.ScriptStackTrace -replace '\s+', ' ').Trim()))
    }
}
finally {
    Write-WrapperLog 'wrapper_stop'
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

Write-Host "Autonomous 90P supervisor started."
Write-Host "Log: $logPath"
