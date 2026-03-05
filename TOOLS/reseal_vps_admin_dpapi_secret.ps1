param(
    [string]$TokenEnvPath = "",
    [string]$UsbLabel = "OANDAKEY",
    [string]$VpsHost = "185.243.55.55",
    [string]$VpsAdminLogin = "Administrator"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-TokenEnvPath {
    param(
        [string]$ExplicitPath,
        [string]$Label
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $p = Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop
        return $p.Path
    }
    $labelNorm = [string]$Label
    if ([string]::IsNullOrWhiteSpace($labelNorm)) {
        throw "UsbLabel cannot be empty when TokenEnvPath is not provided."
    }
    $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { [string]$_.FileSystemLabel -eq $labelNorm } | Select-Object -First 1
    if ($null -eq $vol -or [string]::IsNullOrWhiteSpace([string]$vol.DriveLetter)) {
        throw "Volume with label '$labelNorm' not found."
    }
    $path = "$($vol.DriveLetter):\TOKEN\BotKey.env"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing TOKEN\\BotKey.env at: $path"
    }
    return (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
}

function Parse-EnvFile {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Encoding UTF8
    $map = [ordered]@{}
    foreach($line in $raw) {
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

function Save-EnvFile {
    param(
        [string]$Path,
        [hashtable]$Map
    )
    $lines = New-Object System.Collections.Generic.List[string]
    foreach($k in $Map.Keys) {
        $lines.Add("$k=$($Map[$k])")
    }
    $txt = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    Set-Content -LiteralPath $Path -Value $txt -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($VpsHost)) {
    throw "VpsHost cannot be empty."
}
if ([string]::IsNullOrWhiteSpace($VpsAdminLogin)) {
    throw "VpsAdminLogin cannot be empty."
}

$envPath = Resolve-TokenEnvPath -ExplicitPath $TokenEnvPath -Label $UsbLabel
$bak = "$envPath.bak.$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"
Copy-Item -LiteralPath $envPath -Destination $bak -Force

$cfg = Parse-EnvFile -Path $envPath

$secure = Read-Host -Prompt "Podaj haslo Administrator VPS (nie bedzie wyswietlane)" -AsSecureString
if ($null -eq $secure) {
    throw "Empty password input."
}
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
if ([string]::IsNullOrWhiteSpace($plain)) {
    throw "Empty password input."
}

$cipher = ConvertFrom-SecureString -SecureString $secure
if ([string]::IsNullOrWhiteSpace($cipher)) {
    throw "Cannot produce DPAPI ciphertext."
}

$cfg.Remove("VPS_ADMIN_PASSWORD") | Out-Null
$cfg.Remove("VPS_ADMIN_PASSWORD_DPAPI_B64") | Out-Null
$cfg.Remove("VPS_ADMIN_PASSWORD_DPAPI") | Out-Null
$cfg.Remove("VPS_ADMIN_PASSWORD_MODE") | Out-Null

$cfg["VPS_HOST"] = $VpsHost
$cfg["VPS_ADMIN_LOGIN"] = $VpsAdminLogin
$cfg["VPS_ADMIN_PASSWORD_MODE"] = "DPAPI_CURRENT_USER"
$cfg["VPS_ADMIN_PASSWORD_DPAPI"] = $cipher
$cfg["VPS_ADMIN_SECRET_UPDATED_UTC"] = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Save-EnvFile -Path $envPath -Map $cfg

Write-Host "VPS_ADMIN_DPAPI_RESEAL_OK"
Write-Host "TokenEnvPath: $envPath"
Write-Host "BackupPath: $bak"
Write-Host "VpsHost: $VpsHost"
Write-Host "VpsAdminLogin: $VpsAdminLogin"
Write-Host "Mode: DPAPI_CURRENT_USER"
Write-Host "Note: Na nowym komputerze/uzytkowniku uruchom skrypt ponownie, bo DPAPI jest zwiazane z uzytkownikiem Windows."

