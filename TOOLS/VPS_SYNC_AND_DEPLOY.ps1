param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$UsbLabel = "OANDAKEY",
    [string]$TokenEnvPath = "",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only",
    [switch]$StartAfterSync,
    [switch]$RunEaDeploy,
    [switch]$SkipBootstrap,
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
        $p = "$($vol.DriveLetter):\TOKEN\BotKey.env"
        if (Test-Path -LiteralPath $p) {
            return (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path
        }
    }
    throw "Brak pliku BotKey.env (D:\\TOKEN, C:\\TOKEN, <ROOT>\\OANDAKEY\\TOKEN, label '$Label')."
}

function Parse-EnvFile {
    param([string]$Path)
    $map = [ordered]@{}
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith("#")) { continue }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { continue }
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1)
        if (-not [string]::IsNullOrWhiteSpace($k)) {
            $map[$k] = $v
        }
    }
    return $map
}

function Get-VpsCredential {
    param([hashtable]$Cfg)
    $vpsHost = [string]$Cfg["VPS_HOST"]
    $user = [string]$Cfg["VPS_ADMIN_LOGIN"]
    $dpapi = [string]$Cfg["VPS_ADMIN_PASSWORD_DPAPI"]
    if ([string]::IsNullOrWhiteSpace($vpsHost) -or [string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($dpapi)) {
        throw "Brakuje VPS_HOST / VPS_ADMIN_LOGIN / VPS_ADMIN_PASSWORD_DPAPI w BotKey.env."
    }
    $sec = ConvertTo-SecureString $dpapi
    $cred = New-Object System.Management.Automation.PSCredential($user, $sec)
    return [ordered]@{
        host = $vpsHost
        user = $user
        cred = $cred
    }
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$tokenEnv = Resolve-TokenEnvPath -ExplicitPath $TokenEnvPath -Label $UsbLabel -RuntimeRoot $runtimeRoot
$cfg = Parse-EnvFile -Path $tokenEnv
$vps = Get-VpsCredential -Cfg $cfg

$syncDir = Join-Path $runtimeRoot "EVIDENCE\vps_sync"
New-Item -ItemType Directory -Force -Path $syncDir | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$syncReport = Join-Path $syncDir ("vps_sync_report_" + $stamp + ".json")

$result = [ordered]@{
    schema = "oanda.mt5.vps.sync_and_deploy.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    token_env = $tokenEnv
    host = $vps.host
    dry_run = [bool]$DryRun
    profile = [string]$Profile
    bundle_path = ""
    status = "INIT"
    steps = @()
}

function Add-Step {
    param([string]$Name, [string]$Status, [string]$Info = "")
    $result.steps += [ordered]@{
        name = $Name
        status = $Status
        info = $Info
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    }
}

try {
    $buildScript = Join-Path $runtimeRoot "TOOLS\vps_build_migration_bundle.ps1"
    if (-not (Test-Path -LiteralPath $buildScript)) {
        throw "Brak skryptu: $buildScript"
    }

    if ($DryRun) {
        Add-Step -Name "build_bundle" -Status "DRY_RUN" -Info "Pomijam budowę i upload."
    } else {
        $bundleOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -Root $runtimeRoot
        $latest = Join-Path $runtimeRoot "EVIDENCE\vps_prep\vps_bundle_latest.json"
        if (-not (Test-Path -LiteralPath $latest)) {
            throw "Brak vps_bundle_latest.json po build."
        }
        $manifest = Get-Content -LiteralPath $latest -Raw | ConvertFrom-Json
        $bundlePath = [string]$manifest.bundle_path
        if (-not (Test-Path -LiteralPath $bundlePath)) {
            throw "Brak bundla: $bundlePath"
        }
        $result.bundle_path = $bundlePath
        Add-Step -Name "build_bundle" -Status "OK" -Info $bundlePath

        $session = $null
        try {
            $sessionOpt = New-PSSessionOption -OperationTimeout 120000 -OpenTimeout 30000 -IdleTimeout 180000
            $session = New-PSSession -ComputerName $vps.host -Credential $vps.cred -SessionOption $sessionOpt
            Add-Step -Name "open_pssession" -Status "OK" -Info ("id=" + [string]$session.Id)

            $remoteZipDir = "C:\OANDA_MT5_SYSTEM\RUN\vps_sync"
            $remoteZip = "$remoteZipDir\incoming_bundle.zip"
            Invoke-Command -Session $session -ArgumentList $remoteZipDir -ScriptBlock {
                param($p)
                New-Item -ItemType Directory -Force -Path $p | Out-Null
            } | Out-Null
            Copy-Item -ToSession $session -Path $bundlePath -Destination $remoteZip -Force
            Add-Step -Name "upload_bundle" -Status "OK" -Info $remoteZip

            $remoteAction = Invoke-Command -Session $session -ErrorAction Stop -ArgumentList $remoteZip, "C:\OANDA_MT5_SYSTEM", [bool]$StartAfterSync, [bool]$RunEaDeploy, [bool]$SkipBootstrap, [bool]$SkipRemoteStatus, $Profile -ScriptBlock {
                param($ZipPath, $RemoteRoot, $DoStart, $DoEaDeploy, $DoSkipBootstrap, $DoSkipRemoteStatus, $RuntimeProfile)
                $ErrorActionPreference = "Continue"
                $out = [ordered]@{
                    unzip = "INIT"
                    sync = "INIT"
                    sync_method = "POWERSHELL_COPY"
                    bootstrap = "SKIP"
                    ea_deploy = "SKIP"
                    start = "SKIP"
                    status = "INIT"
                }
                $extract = Join-Path $env:TEMP ("oanda_sync_" + [guid]::NewGuid().ToString("N"))
                New-Item -ItemType Directory -Force -Path $extract | Out-Null
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $extract)
                    $out.unzip = "OK"

                    New-Item -ItemType Directory -Force -Path $RemoteRoot | Out-Null
                    Get-ChildItem -LiteralPath $extract -Force | ForEach-Object {
                        $dest = Join-Path $RemoteRoot $_.Name
                        Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
                    }
                    $out.sync = "OK"

                    if (-not [bool]$DoSkipBootstrap) {
                        $bootstrap = Join-Path $RemoteRoot "TOOLS\vps_bootstrap_windows.ps1"
                        if (Test-Path -LiteralPath $bootstrap) {
                            & powershell -NoProfile -ExecutionPolicy Bypass -File $bootstrap -ProjectRoot $RemoteRoot -LabDataRoot "C:\OANDA_MT5_LAB_DATA" | Out-Null
                            $out.bootstrap = "OK"
                        }
                    }

                    if ($DoEaDeploy) {
                        $eaBat = Join-Path $RemoteRoot "Aktualizuj_EA.bat"
                        if (Test-Path -LiteralPath $eaBat) {
                            cmd /c $eaBat | Out-Null
                            $out.ea_deploy = "OK"
                        }
                    }

                    if ($DoStart) {
                        $startScript = Join-Path $RemoteRoot "RUN\START_WITH_OANDAKEY.ps1"
                        if (Test-Path -LiteralPath $startScript) {
                            $args = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -Root `"$RemoteRoot`" -Profile $RuntimeProfile"
                            Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden | Out-Null
                            Start-Sleep -Seconds 3
                            $out.start = "TRIGGERED"
                        }
                    }

                    if (-not [bool]$DoSkipRemoteStatus) {
                        $statusScript = Join-Path $RemoteRoot "TOOLS\SYSTEM_CONTROL.ps1"
                        if (Test-Path -LiteralPath $statusScript) {
                            $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $statusScript -Action status -Root $RemoteRoot 2>&1 | Out-String
                            $out.status = "STATUS_DONE"
                            $out.status_output = $raw
                        } else {
                            $out.status = "NO_STATUS_SCRIPT"
                        }
                    } else {
                        $out.status = "STATUS_SKIPPED"
                    }
                } finally {
                    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
                }
                return ($out | ConvertTo-Json -Depth 8)
            }
            Add-Step -Name "remote_apply" -Status "OK" -Info ([string]$remoteAction)
            $result.status = "PASS"
        } finally {
            if ($null -ne $session) {
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        }
    }

    if ($DryRun) {
        $result.status = "DRY_RUN"
    }
} catch {
    $result.status = "FAIL"
    $result.error = $_.Exception.Message
    Add-Step -Name "error" -Status "FAIL" -Info $_.Exception.Message
}

$result | ConvertTo-Json -Depth 8 | Set-Content -Path $syncReport -Encoding UTF8
$latest = Join-Path $syncDir "vps_sync_report_latest.json"
$result | ConvertTo-Json -Depth 8 | Set-Content -Path $latest -Encoding UTF8
Write-Output ("VPS_SYNC_AND_DEPLOY status={0} report={1}" -f [string]$result.status, $syncReport)
if ($result.Contains("error") -and -not [string]::IsNullOrWhiteSpace([string]$result.error)) {
    Write-Output ("DETAILS: " + [string]$result.error)
}

if ([string]$result.status -eq "FAIL") { exit 2 }
exit 0
