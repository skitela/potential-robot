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

    $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        [string]$_.FileSystemLabel -eq [string]$Label
    } | Select-Object -First 1

    if ($null -ne $vol -and -not [string]::IsNullOrWhiteSpace([string]$vol.DriveLetter)) {
        $p = "$($vol.DriveLetter):\TOKEN\BotKey.env"
        if (Test-Path -LiteralPath $p) {
            return (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path
        }
    }

    throw "Brak pliku BotKey.env (sprawdzono D:\\TOKEN, C:\\TOKEN, <ROOT>\\OANDAKEY\\TOKEN, <ROOT>\\KEY\\TOKEN oraz wolumin '$Label')."
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

function Convert-SecureToPlain {
    param([Parameter(Mandatory = $true)][SecureString]$Secret)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$envPath = Resolve-TokenEnvPath -ExplicitPath $TokenEnvPath -Label $UsbLabel -RuntimeRoot $runtimeRoot
$cfg = Parse-EnvFile -Path $envPath

$vpsHost = [string]$cfg["VPS_HOST"]
$vpsUser = [string]$cfg["VPS_ADMIN_LOGIN"]
$vpsDpapi = [string]$cfg["VPS_ADMIN_PASSWORD_DPAPI"]

if ([string]::IsNullOrWhiteSpace($vpsHost) -or [string]::IsNullOrWhiteSpace($vpsUser) -or [string]::IsNullOrWhiteSpace($vpsDpapi)) {
    throw "Brakuje VPS_HOST / VPS_ADMIN_LOGIN / VPS_ADMIN_PASSWORD_DPAPI w BotKey.env."
}

# Twardy precheck lacznosci - gdy serwer jest wylaczony po aktualizacji/zamknieciu
# od razu zwracamy jasny komunikat zamiast ogolnego bledu RDP 0x204.
try {
    $rdpReachable = Test-NetConnection -ComputerName $vpsHost -Port 3389 -InformationLevel Quiet -WarningAction SilentlyContinue
} catch {
    $rdpReachable = $false
}
if (-not [bool]$rdpReachable) {
    throw "Port RDP 3389 na VPS jest niedostepny. Najpierw uruchom serwer w panelu VPS (Start/Restart), odczekaj 1-2 min i kliknij skrót ponownie."
}

$secure = ConvertTo-SecureString $vpsDpapi
$plain = Convert-SecureToPlain -Secret $secure
if ([string]::IsNullOrWhiteSpace($plain)) {
    throw "Nie udalo sie odczytac hasla VPS z DPAPI."
}

$target = "TERMSRV/$vpsHost"
$null = & cmdkey /generic:$target /user:$vpsUser /pass:$plain 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Nie udalo sie zapisac poswiadczen RDP (cmdkey)."
}

$rdpDir = Join-Path $runtimeRoot "RUN"
New-Item -ItemType Directory -Force -Path $rdpDir | Out-Null
$rdpPath = Join-Path $rdpDir "vps_quick_connect.rdp"

$rdpLines = @(
    "full address:s:$vpsHost",
    "username:s:$vpsUser",
    "prompt for credentials:i:0",
    "administrative session:i:1",
    "screen mode id:i:2"
)
Set-Content -LiteralPath $rdpPath -Value $rdpLines -Encoding ASCII

# Czyszczenie jawnego hasla z pamieci skryptu.
$plain = ""
Remove-Variable plain -ErrorAction SilentlyContinue
Remove-Variable secure -ErrorAction SilentlyContinue

Start-Process -FilePath "mstsc.exe" -ArgumentList "`"$rdpPath`""
Write-Output ("VPS_RDP_CONNECT_OK host={0} user={1}" -f $vpsHost, $vpsUser)
exit 0
