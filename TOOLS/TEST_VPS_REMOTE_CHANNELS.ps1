param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$UsbLabel = "OANDAKEY",
    [string]$TokenEnvPath = ""
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
    $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object FileSystemLabel -eq $Label | Select-Object -First 1
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
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1)
        if (-not [string]::IsNullOrWhiteSpace($k)) {
            $map[$k] = $v
        }
    }
    return $map
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$envPath = Resolve-TokenEnvPath -ExplicitPath $TokenEnvPath -Label $UsbLabel -RuntimeRoot $runtimeRoot
$cfg = Parse-EnvFile -Path $envPath
$hostName = [string]$cfg["VPS_HOST"]
$reportDir = Join-Path $runtimeRoot "EVIDENCE\vps_remote_admin"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$reportPath = Join-Path $reportDir ("test_vps_remote_channels_" + $stamp + ".json")

$report = [ordered]@{
    schema = "oanda.mt5.vps.remote.channels.v1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    host = $hostName
    ports = [ordered]@{}
    wsman = [ordered]@{}
    ssh = [ordered]@{}
}

foreach ($port in 3389, 5985, 22) {
    try {
        $tn = Test-NetConnection -ComputerName $hostName -Port $port -WarningAction SilentlyContinue
        $report.ports["$port"] = [ordered]@{
            tcp = [bool]$tn.TcpTestSucceeded
            ping = [bool]$tn.PingSucceeded
        }
    } catch {
        $report.ports["$port"] = [ordered]@{ tcp = $false; error = $_.Exception.Message }
    }
}

try {
    $null = Test-WSMan $hostName -ErrorAction Stop
    $report.wsman.probe = "OK"
} catch {
    $report.wsman.probe = "FAIL"
    $report.wsman.probe_error = $_.Exception.Message
}

try {
    $sshOut = (& ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new oanda-vps hostname 2>&1 | Out-String).Trim()
    $report.ssh.exit_code = [int]$LASTEXITCODE
    $report.ssh.output = $sshOut
} catch {
    $report.ssh.exit_code = 999
    $report.ssh.output = $_.Exception.Message
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Output ("TEST_VPS_REMOTE_CHANNELS_DONE report={0}" -f $reportPath)
exit 0
