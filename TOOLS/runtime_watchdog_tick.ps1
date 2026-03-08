param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only",
    [int]$RestartCooldownSec = 180,
    [int]$GuardStatusMaxAgeSec = 180
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

function Get-PidFromFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        if ($raw.StartsWith("{")) {
            $obj = $raw | ConvertFrom-Json
            if ($null -ne $obj -and $null -ne $obj.pid) {
                return [int]$obj.pid
            }
            return $null
        }
        if ($raw -match "^\d+$") {
            return [int]$raw
        }
        return $null
    } catch {
        return $null
    }
}

function Test-GuardRunning {
    param(
        [int]$ProcessId,
        [string]$ScriptNameHint
    )
    if ($ProcessId -le 0) { return $false }
    $proc = $null
    try {
        $proc = Get-Process -Id ([int]$ProcessId) -ErrorAction Stop
    } catch {
        return $false
    }
    if ($null -eq $proc) { return $false }
    if ([string]::IsNullOrWhiteSpace($ScriptNameHint)) { return $true }

    # Najpierw lekkie sprawdzenie po nazwie procesu.
    $pn = [string]$proc.ProcessName
    if ([string]::IsNullOrWhiteSpace($pn)) { return $true }
    if ($pn -notmatch "^(powershell|pwsh|python)$") { return $true }

    # Dla powershell/python próbujemy potwierdzić hint przez CommandLine.
    # Gdy WMI jest chwilowo niestabilne, traktujemy proces jako działający
    # zamiast wywoływać fałszywą degradację watchdoga.
    try {
        $row = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$ProcessId) -ErrorAction Stop
        $cmd = [string]$row.CommandLine
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $true }
        return ($cmd -match [regex]::Escape($ScriptNameHint))
    } catch {
        return $true
    }
}

function Get-StatusAgeSec {
    param([string]$StatusPath)
    $obj = Read-JsonFile -Path $StatusPath
    if ($null -eq $obj) { return $null }
    $ts = ""
    if ($null -ne $obj.ts_utc) {
        $ts = [string]$obj.ts_utc
    }
    if ([string]::IsNullOrWhiteSpace($ts)) { return $null }
    try {
        $dt = [datetime]::Parse($ts).ToUniversalTime()
        return [double]((Get-Date).ToUniversalTime() - $dt).TotalSeconds
    } catch {
        return $null
    }
}

function Get-GuardProcessIdsByHint {
    param([string]$ScriptNameHint)
    $ids = @()
    if ([string]::IsNullOrWhiteSpace($ScriptNameHint)) { return @() }
    try {
        $rows = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.Name -eq "powershell.exe" -and [string]$_.CommandLine -match [regex]::Escape($ScriptNameHint)
        }
        foreach ($row in $rows) {
            try { $ids += [int]$row.ProcessId } catch {}
        }
    } catch {
        return @()
    }
    return @($ids | Sort-Object -Unique)
}

function Ensure-Guard {
    param(
        [string]$Name,
        [string]$RuntimeRoot,
        [string]$ScriptPath,
        [string]$ScriptNameHint,
        [string]$PidPath,
        [string]$StatusPath,
        [string[]]$ExtraArgs,
        [int]$StatusMaxAgeSec
    )
    $result = [ordered]@{
        name = $Name
        script = $ScriptPath
        pid_path = $PidPath
        status_path = $StatusPath
        pid = $null
        running = $false
        status_age_sec = $null
        status_fresh = $false
        repair_action = "none"
        repair_error = ""
        running_after = $false
        pid_after = $null
    }

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        $result.repair_action = "missing_script"
        $result.repair_error = ("missing_script:" + $ScriptPath)
        return $result
    }

    $guardPid = Get-PidFromFile -Path $PidPath
    if ($null -ne $guardPid) {
        $result.pid = [int]$guardPid
        $result.running = [bool](Test-GuardRunning -ProcessId ([int]$guardPid) -ScriptNameHint $ScriptNameHint)
    }
    $age = Get-StatusAgeSec -StatusPath $StatusPath
    if ($null -ne $age) {
        $result.status_age_sec = [double]$age
        $result.status_fresh = ([double]$age -le [double]$StatusMaxAgeSec)
    }

    $needsRepair = ((-not [bool]$result.running) -or (-not [bool]$result.status_fresh))
    if ($needsRepair) {
        if ($result.running -and $result.pid -gt 0) {
            try {
                Stop-Process -Id ([int]$result.pid) -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 250
                $result.repair_action = "restarted"
            } catch {
                $result.repair_action = "restart_failed"
                $result.repair_error = $_.Exception.Message
            }
        } else {
            $result.repair_action = "started"
        }
        if (Test-Path -LiteralPath $PidPath) {
            try { Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue } catch {}
        }
        if (([string]$result.repair_action) -ne "restart_failed") {
            try {
                $argList = @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", $ScriptPath,
                    "-Root", $RuntimeRoot
                )
                if ($null -ne $ExtraArgs -and @($ExtraArgs).Count -gt 0) {
                    $argList += @($ExtraArgs)
                }
                [void](Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WorkingDirectory $RuntimeRoot -WindowStyle Hidden -PassThru)
                Start-Sleep -Milliseconds 400
            } catch {
                $result.repair_action = "start_failed"
                $result.repair_error = $_.Exception.Message
            }
        }
    }

    $deadline = (Get-Date).AddSeconds(8)
    do {
        $guardPidAfter = Get-PidFromFile -Path $PidPath
        if ($null -ne $guardPidAfter) {
            $result.pid_after = [int]$guardPidAfter
            $result.running_after = [bool](Test-GuardRunning -ProcessId ([int]$guardPidAfter) -ScriptNameHint $ScriptNameHint)
        } else {
            $byHint = @(Get-GuardProcessIdsByHint -ScriptNameHint $ScriptNameHint)
            if (@($byHint).Count -gt 0) {
                $result.pid_after = [int]$byHint[0]
                $result.running_after = $true
            }
        }
        if ($result.running_after) { break }
        Start-Sleep -Milliseconds 400
    } while ((Get-Date) -lt $deadline)

    if (-not $result.running_after -and $result.running) {
        $result.running_after = $result.running
        $result.pid_after = $result.pid
    }
    return $result
}

