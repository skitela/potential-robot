param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$UsbLabel = "OANDAKEY",
    [string]$TokenEnvPath = "",
    [switch]$PromptForPassword
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

function Normalize-RdpUser {
    param([Parameter(Mandatory = $true)][string]$UserName)

    if ($UserName.Contains("\") -or $UserName.Contains("@")) {
        return $UserName
    }
    return ".\$UserName"
}

function Set-RdpCredential {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$PasswordPlain
    )

    # Best effort cleanup of stale credential entry.
    try {
        & cmdkey "/delete:$Target" 1>$null 2>$null
    } catch {
    }

    # Use stdin for password so special characters do not break cmdkey arguments.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmdkey.exe"
    $psi.Arguments = "/generic:$Target /user:$User /pass"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $proc) {
        throw "Nie udalo sie uruchomic cmdkey."
    }

    $stdOut = ""
    $stdErr = ""
    try {
        $proc.StandardInput.WriteLine($PasswordPlain)
        $proc.StandardInput.Close()
        $stdOut = $proc.StandardOutput.ReadToEnd()
        $stdErr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
    } finally {
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch {}
        }
        $proc.Dispose()
    }

    # cmdkey with stdin password may still report non-zero exit code in some locales.
    # Trust explicit credential presence check first.
    $verify = & cmdkey "/list:$Target" 2>$null
    if (($verify -join " ") -match [Regex]::Escape("Target: $Target")) {
        return
    }

    if ($proc.ExitCode -ne 0) {
        $detail = ""
        if (-not [string]::IsNullOrWhiteSpace($stdOut)) {
            $detail = ($stdOut -replace "\s+", " ").Trim()
        }
        if ([string]::IsNullOrWhiteSpace($detail) -and -not [string]::IsNullOrWhiteSpace($stdErr)) {
            $detail = ($stdErr -replace "\s+", " ").Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            throw "Nie udalo sie zapisac poswiadczen RDP (cmdkey). Szczegoly: $detail"
        }
        throw "Nie udalo sie zapisac poswiadczen RDP (cmdkey)."
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
$rdpUser = Normalize-RdpUser -UserName $vpsUser
if (-not $PromptForPassword) {
    Set-RdpCredential -Target $target -User $rdpUser -PasswordPlain $plain
}

$rdpDir = Join-Path $runtimeRoot "RUN"
New-Item -ItemType Directory -Force -Path $rdpDir | Out-Null
$rdpFileName = if ($PromptForPassword) { "vps_quick_connect_prompt.rdp" } else { "vps_quick_connect.rdp" }
$rdpPath = Join-Path $rdpDir $rdpFileName

$rdpLines = @(
    "full address:s:$vpsHost",
    "username:s:$rdpUser",
    ("prompt for credentials:i:{0}" -f $(if ($PromptForPassword) { 1 } else { 0 })),
    "administrative session:i:1",
    "screen mode id:i:2",
    "authentication level:i:2",
    "enablecredsspsupport:i:1",
    "negotiate security layer:i:1"
)
Set-Content -LiteralPath $rdpPath -Value $rdpLines -Encoding ASCII

# Czyszczenie jawnego hasla z pamieci skryptu.
$plain = ""
Remove-Variable plain -ErrorAction SilentlyContinue
Remove-Variable secure -ErrorAction SilentlyContinue

Start-Process -FilePath "mstsc.exe" -ArgumentList "`"$rdpPath`""
Write-Output ("VPS_RDP_CONNECT_OK host={0} user={1} prompt={2}" -f $vpsHost, $rdpUser, [int]$PromptForPassword)
exit 0
