param(
    [int]$Port = 3389,
    [switch]$DisableNla
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
    Write-Host ("[VPS_RDP] " + $msg)
}

function Test-IsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    throw "Uruchom ten skrypt w PowerShell jako Administrator na serwerze VPS."
}

Write-Step "start"

$tsKey = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
$rdpTcpKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"

Set-ItemProperty -Path $tsKey -Name fDenyTSConnections -Value 0
Write-Step "rdp_connections=enabled"

if ($DisableNla.IsPresent) {
    Set-ItemProperty -Path $rdpTcpKey -Name UserAuthentication -Value 0
    Write-Step "nla=disabled"
} else {
    Set-ItemProperty -Path $rdpTcpKey -Name UserAuthentication -Value 1
    Write-Step "nla=enabled"
}

if ($Port -ne 3389) {
    Set-ItemProperty -Path $rdpTcpKey -Name PortNumber -Value ([int]$Port)
    Write-Step "port=$Port"
} else {
    Write-Step "port=3389"
}

try {
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" | Out-Null
    Write-Step "firewall_group=enabled"
} catch {
    Write-Step ("firewall_group_warn=" + $_.Exception.Message)
}

Set-Service -Name TermService -StartupType Automatic
if ((Get-Service -Name TermService).Status -ne "Running") {
    Start-Service -Name TermService
}
Write-Step "termservice=running"

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
$reportDir = "C:\OANDA_MT5_SYSTEM\EVIDENCE\vps_prep"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$reportPath = Join-Path $reportDir ("vps_enable_rdp_" + $stamp + ".json")

$report = [ordered]@{
    schema = "oanda.mt5.vps.enable_rdp.v1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    host = $env:COMPUTERNAME
    user = $env:USERNAME
    port = $Port
    nla_enabled = (-not $DisableNla.IsPresent)
    listener_detected = ($null -ne $listener)
}

$report | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $reportPath
Write-Step ("report=" + $reportPath)
Write-Step "done"