function Test-SafetyBotPidShapeBenign {
    param([int[]]$Pids)
    $uniq = @($Pids | Sort-Object -Unique)
    if (@($uniq).Count -le 1) { return $true }
    if (@($uniq).Count -ne 2) { return $false }
    try {
        $a = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$uniq[0]) -ErrorAction Stop
        $b = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$uniq[1]) -ErrorAction Stop
        if (($null -eq $a) -or ($null -eq $b)) { return $false }
        $aParent = [int]$a.ParentProcessId
        $bParent = [int]$b.ParentProcessId
        if (($aParent -eq [int]$uniq[1]) -or ($bParent -eq [int]$uniq[0])) {
            return $true
        }
    } catch {
        return $false
    }
    return $false
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
$criticalNames = @("SafetyBot")
if ($Profile -eq "full") {
    $criticalNames += @("SCUD", "InfoBot")
}
$components = @()
if ($null -ne $last -and $null -ne $last.components) {
    $components = @($last.components)
    $statusValue = [string]$last.status
}

$terminalRows = @()
try {
    $terminalRows = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -eq "terminal64.exe" -and $_.CommandLine -match "OANDA TMS MT5 Terminal"
    })
} catch {
    $terminalRows = @()
}
$terminalRunning = (@($terminalRows).Count -gt 0)

$guardResults = @()
if ($terminalRunning) {
    $guardDefs = @(
        @{
            name = "MT5RiskGuard"
            script = (Join-Path $runtimeRoot "TOOLS\mt5_risk_popup_guard.ps1")
            script_hint = "mt5_risk_popup_guard.ps1"
            pid = (Join-Path $runDir "mt5_risk_guard.pid")
            status = (Join-Path $runDir "mt5_risk_guard_status.json")
            extra = @()
        },
        @{
            name = "MT5SessionGuard"
            script = (Join-Path $runtimeRoot "TOOLS\mt5_session_guard.ps1")
            script_hint = "mt5_session_guard.ps1"
            pid = (Join-Path $runDir "mt5_session_guard.pid")
            status = (Join-Path $runDir "mt5_session_guard_status.json")
            extra = @("-Profile", $Profile)
        }
    )
    foreach ($g in $guardDefs) {
        $guardResults += (Ensure-Guard -Name ([string]$g.name) `
            -RuntimeRoot $runtimeRoot `
            -ScriptPath ([string]$g.script) `
            -ScriptNameHint ([string]$g.script_hint) `
            -PidPath ([string]$g.pid) `
            -StatusPath ([string]$g.status) `
            -ExtraArgs @($g.extra) `
            -StatusMaxAgeSec ([int]$GuardStatusMaxAgeSec))
    }
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
    $pidCount = @($c.pids).Count
    if (($name -eq "SafetyBot") -and ($pidCount -gt 1)) {
        $isBenign = Test-SafetyBotPidShapeBenign -Pids @($c.pids)
        if (-not $isBenign) {
            $criticalOk = $false
            $criticalDetails += ("SafetyBot:duplicate_pids=" + [string]$pidCount)
        }
    }
    # W praktyce "running_by_pid" potrafi być chwilowo puste mimo zdrowego serca
    # (heartbeat + log), np. podczas przełączania interpretera.
    # Dla hot-path traktujemy heartbeat jako nadrzędny sygnał żywotności.
    $ok = $running -and $hbOk
    if (-not $ok) {
        $criticalOk = $false
        $criticalDetails += ("{0}:running={1},pid={2},hb={3}" -f [string]$name, [bool]$running, [bool]$pidOk, [bool]$hbOk)
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
if ($terminalRunning) {
    $guardFailures = @($guardResults | Where-Object { -not [bool]$_.running_after })
    if (@($guardFailures).Count -gt 0) {
        $healthy = $false
        $reasons += "GUARDS_DEGRADED"
        foreach ($gf in $guardFailures) {
            $criticalDetails += ("{0}:running_after=0 action={1} err={2}" -f [string]$gf.name, [string]$gf.repair_action, [string]$gf.repair_error)
        }
    }
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
        $reasonSuffix = ""
        if ($criticalDetails.Count -gt 0) {
            $reasonSuffix = "|" + ($criticalDetails -join ";")
        }
        $state.last_restart_utc = $now.ToString("o")
        $state.last_reason = (($reasons -join ",") + $reasonSuffix)
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
    terminal_running = [bool]$terminalRunning
    healthy = [bool]$healthy
    status = $statusValue
    reasons = @($reasons)
    critical_issues = @($criticalDetails)
    guard_results = @($guardResults)
    restart_invoked = [bool]$restartInvoked
    restart_exit_code = $restartRc
    restart_error = $restartErr
    system_control_status_output = $statusOut
}
Write-JsonLine -Path $jsonlPath -Payload $event
$event | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8

Write-Output ("RUNTIME_WATCHDOG tick healthy={0} restart_invoked={1} status={2}" -f [int]$healthy, [int]$restartInvoked, $statusValue)
