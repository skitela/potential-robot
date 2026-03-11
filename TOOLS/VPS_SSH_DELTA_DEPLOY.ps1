param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$UsbLabel = "OANDAKEY",
    [string]$TokenEnvPath = "",
    [string]$RemoteRoot = "C:\OANDA_MT5_SYSTEM",
    [string]$SshKeyPath = "",
    [string]$GitRange = "",
    [string[]]$Paths = @(),
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only",
    [int]$RuntimeReadyTimeoutSec = 180,
    [int]$RuntimeReadyPollSec = 5,
    [switch]$RunEaDeploy,
    [switch]$RunProfileSetup,
    [switch]$StartRuntime,
    [switch]$SkipRemoteStatus,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-TokenEnvPath {
    param(
        [string]$ExplicitPath,
        [string]$Label,
        [string]$RuntimeRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
    }
    $candidates = @(
        "D:\TOKEN\BotKey.env",
        "C:\TOKEN\BotKey.env",
        (Join-Path $RuntimeRoot "OANDAKEY\TOKEN\BotKey.env"),
        (Join-Path $RuntimeRoot "KEY\TOKEN\BotKey.env")
    )
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath $cand) {
            return (Resolve-Path -LiteralPath $cand -ErrorAction Stop).Path
        }
    }
    $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        [string]$_.FileSystemLabel -eq [string]$Label
    } | Select-Object -First 1
    if ($null -ne $vol -and -not [string]::IsNullOrWhiteSpace([string]$vol.DriveLetter)) {
        $candidate = "$($vol.DriveLetter):\TOKEN\BotKey.env"
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
    }
    throw "Brak pliku BotKey.env."
}

function Parse-EnvFile {
    param([string]$Path)
    $map = [ordered]@{}
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith("#")) { continue }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1)
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $map[$key] = $val
        }
    }
    return $map
}

function Resolve-DeployPaths {
    param(
        [string]$RuntimeRoot,
        [string[]]$ExplicitPaths,
        [string]$Range
    )
    if ($ExplicitPaths.Count -gt 0) {
        $items = @()
        foreach ($entry in $ExplicitPaths) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            foreach ($piece in ($entry -split ",")) {
                if (-not [string]::IsNullOrWhiteSpace($piece)) {
                    $items += $piece.Trim()
                }
            }
        }
        return @($items)
    }
    if ([string]::IsNullOrWhiteSpace($Range)) {
        throw "Podaj -Paths albo -GitRange."
    }
    $items = git -C $RuntimeRoot diff --name-only --diff-filter=ACMRTUX $Range
    if ($LASTEXITCODE -ne 0) {
        throw "git diff nie powiodl sie dla zakresu: $Range"
    }
    return @($items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function To-RemoteScpPath {
    param(
        [string]$RemoteRootPath,
        [string]$RelativePath
    )
    $full = Join-Path $RemoteRootPath $RelativePath
    $normalized = $full -replace "\\", "/"
    if ($normalized -match "^([A-Za-z]):/(.*)$") {
        return "/$($matches[1]):/$($matches[2])"
    }
    throw "Nie umiem zmapowac sciezki zdalnej: $full"
}

function Invoke-SshRemote {
    param(
        [string[]]$BaseArgs,
        [string]$CommandText
    )
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($CommandText))
        $output = (& ssh @BaseArgs "powershell" "-NoProfile" "-EncodedCommand" $encoded 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) {
            return
        }
        $msg = [string]$output
        $isTransient = (
            ($msg -match "Connection reset") -or
            ($msg -match "kex_exchange_identification") -or
            ($msg -match "Connection closed") -or
            ($msg -match "subsystem request failed") -or
            ($msg -match "Broken pipe") -or
            ($msg -match "timed out")
        )
        if (($attempt -lt $maxAttempts) -and $isTransient) {
            Start-Sleep -Seconds ([Math]::Min(10, (2 * $attempt)))
            continue
        }
        throw "Polecenie ssh nie powiodlo sie: $CommandText`n$msg"
    }
}

