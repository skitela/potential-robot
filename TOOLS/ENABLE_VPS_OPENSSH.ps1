param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$UsbLabel = "OANDAKEY",
    [string]$TokenEnvPath = "",
    [string]$SshKeyPath = "",
    [switch]$SkipKeySetup
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
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1)
        if (-not [string]::IsNullOrWhiteSpace($k)) {
            $map[$k] = $v
        }
    }
    return $map
}

function Ensure-LocalSshKey {
    param([string]$KeyPath)
    $keyDir = Split-Path -Parent $KeyPath
    New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
    if (-not (Test-Path -LiteralPath $KeyPath)) {
        $cmd = "ssh-keygen -t ed25519 -f `"$KeyPath`" -N `"`" -C `"oanda-vps`""
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $cmd) -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -ne 0) {
            throw "ssh-keygen failed with exit code $($proc.ExitCode)"
        }
    }
    $pub = "$KeyPath.pub"
    if (-not (Test-Path -LiteralPath $pub)) {
        throw "Brak klucza publicznego: $pub"
    }
    return (Get-Content -LiteralPath $pub -Raw).Trim()
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$envPath = Resolve-TokenEnvPath -ExplicitPath $TokenEnvPath -Label $UsbLabel -RuntimeRoot $runtimeRoot
$cfg = Parse-EnvFile -Path $envPath
$vpsHost = [string]$cfg["VPS_HOST"]
$vpsUser = [string]$cfg["VPS_ADMIN_LOGIN"]
$vpsDpapi = [string]$cfg["VPS_ADMIN_PASSWORD_DPAPI"]
if ([string]::IsNullOrWhiteSpace($vpsHost) -or [string]::IsNullOrWhiteSpace($vpsUser) -or [string]::IsNullOrWhiteSpace($vpsDpapi)) {
    throw "Brakuje VPS_HOST / VPS_ADMIN_LOGIN / VPS_ADMIN_PASSWORD_DPAPI."
}

if ([string]::IsNullOrWhiteSpace($SshKeyPath)) {
    $SshKeyPath = Join-Path $env:USERPROFILE ".ssh\id_ed25519_oanda_vps"
}
$publicKey = $null
if (-not $SkipKeySetup) {
    $publicKey = Ensure-LocalSshKey -KeyPath $SshKeyPath
}

