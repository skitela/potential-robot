param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfileRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\PACKAGE",
    [string]$SourceTerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profilePath = $ProfileRoot

$dirs = @(
    $profilePath,
    (Join-Path $profilePath "MQL5"),
    (Join-Path $profilePath "MQL5\\Experts"),
    (Join-Path $profilePath "MQL5\\Experts\\MicroBots"),
    (Join-Path $profilePath "MQL5\\Include"),
    (Join-Path $profilePath "MQL5\\Include\\Core"),
    (Join-Path $profilePath "MQL5\\Include\\Profiles"),
    (Join-Path $profilePath "MQL5\\Include\\Strategies"),
    (Join-Path $profilePath "MQL5\\Presets"),
    (Join-Path $profilePath "MQL5\\Presets\\ActiveLive"),
    (Join-Path $profilePath "CONFIG"),
    (Join-Path $profilePath "COMMON\\Files\\MAKRO_I_MIKRO_BOT")
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Copy-Item (Join-Path $projectPath "MQL5\\Experts\\MicroBots\\*.mq5") (Join-Path $profilePath "MQL5\\Experts\\MicroBots") -Force
Copy-Item (Join-Path $projectPath "MQL5\\Include\\Core\\*.mqh") (Join-Path $profilePath "MQL5\\Include\\Core") -Force
Copy-Item (Join-Path $projectPath "MQL5\\Include\\Profiles\\*.mqh") (Join-Path $profilePath "MQL5\\Include\\Profiles") -Force
Copy-Item (Join-Path $projectPath "MQL5\\Include\\Strategies\\*.mqh") (Join-Path $profilePath "MQL5\\Include\\Strategies") -Force
Copy-Item (Join-Path $projectPath "MQL5\\Presets\\*.set") (Join-Path $profilePath "MQL5\\Presets") -Force
if (Test-Path -LiteralPath (Join-Path $projectPath "MQL5\\Presets\\ActiveLive")) {
    Copy-Item (Join-Path $projectPath "MQL5\\Presets\\ActiveLive\\*.set") (Join-Path $profilePath "MQL5\\Presets\\ActiveLive") -Force
}
Copy-Item (Join-Path $projectPath "CONFIG\\*.json") (Join-Path $profilePath "CONFIG") -Force

$sourceExperts = Join-Path $SourceTerminalDataDir "MQL5\\Experts\\MicroBots"
if (Test-Path -LiteralPath $sourceExperts) {
    Copy-Item (Join-Path $sourceExperts "MicroBot_*.ex5") (Join-Path $profilePath "MQL5\\Experts\\MicroBots") -Force
}

$manifest = [ordered]@{
    schema_version = "1.0"
    profile_name = "MAKRO_I_MIKRO_BOT_MT5_ONLY_PACKAGE"
    package_root = $profilePath
    runtime_model = "mql5_only_microbots"
    deployment_model = "one_microbot_per_chart"
    copied = @(
        "MQL5\\Experts\\MicroBots\\*.mq5",
        "MQL5\\Include\\Core\\*.mqh",
        "MQL5\\Include\\Profiles\\*.mqh",
        "MQL5\\Include\\Strategies\\*.mqh",
        "MQL5\\Presets\\*.set",
        "MQL5\\Presets\\ActiveLive\\*.set",
        "MQL5\\Experts\\MicroBots\\*.ex5",
        "CONFIG\\*.json"
    )
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $profilePath "server_profile_manifest.json") -Encoding UTF8
Write-Host "Exported MT5 server profile package to $profilePath"
