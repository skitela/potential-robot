param(
    [ValidateSet("open-chat", "run", "status", "process-once")]
    [string]$Mode = "run",
    [string]$ConfigPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\orchestrator_config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$python = "python"
$script = "C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\chatgpt_codex_orchestrator.py"
$statusDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\status"
$opsLog = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\orchestrator_launcher_latest.log"

function Write-OrchLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($opsLog)) | Out-Null
    Add-Content -LiteralPath $opsLog -Value ("[{0}] {1}" -f $stamp, $Message) -Encoding UTF8
}

function Resolve-ChromePath {
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "Nie znaleziono Chrome w Program Files ani Program Files (x86)."
}

function Get-DebugPortOwner {
    param([int]$Port)
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $connection) {
            return $null
        }
        $proc = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            pid = $connection.OwningProcess
            process_name = if ($proc) { $proc.ProcessName } else { "" }
        }
    }
    catch {
        return $null
    }
}

function Wait-DevToolsReady {
    param(
        [string]$DebugHost,
        [int]$Port,
        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $url = "http://$DebugHost`:$Port/json/version"
    while ((Get-Date) -lt $deadline) {
        try {
            $null = Invoke-RestMethod -Uri $url -TimeoutSec 5 -ErrorAction Stop
            return $true
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }
    return $false
}

if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing orchestrator script: $script"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Missing orchestrator config: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$chatUrl = [string]$config.chat_url
$chromeProfile = [string]$config.chrome_profile_dir
$debugHost = [string]$config.remote_debugging_host
$debugPort = [int]$config.remote_debugging_port
$chromeExe = Resolve-ChromePath

if ([string]::IsNullOrWhiteSpace($chromeProfile)) {
    $chromeProfile = Join-Path $env:TEMP "orchestrator-chatgpt-profile"
}
New-Item -ItemType Directory -Force -Path $chromeProfile | Out-Null
New-Item -ItemType Directory -Force -Path $statusDir | Out-Null

$existingDevtools = Wait-DevToolsReady -DebugHost $debugHost -Port $debugPort -TimeoutSeconds 2
if (-not $existingDevtools) {
    $owner = Get-DebugPortOwner -Port $debugPort
    if ($owner -and $owner.process_name -and $owner.process_name -ne "chrome") {
        throw ("Port debugowania {0} jest zajety przez proces PID={1} ({2}). Zwolnij port albo zatrzymaj obcy proces." -f $debugPort, $owner.pid, $owner.process_name)
    }

    $chromeArgs = @(
        "--remote-debugging-port=$debugPort",
        "--remote-debugging-address=$debugHost",
        "--remote-allow-origins=http://127.0.0.1:$debugPort,http://localhost:$debugPort",
        "--user-data-dir=$chromeProfile",
        "--no-first-run",
        "--disable-session-crashed-bubble",
        "--new-window",
        $chatUrl
    )

    Write-OrchLog ("Launching Chrome: {0} {1}" -f $chromeExe, ($chromeArgs -join " "))
    Start-Process -FilePath $chromeExe -ArgumentList $chromeArgs | Out-Null

    if (-not (Wait-DevToolsReady -DebugHost $debugHost -Port $debugPort -TimeoutSeconds 30)) {
        throw "Chrome uruchomil sie, ale DevTools nie odpowiada na porcie debugowym w wymaganym czasie."
    }
}
else {
    Write-OrchLog ("Reusing existing DevTools session on {0}:{1}" -f $debugHost, $debugPort)
}

$launcherStatus = [ordered]@{
    mode = $Mode
    chrome_exe = $chromeExe
    chrome_profile = $chromeProfile
    chat_url = $chatUrl
    chrome_debug_port = $debugPort
    devtools_ready = $true
    used_existing_session = $existingDevtools
    launched_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
$launcherStatus | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $statusDir "launcher_latest.json") -Encoding UTF8

$env:ORCH_CHROME_EXE = $chromeExe
$env:ORCH_CHROME_PROFILE_DIR = $chromeProfile
$env:ORCH_CHAT_URL = $chatUrl

$args = @($script, $Mode, "--config", $ConfigPath)
& $python @args
exit $LASTEXITCODE
