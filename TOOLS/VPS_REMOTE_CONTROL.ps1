param(
    [ValidateSet("start", "stop", "status", "restart", "create_server_buttons")]
    [string]$Action = "status",
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$UsbLabel = "OANDAKEY",
    [string]$TokenEnvPath = "",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only",
    [switch]$OpenRdp,
    [switch]$NoLocalStop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-TokenEnvPath {
    param(
        [string]$ExplicitPath,
        [string]$Label
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
    }

    $candidates = @(
        "D:\TOKEN\BotKey.env",
        "C:\TOKEN\BotKey.env"
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

    throw "Brak pliku BotKey.env (sprawdzono D:\TOKEN, C:\TOKEN oraz wolumin '$Label')."
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

function Stop-LocalRuntimeBestEffort {
    param([string]$RuntimeRoot)
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RuntimeRoot "TOOLS\SYSTEM_CONTROL.ps1") -Action stop -Root $RuntimeRoot | Out-Null
    } catch {
        # nie przerywamy
    }
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$envPath = Resolve-TokenEnvPath -ExplicitPath $TokenEnvPath -Label $UsbLabel
$cfg = Parse-EnvFile -Path $envPath
$vps = Get-VpsCredential -Cfg $cfg
$vpsRoot = "C:\OANDA_MT5_SYSTEM"

if ((@("start", "restart") -contains $Action) -and (-not $NoLocalStop)) {
    # Tryb "single runtime": przed startem VPS wygaszamy lokalny runtime.
    Stop-LocalRuntimeBestEffort -RuntimeRoot $runtimeRoot
}

$invokeError = ""
$result = $null
$sessionOpt = New-PSSessionOption -OperationTimeout 30000 -OpenTimeout 15000 -IdleTimeout 60000
try {
    $result = Invoke-Command -ComputerName $vps.host -Credential $vps.cred -SessionOption $sessionOpt -ArgumentList $Action, $vpsRoot, $Profile -ScriptBlock {
    param($RemoteAction, $RemoteRoot, $RemoteProfile)

    $out = [ordered]@{
        action = [string]$RemoteAction
        root = [string]$RemoteRoot
        ts_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    if ($RemoteAction -eq "start") {
        $script = Join-Path $RemoteRoot "RUN\START_WITH_OANDAKEY.ps1"
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Root `"$RemoteRoot`" -Profile $RemoteProfile"
        Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 2
        $out.output = @("START_TRIGGERED")
    } elseif ($RemoteAction -eq "stop") {
        $script = Join-Path $RemoteRoot "TOOLS\SYSTEM_CONTROL.ps1"
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Action stop -Root `"$RemoteRoot`""
        Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 2
        $out.output = @("STOP_TRIGGERED")
    } elseif ($RemoteAction -eq "status") {
        $out.output = @("STATUS_SNAPSHOT")
    } elseif ($RemoteAction -eq "restart") {
        $stopScript = Join-Path $RemoteRoot "TOOLS\SYSTEM_CONTROL.ps1"
        $stopArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$stopScript`" -Action stop -Root `"$RemoteRoot`""
        Start-Process -FilePath "powershell.exe" -ArgumentList $stopArgs -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 4
        $startScript = Join-Path $RemoteRoot "RUN\START_WITH_OANDAKEY.ps1"
        $startArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -Root `"$RemoteRoot`" -Profile $RemoteProfile"
        Start-Process -FilePath "powershell.exe" -ArgumentList $startArgs -WindowStyle Hidden | Out-Null
        $out.output = @("RESTART_TRIGGERED")
    } elseif ($RemoteAction -eq "create_server_buttons") {
        $script = Join-Path $RemoteRoot "TOOLS\CREATE_VPS_SERVER_BUTTONS.ps1"
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Root `"$RemoteRoot`" -Force"
        $p = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden -PassThru
        if ($p -and -not $p.HasExited) {
            $null = $p.WaitForExit(15000)
        }
        $out.output = @("CREATE_SERVER_BUTTONS_TRIGGERED")
    }

    try {
        $statusPath = Join-Path $RemoteRoot "RUN\system_control_last.json"
        if (Test-Path -LiteralPath $statusPath) {
            $out.system_control_last = Get-Content -LiteralPath $statusPath -Raw -ErrorAction SilentlyContinue
        }
    } catch {}
    try {
        $startPath = Join-Path $RemoteRoot "RUN\start_with_key_status.json"
        if (Test-Path -LiteralPath $startPath) {
            $out.start_with_key_last = Get-Content -LiteralPath $startPath -Raw -ErrorAction SilentlyContinue
        }
    } catch {}
    try {
        $logPath = Join-Path $RemoteRoot "LOGS\safetybot.log"
        if (Test-Path -LiteralPath $logPath) {
            $out.safetybot_tail = @(Get-Content -LiteralPath $logPath -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object { [string]$_ })
        }
    } catch {}

    return ($out | ConvertTo-Json -Depth 8)
    }
} catch {
    $invokeError = $_.Exception.Message
}

if (-not [string]::IsNullOrWhiteSpace($invokeError)) {
    Write-Output ("VPS_REMOTE_CONTROL action={0} host={1} status=REMOTE_CALL_FAILED" -f $Action, $vps.host)
    Write-Output ("DETAILS: {0}" -f $invokeError)
    if ($OpenRdp) {
        $connectScript = Join-Path $runtimeRoot "TOOLS\CONNECT_VPS_RDP.ps1"
        if (Test-Path -LiteralPath $connectScript) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $connectScript -Root $runtimeRoot -UsbLabel $UsbLabel -TokenEnvPath $envPath
        }
    }
    exit 0
}

$parsed = $null
try {
    $parsed = [string]$result | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Output ("VPS_REMOTE_CONTROL action={0} host={1}" -f $Action, $vps.host)
    Write-Output ([string]$result)
    exit 0
}

Write-Output ("VPS_REMOTE_CONTROL action={0} host={1} ts_utc={2}" -f $Action, $vps.host, [string]$parsed.ts_utc)
if ($parsed.output) {
    foreach ($ln in @($parsed.output)) { Write-Output ([string]$ln) }
}
if ($parsed.stop_output) {
    foreach ($ln in @($parsed.stop_output)) { Write-Output ([string]$ln) }
}
if ($parsed.start_output) {
    foreach ($ln in @($parsed.start_output)) { Write-Output ([string]$ln) }
}
if ($parsed.system_control_last) {
    try {
        $sc = ([string]$parsed.system_control_last | ConvertFrom-Json -ErrorAction Stop)
        Write-Output ("REMOTE_STATUS last_action={0} status={1} ts_utc={2}" -f [string]$sc.action, [string]$sc.status, [string]$sc.ts_utc)
    } catch {}
}
if ($parsed.start_with_key_last) {
    try {
        $swk = ([string]$parsed.start_with_key_last | ConvertFrom-Json -ErrorAction Stop)
        Write-Output ("START_WITH_KEY status={0} key_source={1} detected_drive={2}" -f [string]$swk.status, [string]$swk.key_source, [string]$swk.detected_drive)
    } catch {}
}
if ($parsed.safetybot_tail) {
    foreach ($ln in @($parsed.safetybot_tail)) { Write-Output ("LOG " + [string]$ln) }
}

if ($OpenRdp) {
    $connectScript = Join-Path $runtimeRoot "TOOLS\CONNECT_VPS_RDP.ps1"
    if (Test-Path -LiteralPath $connectScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $connectScript -Root $runtimeRoot -UsbLabel $UsbLabel -TokenEnvPath $envPath
    }
}

exit 0