function Invoke-SshRemoteBestEffort {
    param(
        [string[]]$BaseArgs,
        [string]$CommandText
    )
    $maxAttempts = 3
    $lastExit = 1
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($CommandText))
        $output = (& ssh @BaseArgs "powershell" "-NoProfile" "-EncodedCommand" $encoded 2>&1 | Out-String)
        $lastExit = [int]$LASTEXITCODE
        if ($lastExit -eq 0) {
            return 0
        }
        $msg = [string]$output
        $isTransient = (
            ($msg -match "Connection reset") -or
            ($msg -match "kex_exchange_identification") -or
            ($msg -match "Connection closed") -or
            ($msg -match "subsystem request failed") -or
            ($msg -match "Broken pipe") -or
            ($msg -match "timed out")
        )
        if (($attempt -lt $maxAttempts) -and $isTransient) {
            Start-Sleep -Seconds ([Math]::Min(10, (2 * $attempt)))
            continue
        }
        break
    }
    return $lastExit
}

function Invoke-SshRemoteCapture {
    param(
        [string[]]$BaseArgs,
        [string]$CommandText
    )
    $maxAttempts = 3
    $lastExit = 1
    $lastOutput = ""
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($CommandText))
        $output = (& ssh @BaseArgs "powershell" "-NoProfile" "-EncodedCommand" $encoded 2>&1 | Out-String)
        $lastExit = [int]$LASTEXITCODE
        $lastOutput = ([string]$output).Trim()
        if ($lastExit -eq 0) {
            break
        }
        $isTransient = (
            ($lastOutput -match "Connection reset") -or
            ($lastOutput -match "kex_exchange_identification") -or
            ($lastOutput -match "Connection closed") -or
            ($lastOutput -match "subsystem request failed") -or
            ($lastOutput -match "Broken pipe") -or
            ($lastOutput -match "timed out")
        )
        if (($attempt -lt $maxAttempts) -and $isTransient) {
            Start-Sleep -Seconds ([Math]::Min(10, (2 * $attempt)))
            continue
        }
        break
    }
    return [ordered]@{
        exit_code = [int]$lastExit
        output = $lastOutput
    }
}

function Invoke-ScpWithRetry {
    param(
        [string]$SshKeyPath,
        [string]$LocalPath,
        [string]$RemoteTarget
    )
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $output = (& scp "-i" $SshKeyPath "-o" "BatchMode=yes" "-o" "StrictHostKeyChecking=accept-new" $LocalPath $RemoteTarget 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) {
            return
        }
        $msg = [string]$output
        $isTransient = (
            ($msg -match "Connection reset") -or
            ($msg -match "kex_exchange_identification") -or
            ($msg -match "Connection closed") -or
            ($msg -match "subsystem request failed") -or
            ($msg -match "Broken pipe") -or
            ($msg -match "timed out")
        )
        if (($attempt -lt $maxAttempts) -and $isTransient) {
            Start-Sleep -Seconds ([Math]::Min(10, (2 * $attempt)))
            continue
        }
        throw "scp nie powiodlo sie dla: $LocalPath`n$msg"
    }
}

function Wait-RemoteRuntimeReady {
    param(
        [string[]]$BaseArgs,
        [string]$RemoteRootPath,
        [int]$TimeoutSec = 180,
        [int]$PollSec = 5
    )
    $timeout = [Math]::Max(30, [int]$TimeoutSec)
    $poll = [Math]::Max(2, [int]$PollSec)
    $startedAt = Get-Date
    $deadline = $startedAt.AddSeconds($timeout)
    $lastStatus = ""

    while ((Get-Date) -lt $deadline) {
        $statusCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File '$RemoteRootPath\TOOLS\SYSTEM_CONTROL.ps1' -Action status -Root '$RemoteRootPath'"
        $call = Invoke-SshRemoteCapture -BaseArgs $BaseArgs -CommandText $statusCmd
        $lastStatus = [string]$call.output
        if (($call.exit_code -eq 0) -and ($lastStatus -match "SYSTEM_CONTROL action=status status=PASS")) {
            return [ordered]@{
                ok = $true
                exit_code = [int]$call.exit_code
                status_out = $lastStatus
                waited_sec = [double]([Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3))
            }
        }
        Start-Sleep -Seconds $poll
    }

    return [ordered]@{
        ok = $false
        status_out = $lastStatus
        waited_sec = [double]([Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3))
    }
}

