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
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($CommandText))
    & ssh @BaseArgs "powershell" "-NoProfile" "-EncodedCommand" $encoded
    if ($LASTEXITCODE -ne 0) {
        throw "Polecenie ssh nie powiodlo sie: $CommandText"
    }
}

function Invoke-SshRemoteBestEffort {
    param(
        [string[]]$BaseArgs,
        [string]$CommandText
    )
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($CommandText))
    & ssh @BaseArgs "powershell" "-NoProfile" "-EncodedCommand" $encoded
    return $LASTEXITCODE
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
            & scp "-i" $SshKeyPath "-o" "BatchMode=yes" "-o" "StrictHostKeyChecking=accept-new" $localPath "${vpsUser}@${vpsHost}:$remoteScp"
            if ($LASTEXITCODE -ne 0) {
                throw "scp nie powiodl sie dla: $rel"
            }
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
        $stopCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File '$escapedRemoteRoot\TOOLS\SYSTEM_CONTROL.ps1' -Action stop -Root '$escapedRemoteRoot'"
        if (-not $DryRun) {
            [void](Invoke-SshRemoteBestEffort -BaseArgs $sshBase -CommandText $stopCmd)
        }
        $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File '$escapedRemoteRoot\TOOLS\SYSTEM_CONTROL.ps1' -Action start -Root '$escapedRemoteRoot' -Profile '$Profile'"
        if (-not $DryRun) {
            Invoke-SshRemote -BaseArgs $sshBase -CommandText $cmd
        }
    }

    if (-not $SkipRemoteStatus) {
        $statusCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File '$RemoteRoot\TOOLS\SYSTEM_CONTROL.ps1' -Action status -Root '$RemoteRoot'"
        if (-not $DryRun) {
            $remoteStatus = & ssh @sshBase "powershell" "-NoProfile" "-ExecutionPolicy" "Bypass" "-File" "$RemoteRoot\TOOLS\SYSTEM_CONTROL.ps1" "-Action" "status" "-Root" "$RemoteRoot"
            if ($LASTEXITCODE -ne 0) {
                throw "Zdalny SYSTEM_CONTROL status nie powiodl sie."
            }
            $report.remote_status = ($remoteStatus | Out-String).Trim()
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
