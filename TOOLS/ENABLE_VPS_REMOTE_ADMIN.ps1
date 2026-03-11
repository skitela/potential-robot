param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [switch]$EnableBasicAuth,
    [switch]$DisableRdpNla,
    [ValidateSet(0, 1, 2)]
    [int]$RdpSecurityLayer = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    throw "Uruchom ten skrypt jako Administrator na serwerze VPS."
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$reportDir = Join-Path $runtimeRoot "EVIDENCE\vps_remote_admin"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$reportPath = Join-Path $reportDir ("enable_vps_remote_admin_" + $stamp + ".json")

$report = [ordered]@{
    schema = "oanda.mt5.vps.remote.admin.v1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    host = $env:COMPUTERNAME
    winrm = [ordered]@{}
    openssh = [ordered]@{}
    rdp = [ordered]@{}
}

# WinRM / PowerShell Remoting
Enable-PSRemoting -SkipNetworkProfileCheck -Force | Out-Null
Set-Service -Name WinRM -StartupType Automatic
if ((Get-Service -Name WinRM).Status -ne "Running") {
    Start-Service -Name WinRM
}
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
if ($EnableBasicAuth) {
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
} else {
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
}
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name LocalAccountTokenFilterPolicy -PropertyType DWord -Value 1 -Force | Out-Null
try {
    Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" | Out-Null
} catch {
}
$report.winrm.service = (Get-Service -Name WinRM).Status.ToString()
$report.winrm.auth_negotiate = (Get-Item WSMan:\localhost\Service\Auth\Negotiate).Value
$report.winrm.auth_basic = (Get-Item WSMan:\localhost\Service\Auth\Basic).Value
$report.winrm.local_account_token_filter_policy = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System").LocalAccountTokenFilterPolicy

# OpenSSH
$cap = Get-WindowsCapability -Online -Name OpenSSH.Server* | Select-Object -First 1
if ($null -ne $cap -and [string]$cap.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    $cap = Get-WindowsCapability -Online -Name OpenSSH.Server* | Select-Object -First 1
}
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
if ((Get-Service -Name sshd -ErrorAction SilentlyContinue).Status -ne "Running") {
    Start-Service sshd -ErrorAction SilentlyContinue
}
if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
} else {
    Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True | Out-Null
}
$cfgPath = "C:\ProgramData\ssh\sshd_config"
if (Test-Path -LiteralPath $cfgPath) {
    $raw = Get-Content -LiteralPath $cfgPath -Raw -Encoding ASCII
    if ($raw -notmatch "(?m)^\s*PubkeyAuthentication\s+yes\s*$") {
        $raw += "`r`nPubkeyAuthentication yes`r`n"
    }
    if ($raw -notmatch "(?m)^\s*PasswordAuthentication\s+yes\s*$") {
        $raw += "PasswordAuthentication yes`r`n"
    }
    Set-Content -LiteralPath $cfgPath -Value $raw -Encoding ASCII
    Restart-Service sshd -ErrorAction SilentlyContinue
}
$report.openssh.capability_state = if ($null -ne $cap) { [string]$cap.State } else { "UNKNOWN" }
$report.openssh.service = (Get-Service -Name sshd -ErrorAction SilentlyContinue).Status.ToString()
$report.openssh.firewall_22 = [bool](Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)

# RDP baseline repair
$rdpHelper = Join-Path $runtimeRoot "TOOLS\vps_enable_rdp.ps1"
if (Test-Path -LiteralPath $rdpHelper) {
    $rdpArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $rdpHelper,
        "-SecurityLayer", [string]$RdpSecurityLayer
    )
    if ($DisableRdpNla) {
        $rdpArgs += "-DisableNla"
    }
    $rdpOutput = & powershell @rdpArgs 2>&1
    $report.rdp.helper = $rdpHelper
    $report.rdp.disable_nla = [bool]$DisableRdpNla
    $report.rdp.security_layer = [int]$RdpSecurityLayer
    $report.rdp.output = @($rdpOutput | ForEach-Object { [string]$_ })
} else {
    $report.rdp.helper = "MISSING"
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Output ("ENABLE_VPS_REMOTE_ADMIN_OK report={0}" -f $reportPath)
exit 0