function Repair-RemoteRuntimeControlState {
    param(
        [string[]]$BaseArgs,
        [string]$RemoteRootPath,
        [int]$StaleMinutes = 10
    )
    $mins = [Math]::Max(3, [int]$StaleMinutes)
    $cmd = @'
$cutoff = (Get-Date).AddMinutes(-__STALE_MINUTES__)
$candidates = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'powershell.exe' -and $_.CommandLine -and (
        ($_.CommandLine -match 'SYSTEM_CONTROL\.ps1') -or
        ($_.CommandLine -match 'START_WITH_OANDAKEY\.ps1')
    )
})
$killed = @()
foreach ($row in $candidates) {
    try {
        $proc = Get-Process -Id ([int]$row.ProcessId) -ErrorAction Stop
    } catch {
        $proc = $null
    }
    if (($null -ne $proc) -and ($proc.StartTime -lt $cutoff)) {
        try {
            Stop-Process -Id ([int]$row.ProcessId) -Force -ErrorAction SilentlyContinue
            $killed += [int]$row.ProcessId
        } catch {}
    }
}
Start-Sleep -Milliseconds 400
$lockPath = '__REMOTE_ROOT__\RUN\system_control.action.lock'
$lockState = 'missing'
if (Test-Path -LiteralPath $lockPath) {
    try {
        $raw = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json
        $pid = $null
        if ($null -ne $obj -and $null -ne $obj.pid) {
            try { $pid = [int]$obj.pid } catch { $pid = $null }
        }
        if (($null -eq $pid) -or (-not (Get-Process -Id $pid -ErrorAction SilentlyContinue))) {
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            $lockState = 'removed'
        } else {
            $lockState = 'active'
        }
    } catch {
        try {
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            $lockState = 'removed_after_error'
        } catch {
            $lockState = 'remove_failed'
        }
    }
}
[ordered]@{
    killed = @($killed)
    lock_state = $lockState
} | ConvertTo-Json -Compress
'@
    $cmd = $cmd.Replace("__STALE_MINUTES__", [string]$mins).Replace("__REMOTE_ROOT__", $RemoteRootPath)
    return (Invoke-SshRemoteCapture -BaseArgs $BaseArgs -CommandText $cmd)
}

