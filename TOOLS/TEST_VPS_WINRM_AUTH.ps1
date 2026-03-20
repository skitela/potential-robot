param(
    [string]$TokenEnvPath = "D:\TOKEN\BotKey.env"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Parse-Env {
    param([string]$Path)
    $map = @{}
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = [string]$_
        if ($line -match '^\s*#') { return }
        $i = $line.IndexOf('=')
        if ($i -gt 0) {
            $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1)
        }
    }
    return $map
}

$cfg = Parse-Env -Path $TokenEnvPath
$hostName = [string]$cfg["VPS_HOST"]
$login = [string]$cfg["VPS_ADMIN_LOGIN"]
$secure = ConvertTo-SecureString ([string]$cfg["VPS_ADMIN_PASSWORD_DPAPI"])
$cred = [pscredential]::new($login, $secure)

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    host = $hostName
    login = $login
    tcp_5985 = $false
    winrm_auth_ok = $false
    error = ""
}

try {
    $tcp = Test-NetConnection $hostName -Port 5985 -WarningAction SilentlyContinue
    $result.tcp_5985 = [bool]$tcp.TcpTestSucceeded
} catch {
    $result.error = $_.Exception.Message
}

try {
    $s = New-PSSession -ComputerName $hostName -Credential $cred -ErrorAction Stop
    try {
        $probe = Invoke-Command -Session $s -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
        $result.winrm_auth_ok = $true
        $result.remote_computername = [string]$probe
    } finally {
        if ($s) { Remove-PSSession -Session $s -ErrorAction SilentlyContinue }
    }
} catch {
    $result.winrm_auth_ok = $false
    $result.error = $_.Exception.Message
}

$evidenceDir = "C:\OANDA_MT5_SYSTEM\EVIDENCE"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$jsonPath = Join-Path $evidenceDir "test_vps_winrm_auth_report.json"
$txtPath = Join-Path $evidenceDir "test_vps_winrm_auth_report.txt"
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $txtPath -Encoding ASCII
$result | ConvertTo-Json -Depth 5
