param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Profile = "full",
    [int]$RestartCooldownSec = 180
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-JsonLine {
    param(
        [string]$Path,
        [hashtable]$Payload
    )
    $line = ($Payload | ConvertTo-Json -Compress -Depth 8)
    Add-Content -Path $Path -Value $line -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root).Path
$systemControl = Join-Path $runtimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
if (-not (Test-Path -LiteralPath $systemControl)) {
    throw "Missing SYSTEM_CONTROL script: $systemControl"
}

$evidenceDir = Join-Path $runtimeRoot "EVIDENCE\runtime_watchdog"
$runDir = Join-Path $runtimeRoot "RUN"
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$jsonlPath = Join-Path $evidenceDir "runtime_watchdog.jsonl"
$statusPath = Join-Path $evidenceDir "runtime_watchdog_status.json"
$statePath = Join-Path $runDir "runtime_watchdog_state.json"
$systemStatusPath = Join-Path $runDir "system_control_last.json"

$now = (Get-Date).ToUniversalTime()
$statusOut = ""
try {
    $statusOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $systemControl -Action status -Root $runtimeRoot -Profile $Profile 2>&1 | Out-String).Trim()
} catch {
    $statusOut = "STATUS_CALL_FAILED: $($_.Exception.Message)"
}

$last = Read-JsonFile -Path $systemStatusPath
$state = Read-JsonFile -Path $statePath
if ($null -eq $state) {
    $state = @{
        schema = "oanda.mt5.runtime_watchdog_state.v1"
        last_restart_utc = ""
        last_reason = ""
    }
}

$statusValue = ""
$criticalDetails = @()
$criticalNames = @("SafetyBot", "SCUD", "InfoBot")
$components = @()
if ($null -ne $last -and $null -ne $last.components) {
    $components = @($last.components)
    $statusValue = [string]$last.status
}

$criticalOk = $true
foreach ($name in $criticalNames) {
    $c = $components | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($null -eq $c) {
        $criticalOk = $false
        $criticalDetails += "$name:MISSING"
        continue
    }
    $running = [bool]$c.running
    $pidOk = [bool]$c.running_by_pid
    $hbOk = [bool]$c.running_by_heartbeat
    $ok = $running -and $pidOk -and $hbOk
    if (-not $ok) {
        $criticalOk = $false
        $criticalDetails += "$name:running=$running,pid=$pidOk,hb=$hbOk"
    }
}

$healthy = $true
$reasons = @()
if ($statusValue -ne "PASS") {
    $healthy = $false
    $reasons += "SYSTEM_STATUS_$statusValue"
}
if (-not $criticalOk) {
    $healthy = $false
    $reasons += "CRITICAL_COMPONENTS_DEGRADED"
}

$restartInvoked = $false
$restartRc = $null
$restartErr = ""

if (-not $healthy) {
    $lastRestartUtc = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$state.last_restart_utc)) {
        try { $lastRestartUtc = [datetime]::Parse([string]$state.last_restart_utc).ToUniversalTime() } catch { $lastRestartUtc = $null }
    }
    $cooldownOk = $true
    if ($null -ne $lastRestartUtc) {
        $ageSec = ($now - $lastRestartUtc).TotalSeconds
        $cooldownOk = ($ageSec -ge [double]$RestartCooldownSec)
    }
    if ($cooldownOk) {
        $restartInvoked = $true
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $systemControl -Action start -Root $runtimeRoot -Profile $Profile | Out-Null
            $restartRc = $LASTEXITCODE
        } catch {
            $restartRc = -1
            $restartErr = $_.Exception.Message
        }
        $state.last_restart_utc = $now.ToString("o")
        $state.last_reason = (($reasons -join ",") + (if ($criticalDetails.Count -gt 0) { "|" + ($criticalDetails -join ";") } else { "" }))
    } else {
        $reasons += "RESTART_COOLDOWN_ACTIVE"
    }
}

$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

$event = @{
    ts_utc = $now.ToString("o")
    event = "runtime_watchdog_tick"
    root = $runtimeRoot
    profile = $Profile
    healthy = [bool]$healthy
    status = $statusValue
    reasons = @($reasons)
    critical_issues = @($criticalDetails)
    restart_invoked = [bool]$restartInvoked
    restart_exit_code = $restartRc
    restart_error = $restartErr
    system_control_status_output = $statusOut
}
Write-JsonLine -Path $jsonlPath -Payload $event
$event | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8

Write-Output ("RUNTIME_WATCHDOG tick healthy={0} restart_invoked={1} status={2}" -f [int]$healthy, [int]$restartInvoked, $statusValue)