function Write-Report {
    param(
        [hashtable]$Payload,
        [string]$ReportPath,
        [string]$LatestPath
    )
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $LatestPath -Encoding UTF8
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$tokenEnv = Resolve-TokenEnvPath -ExplicitPath $TokenEnvPath -Label $UsbLabel -RuntimeRoot $runtimeRoot
$cfg = Parse-EnvFile -Path $tokenEnv
$vpsHost = [string]$cfg["VPS_HOST"]
$vpsUser = [string]$cfg["VPS_ADMIN_LOGIN"]
if ([string]::IsNullOrWhiteSpace($vpsHost) -or [string]::IsNullOrWhiteSpace($vpsUser)) {
    throw "Brakuje VPS_HOST / VPS_ADMIN_LOGIN."
}

if ([string]::IsNullOrWhiteSpace($SshKeyPath)) {
    $SshKeyPath = Join-Path $env:USERPROFILE ".ssh\id_ed25519_oanda_vps"
}
if (-not (Test-Path -LiteralPath $SshKeyPath)) {
    throw "Brak klucza SSH: $SshKeyPath"
}

$pathsToDeploy = @(Resolve-DeployPaths -RuntimeRoot $runtimeRoot -ExplicitPaths $Paths -Range $GitRange)
if ($pathsToDeploy.Count -eq 0) {
    throw "Lista plikow do deployu jest pusta."
}

$sshBase = @(
    "-i", $SshKeyPath,
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "$vpsUser@$vpsHost"
)

$reportDir = Join-Path $runtimeRoot "EVIDENCE\vps_sync"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$reportPath = Join-Path $reportDir ("vps_ssh_delta_deploy_" + $stamp + ".json")
$latestPath = Join-Path $reportDir "vps_ssh_delta_deploy_latest.json"
$report = [ordered]@{
    schema = "oanda.mt5.vps.ssh.delta.deploy.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    remote_root = $RemoteRoot
    host = $vpsHost
    user = $vpsUser
    dry_run = [bool]$DryRun
    profile = $Profile
    paths = @($pathsToDeploy)
    copied = @()
    status = "INIT"
}

try {
    $dirs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($rel in $pathsToDeploy) {
        $localPath = Join-Path $runtimeRoot $rel
        if (-not (Test-Path -LiteralPath $localPath)) {
            throw "Brak lokalnego pliku: $rel"
        }
        $remoteDir = Split-Path (Join-Path $RemoteRoot $rel) -Parent
        [void]$dirs.Add($remoteDir)
    }

    foreach ($dir in $dirs) {
        $escaped = $dir.Replace("'", "''")
        $cmd = "New-Item -ItemType Directory -Force -Path '$escaped'"
        if (-not $DryRun) {
            Invoke-SshRemote -BaseArgs $sshBase -CommandText $cmd
        }
    }

    foreach ($rel in $pathsToDeploy) {
        $localPath = (Resolve-Path -LiteralPath (Join-Path $runtimeRoot $rel) -ErrorAction Stop).Path
        $remoteScp = To-RemoteScpPath -RemoteRootPath $RemoteRoot -RelativePath $rel
        if (-not $DryRun) {
            Invoke-ScpWithRetry -SshKeyPath $SshKeyPath -LocalPath $localPath -RemoteTarget "${vpsUser}@${vpsHost}:$remoteScp"
        }
        $report.copied += $rel
    }

    if ($RunProfileSetup) {
        $cmd = "C:\OANDA_VENV\.venv\Scripts\python.exe '$RemoteRoot\TOOLS\setup_mt5_hybrid_profile.py' --root '$RemoteRoot' --profile OANDA_HYBRID_AUTO"
        if (-not $DryRun) {
            Invoke-SshRemote -BaseArgs $sshBase -CommandText $cmd
        }
    }

    if ($RunEaDeploy) {
        $escapedRemoteRoot = $RemoteRoot.Replace("'", "''")
        $cmd = "Set-Location '$escapedRemoteRoot'; cmd /c '.\Aktualizuj_EA.bat'"
        if (-not $DryRun) {
            Invoke-SshRemote -BaseArgs $sshBase -CommandText $cmd
        }
    }

    if ($StartRuntime) {
        $escapedRemoteRoot = $RemoteRoot.Replace("'", "''")
        if (-not $DryRun) {
            $repairCall = Repair-RemoteRuntimeControlState -BaseArgs $sshBase -RemoteRootPath $escapedRemoteRoot -StaleMinutes 10
            $report.runtime_control_repair = [ordered]@{
                exit_code = [int]$repairCall.exit_code
                output = [string]$repairCall.output
            }
        }
        $stopCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File '$escapedRemoteRoot\TOOLS\SYSTEM_CONTROL.ps1' -Action stop -Root '$escapedRemoteRoot'"
        if (-not $DryRun) {
            [void](Invoke-SshRemoteBestEffort -BaseArgs $sshBase -CommandText $stopCmd)
        }
        $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File '$escapedRemoteRoot\RUN\START_WITH_OANDAKEY.ps1' -Root '$escapedRemoteRoot' -Profile '$Profile' -AllowNonInteractive"
        if (-not $DryRun) {
            $startCall = Invoke-SshRemoteCapture -BaseArgs $sshBase -CommandText $cmd
            $report.start_runtime = [ordered]@{
                exit_code = [int]$startCall.exit_code
                output = [string]$startCall.output
            }
            $runtimeReady = Wait-RemoteRuntimeReady -BaseArgs $sshBase -RemoteRootPath $escapedRemoteRoot -TimeoutSec $RuntimeReadyTimeoutSec -PollSec $RuntimeReadyPollSec
            $report.runtime_ready = $runtimeReady
            if (-not [bool]$runtimeReady.ok) {
                if ($startCall.exit_code -ne 0) {
                    throw "Zdalny start runtime nie powiodl sie: $($startCall.output)"
                }
                throw "Zdalny runtime nie osiagnal status=PASS w limicie czasu. Ostatni status: $($runtimeReady.status_out)"
            }
        }
    }

    if ((-not $SkipRemoteStatus) -and (-not $StartRuntime)) {
        if (-not $DryRun) {
            $remoteStatus = Invoke-SshRemoteCapture -BaseArgs $sshBase -CommandText ("powershell -NoProfile -ExecutionPolicy Bypass -File '{0}\\TOOLS\\SYSTEM_CONTROL.ps1' -Action status -Root '{0}'" -f $RemoteRoot)
            if (($remoteStatus.exit_code -ne 0) -or [string]::IsNullOrWhiteSpace([string]$remoteStatus.output)) {
                throw "Zdalny SYSTEM_CONTROL status nie powiodl sie."
            }
            $report.remote_status = ([string]$remoteStatus.output).Trim()
        }
    }

    $report.status = if ($DryRun) { "DRY_RUN" } else { "PASS" }
}
catch {
    $report.status = "FAIL"
    $report.error = $_.Exception.Message
}

Write-Report -Payload $report -ReportPath $reportPath -LatestPath $latestPath
Write-Output ("VPS_SSH_DELTA_DEPLOY status={0} report={1}" -f $report.status, $reportPath)
if ($report.Contains("error")) {
    Write-Output ("DETAILS: " + [string]$report.error)
}

if ($report.status -eq "FAIL") { exit 2 }
exit 0
