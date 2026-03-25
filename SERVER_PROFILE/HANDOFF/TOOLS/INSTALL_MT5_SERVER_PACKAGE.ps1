param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$PackageRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\PACKAGE",
    [string]$TargetTerminalDataDir,
    [string]$TargetCommonFilesDir = (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"),
    [switch]$CreateRuntimeFolders,
    [switch]$AllowBlockedAuditGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TargetTerminalDataDir)) {
    throw "TargetTerminalDataDir is required."
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$packagePath = (Resolve-Path -LiteralPath $PackageRoot).Path
$targetTerminal = $TargetTerminalDataDir
$targetCommon = $TargetCommonFilesDir
$registryPath = Join-Path $projectPath "CONFIG\microbots_registry.json"

if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing registry: $registryPath"
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-CodeSymbolFromRegistryRow {
    param(
        [psobject]$Row
    )

    if ($Row.PSObject.Properties.Name -contains 'code_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$Row.code_symbol)) {
        return [string]$Row.code_symbol
    }

    return ([string]$Row.expert).Replace("MicroBot_", "")
}

& (Join-Path $projectPath "TOOLS\ASSERT_AUDIT_SUPERVISOR_GATE.ps1") `
    -ProjectRoot $projectPath `
    -GateType ROLLOUT `
    -AllowBlocked:$AllowBlockedAuditGate | Out-Null

$targetExperts = Join-Path $targetTerminal "MQL5\Experts\MicroBots"
$targetCore = Join-Path $targetTerminal "MQL5\Include\Core"
$targetProfiles = Join-Path $targetTerminal "MQL5\Include\Profiles"
$targetStrategies = Join-Path $targetTerminal "MQL5\Include\Strategies"
$targetPresets = Join-Path $targetTerminal "MQL5\Presets"
$targetActivePresets = Join-Path $targetPresets "ActiveLive"
$targetConfig = Join-Path $targetTerminal "MAKRO_I_MIKRO_BOT\CONFIG"
$targetCommonRoot = Join-Path $targetCommon "MAKRO_I_MIKRO_BOT"

$dirs = @(
    $targetExperts,
    $targetCore,
    $targetProfiles,
    $targetStrategies,
    $targetPresets,
    $targetActivePresets,
    $targetConfig,
    $targetCommonRoot
)

if ($CreateRuntimeFolders) {
    $dirs += @(
        (Join-Path $targetCommonRoot "state"),
        (Join-Path $targetCommonRoot "logs"),
        (Join-Path $targetCommonRoot "run")
    )
}

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$allowedExpertFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$allowedProfileFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$allowedStrategyFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$allowedPresetFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$allowedActivePresetFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($row in @($registry.symbols)) {
    $expert = [string]$row.expert
    $preset = [string]$row.preset
    $codeSymbol = Get-CodeSymbolFromRegistryRow -Row $row
    $activePresetName = "{0}_ACTIVE.set" -f ([System.IO.Path]::GetFileNameWithoutExtension($preset))

    [void]$allowedExpertFiles.Add(("{0}.mq5" -f $expert))
    [void]$allowedExpertFiles.Add(("{0}.ex5" -f $expert))
    [void]$allowedProfileFiles.Add(("Profile_{0}.mqh" -f $codeSymbol))
    [void]$allowedStrategyFiles.Add(("Strategy_{0}.mqh" -f $codeSymbol))
    [void]$allowedPresetFiles.Add($preset)
    [void]$allowedActivePresetFiles.Add($activePresetName)
}

foreach ($file in @(Get-ChildItem -LiteralPath $targetExperts -File -ErrorAction SilentlyContinue)) {
    if (-not $allowedExpertFiles.Contains($file.Name)) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
}
foreach ($file in @(Get-ChildItem -LiteralPath $targetProfiles -File -ErrorAction SilentlyContinue)) {
    if (-not $allowedProfileFiles.Contains($file.Name)) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
}
foreach ($file in @(Get-ChildItem -LiteralPath $targetStrategies -File -ErrorAction SilentlyContinue)) {
    if (-not $allowedStrategyFiles.Contains($file.Name)) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
}
foreach ($file in @(Get-ChildItem -LiteralPath $targetPresets -File -Filter "*.set" -ErrorAction SilentlyContinue)) {
    if (-not $allowedPresetFiles.Contains($file.Name)) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
}
foreach ($file in @(Get-ChildItem -LiteralPath $targetActivePresets -File -Filter "*.set" -ErrorAction SilentlyContinue)) {
    if (-not $allowedActivePresetFiles.Contains($file.Name)) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
}

Copy-Item (Join-Path $packagePath "MQL5\Experts\MicroBots\*.mq5") $targetExperts -Force
if (Test-Path -LiteralPath (Join-Path $packagePath "MQL5\Experts\MicroBots")) {
    Copy-Item (Join-Path $packagePath "MQL5\Experts\MicroBots\*.ex5") $targetExperts -Force -ErrorAction SilentlyContinue
}
Copy-Item (Join-Path $packagePath "MQL5\Include\Core\*.mqh") $targetCore -Force
Copy-Item (Join-Path $packagePath "MQL5\Include\Profiles\*.mqh") $targetProfiles -Force
Copy-Item (Join-Path $packagePath "MQL5\Include\Strategies\*.mqh") $targetStrategies -Force
Copy-Item (Join-Path $packagePath "MQL5\Presets\*.set") $targetPresets -Force
if (Test-Path -LiteralPath (Join-Path $packagePath "MQL5\Presets\ActiveLive")) {
    Copy-Item (Join-Path $packagePath "MQL5\Presets\ActiveLive\*.set") $targetActivePresets -Force
}
Copy-Item (Join-Path $packagePath "CONFIG\*.json") $targetConfig -Force

$manifest = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    package_root = $packagePath
    target_terminal_data_dir = $targetTerminal
    target_common_files_dir = $targetCommon
    copied = @(
        "MQL5\Experts\MicroBots\*.mq5",
        "MQL5\Experts\MicroBots\*.ex5",
        "MQL5\Include\Core\*.mqh",
        "MQL5\Include\Profiles\*.mqh",
        "MQL5\Include\Strategies\*.mqh",
        "MQL5\Presets\*.set",
        "MQL5\Presets\ActiveLive\*.set",
        "CONFIG\*.json"
    )
    create_runtime_folders = [bool]$CreateRuntimeFolders
}

$jsonPath = Join-Path $projectPath "EVIDENCE\install_mt5_server_package_report.json"
$txtPath = Join-Path $projectPath "EVIDENCE\install_mt5_server_package_report.txt"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $txtPath -Encoding ASCII
$manifest | ConvertTo-Json -Depth 6
