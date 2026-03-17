param(
    [string]$RemoteRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$dirs = @(
    $RemoteRoot,
    (Join-Path $RemoteRoot "CONFIG"),
    (Join-Path $RemoteRoot "DOCS"),
    (Join-Path $RemoteRoot "MQL5"),
    (Join-Path $RemoteRoot "MQL5\\Experts"),
    (Join-Path $RemoteRoot "MQL5\\Experts\\MicroBots"),
    (Join-Path $RemoteRoot "MQL5\\Include"),
    (Join-Path $RemoteRoot "MQL5\\Include\\Core"),
    (Join-Path $RemoteRoot "MQL5\\Include\\Profiles"),
    (Join-Path $RemoteRoot "MQL5\\Include\\Strategies"),
    (Join-Path $RemoteRoot "MQL5\\Presets"),
    (Join-Path $RemoteRoot "RUN"),
    (Join-Path $RemoteRoot "STATE"),
    (Join-Path $RemoteRoot "LOGS"),
    (Join-Path $RemoteRoot "EVIDENCE"),
    (Join-Path $RemoteRoot "TOOLS"),
    (Join-Path $RemoteRoot "BACKUP")
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$result = [ordered]@{
    schema = "makro_i_mikro_bot.remote.bootstrap.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    remote_root = $RemoteRoot
    directories_created = @($dirs)
    status = "OK"
}

$result | ConvertTo-Json -Depth 6