$sec = ConvertTo-SecureString $vpsDpapi
$cred = New-Object System.Management.Automation.PSCredential($vpsUser, $sec)
$opt = New-PSSessionOption -OperationTimeout 120000 -OpenTimeout 30000 -IdleTimeout 180000
$session = New-PSSession -ComputerName $vpsHost -Credential $cred -SessionOption $opt
try {
    $remoteResult = Invoke-Command -Session $session -ArgumentList @([string]$publicKey, [bool](-not $SkipKeySetup)) -ScriptBlock {
        param($PubKey, $DoKeySetup)
        $result = [ordered]@{
            sshd_capability = "UNKNOWN"
            service_status = "UNKNOWN"
            firewall = "UNKNOWN"
            key_setup = "SKIPPED"
            hostname = $env:COMPUTERNAME
            capability_install_error = ""
            needs_fallback_install = $false
        }

        $cap = Get-WindowsCapability -Online -Name OpenSSH.Server* | Select-Object -First 1
        if ($null -eq $cap) {
            $result.sshd_capability = "NOT_FOUND"
            $result.needs_fallback_install = $true
        } else {
            $result.sshd_capability = [string]$cap.State
            if ([string]$cap.State -ne "Installed") {
                try {
                    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
                    $result.sshd_capability = "Installed"
                } catch {
                    $result.capability_install_error = $_.Exception.Message
                }
            }
        }

        $svc = Get-Service sshd -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            $result.needs_fallback_install = $true
            return ($result | ConvertTo-Json -Depth 6)
        }

        Set-Service -Name sshd -StartupType Automatic
        if ((Get-Service sshd).Status -ne "Running") {
            Start-Service sshd
        }
        $result.service_status = (Get-Service sshd).Status.ToString()

        $fw = Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue
        if ($null -eq $fw) {
            New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
            $result.firewall = "CREATED"
        } else {
            Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -Enabled True | Out-Null
            $result.firewall = "ENABLED"
        }

        if ($DoKeySetup) {
            $authPath = "C:\ProgramData\ssh\administrators_authorized_keys"
            New-Item -ItemType Directory -Force -Path "C:\ProgramData\ssh" | Out-Null
            if (-not (Test-Path -LiteralPath $authPath)) {
                New-Item -ItemType File -Path $authPath -Force | Out-Null
            }
            $existing = Get-Content -LiteralPath $authPath -ErrorAction SilentlyContinue
            if ($existing -notcontains $PubKey) {
                Add-Content -LiteralPath $authPath -Value $PubKey
            }
            icacls $authPath /inheritance:r | Out-Null
            icacls $authPath /grant "*S-1-5-32-544:F" | Out-Null
            icacls $authPath /grant "*S-1-5-18:F" | Out-Null
            $result.key_setup = "OK"
        }

        $cfgPath = "C:\ProgramData\ssh\sshd_config"
        if (Test-Path -LiteralPath $cfgPath) {
            $raw = Get-Content -LiteralPath $cfgPath -Raw
            if ($raw -notmatch "(?m)^\s*PubkeyAuthentication\s+yes\s*$") {
                $raw += "`r`nPubkeyAuthentication yes`r`n"
            }
            if ($raw -notmatch "(?m)^\s*PasswordAuthentication\s+yes\s*$") {
                $raw += "PasswordAuthentication yes`r`n"
            }
            Set-Content -LiteralPath $cfgPath -Value $raw -Encoding ascii
            Restart-Service sshd
            $result.service_status = (Get-Service sshd).Status.ToString()
        }

        return ($result | ConvertTo-Json -Depth 5)
    }

    $rr = $remoteResult | ConvertFrom-Json
    if ([bool]$rr.needs_fallback_install) {
        $tmpZip = Join-Path $env:TEMP "OpenSSH-Win64.zip"
        if (Test-Path -LiteralPath $tmpZip) {
            Remove-Item -LiteralPath $tmpZip -Force
        }
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest"
        $asset = $release.assets | Where-Object { $_.name -eq "OpenSSH-Win64.zip" } | Select-Object -First 1
        if ($null -eq $asset -or [string]::IsNullOrWhiteSpace([string]$asset.browser_download_url)) {
            throw "Nie znaleziono paczki OpenSSH-Win64.zip w latest release."
        }
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip

        $remoteZipPath = "C:\OANDA_MT5_SYSTEM\RUN\vps_sync\OpenSSH-Win64.zip"
        Invoke-Command -Session $session -ArgumentList "C:\OANDA_MT5_SYSTEM\RUN\vps_sync" -ScriptBlock {
            param($p) New-Item -ItemType Directory -Force -Path $p | Out-Null
        } | Out-Null
        Copy-Item -ToSession $session -Path $tmpZip -Destination $remoteZipPath -Force

        $remoteResult = Invoke-Command -Session $session -ArgumentList @($remoteZipPath, [string]$publicKey, [bool](-not $SkipKeySetup)) -ScriptBlock {
            param($ZipPath, $PubKey, $DoKeySetup)
            $result = [ordered]@{
                fallback_install = "INIT"
                service_status = "UNKNOWN"
                firewall = "UNKNOWN"
                key_setup = "SKIPPED"
                install_root = "C:\Program Files\OpenSSH-Win64"
            }
            $installRoot = [string]$result.install_root
            if (Test-Path -LiteralPath $installRoot) {
                Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Force -Path $installRoot | Out-Null

            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $installRoot)
            $installScript = Get-ChildItem -LiteralPath $installRoot -Recurse -Filter "install-sshd.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $installScript) {
                throw "Brak install-sshd.ps1 po rozpakowaniu OpenSSH."
            }
            & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript.FullName | Out-Null
            $result.fallback_install = "OK"

            Set-Service -Name sshd -StartupType Automatic
            if ((Get-Service sshd).Status -ne "Running") {
                Start-Service sshd
            }
            $result.service_status = (Get-Service sshd).Status.ToString()

            $fw = Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue
            if ($null -eq $fw) {
                New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
                $result.firewall = "CREATED"
            } else {
                Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -Enabled True | Out-Null
                $result.firewall = "ENABLED"
            }

            if ($DoKeySetup) {
                $authPath = "C:\ProgramData\ssh\administrators_authorized_keys"
                New-Item -ItemType Directory -Force -Path "C:\ProgramData\ssh" | Out-Null
                if (-not (Test-Path -LiteralPath $authPath)) {
                    New-Item -ItemType File -Path $authPath -Force | Out-Null
                }
                $existing = Get-Content -LiteralPath $authPath -ErrorAction SilentlyContinue
                if ($existing -notcontains $PubKey) {
                    Add-Content -LiteralPath $authPath -Value $PubKey
                }
                icacls $authPath /inheritance:r | Out-Null
                icacls $authPath /grant "*S-1-5-32-544:F" | Out-Null
                icacls $authPath /grant "*S-1-5-18:F" | Out-Null
                $result.key_setup = "OK"
            }
            return ($result | ConvertTo-Json -Depth 6)
        }
    }

    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    $cfgPath = Join-Path $sshDir "config"
    $alias = @(
        "Host oanda-vps"
        "    HostName $vpsHost"
        "    User $vpsUser"
        "    Port 22"
        "    IdentityFile $SshKeyPath"
        "    StrictHostKeyChecking accept-new"
        "    ServerAliveInterval 20"
        "    ServerAliveCountMax 3"
    ) -join "`r`n"
    $cfgRaw = ""
    if (Test-Path -LiteralPath $cfgPath) { $cfgRaw = Get-Content -LiteralPath $cfgPath -Raw }
    if ($cfgRaw -notmatch "(?m)^\s*Host\s+oanda-vps\s*$") {
        if (-not [string]::IsNullOrWhiteSpace($cfgRaw) -and -not $cfgRaw.EndsWith("`n")) {
            $cfgRaw += "`r`n"
        }
        $cfgRaw += "`r`n$alias`r`n"
        Set-Content -LiteralPath $cfgPath -Value $cfgRaw -Encoding ascii
    }

    Write-Output ("VPS_OPENSSH_SETUP_OK host={0} key={1}" -f $vpsHost, $SshKeyPath)
    Write-Output ("REMOTE: " + [string]$remoteResult)
    Write-Output "TEST: ssh oanda-vps hostname"
} finally {
    if ($null -ne $session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
}
