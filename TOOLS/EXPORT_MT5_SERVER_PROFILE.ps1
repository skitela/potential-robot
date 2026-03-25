param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfileRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\PACKAGE",
    [string]$SourceTerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profilePath = $ProfileRoot
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

function Resolve-PreferredCompiledSourceDir {
    param(
        [string]$ProjectPath,
        [string]$FallbackDir
    )

    $compileReportPath = Join-Path $ProjectPath "EVIDENCE\compile_all_microbots_report.json"
    if (Test-Path -LiteralPath $compileReportPath) {
        try {
            $report = Get-Content -LiteralPath $compileReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $freshest = @($report | Where-Object { $_.compile_ok -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$_.terminal_data_dir) }) |
                Group-Object terminal_data_dir |
                Sort-Object Count -Descending |
                Select-Object -First 1
            if ($null -ne $freshest -and -not [string]::IsNullOrWhiteSpace([string]$freshest.Name) -and (Test-Path -LiteralPath ([string]$freshest.Name))) {
                return [string]$freshest.Name
            }
        }
        catch {
        }
    }

    return $FallbackDir
}

$resolvedSourceTerminalDataDir = Resolve-PreferredCompiledSourceDir -ProjectPath $projectPath -FallbackDir $SourceTerminalDataDir

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

$packageExperts = Join-Path $profilePath "MQL5\\Experts\\MicroBots"
$packageCore = Join-Path $profilePath "MQL5\\Include\\Core"
$packageProfiles = Join-Path $profilePath "MQL5\\Include\\Profiles"
$packageStrategies = Join-Path $profilePath "MQL5\\Include\\Strategies"
$packagePresets = Join-Path $profilePath "MQL5\\Presets"
$packageActivePresets = Join-Path $profilePath "MQL5\\Presets\\ActiveLive"
$packageConfig = Join-Path $profilePath "CONFIG"
$configAllowList = @(
    "candidate_arbitration_contract_v1.json",
    "capital_risk_contract_v1.json",
    "core_capital_contract_v1.json",
    "domain_architecture_registry_v1.json",
    "family_policy_registry.json",
    "family_reference_registry.json",
    "microbots_registry.json",
    "project_config.json",
    "rollover_guard_v1.json",
    "session_capital_coordinator_v1.json",
    "session_window_matrix_v1.json",
    "tuning_cost_window_guard_matrix_v1.json",
    "tuning_fleet_registry.json"
)

foreach ($cleanDir in @($packageExperts, $packageCore, $packageProfiles, $packageStrategies, $packagePresets, $packageActivePresets, $packageConfig)) {
    if (Test-Path -LiteralPath $cleanDir) {
        Get-ChildItem -LiteralPath $cleanDir -Force | Remove-Item -Recurse -Force
    }
}

foreach ($dir in @($packageExperts, $packageCore, $packageProfiles, $packageStrategies, $packagePresets, $packageActivePresets, $packageConfig)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

foreach ($file in @(Get-ChildItem -LiteralPath $packageConfig -File -Filter "*.json" -ErrorAction SilentlyContinue)) {
    Remove-Item -LiteralPath $file.FullName -Force
}

$copiedExperts = New-Object System.Collections.Generic.List[string]
$copiedProfiles = New-Object System.Collections.Generic.List[string]
$copiedStrategies = New-Object System.Collections.Generic.List[string]
$copiedPresets = New-Object System.Collections.Generic.List[string]
$copiedActivePresets = New-Object System.Collections.Generic.List[string]
$copiedConfigs = New-Object System.Collections.Generic.List[string]

foreach ($row in @($registry.symbols)) {
    $expert = [string]$row.expert
    $preset = [string]$row.preset
    $codeSymbol = Get-CodeSymbolFromRegistryRow -Row $row

    $sourceMq5 = Join-Path $projectPath ("MQL5\\Experts\\MicroBots\\{0}.mq5" -f $expert)
    $sourceProfile = Join-Path $projectPath ("MQL5\\Include\\Profiles\\Profile_{0}.mqh" -f $codeSymbol)
    $sourceStrategy = Join-Path $projectPath ("MQL5\\Include\\Strategies\\Strategy_{0}.mqh" -f $codeSymbol)
    $sourcePreset = Join-Path $projectPath ("MQL5\\Presets\\{0}" -f $preset)
    $activePresetName = "{0}_ACTIVE.set" -f ([System.IO.Path]::GetFileNameWithoutExtension($preset))
    $targetActivePreset = Join-Path $packageActivePresets $activePresetName

    foreach ($requiredPath in @($sourceMq5, $sourceProfile, $sourceStrategy, $sourcePreset)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Missing active migration artifact: $requiredPath"
        }
    }

    Copy-Item -LiteralPath $sourceMq5 -Destination $packageExperts -Force
    Copy-Item -LiteralPath $sourceProfile -Destination $packageProfiles -Force
    Copy-Item -LiteralPath $sourceStrategy -Destination $packageStrategies -Force
    Copy-Item -LiteralPath $sourcePreset -Destination $packagePresets -Force

    $presetContent = Get-Content -LiteralPath $sourcePreset
    $activePresetContent = foreach ($line in $presetContent) {
        if ($line -match '^InpEnableLiveEntries=') {
            'InpEnableLiveEntries=true'
        }
        else {
            $line
        }
    }
    Set-Content -LiteralPath $targetActivePreset -Value $activePresetContent -Encoding ASCII

    [void]$copiedExperts.Add([System.IO.Path]::GetFileName($sourceMq5))
    [void]$copiedProfiles.Add([System.IO.Path]::GetFileName($sourceProfile))
    [void]$copiedStrategies.Add([System.IO.Path]::GetFileName($sourceStrategy))
    [void]$copiedPresets.Add([System.IO.Path]::GetFileName($sourcePreset))
    [void]$copiedActivePresets.Add($activePresetName)
}

Copy-Item (Join-Path $projectPath "MQL5\\Include\\Core\\*.mqh") $packageCore -Force
foreach ($configName in $configAllowList) {
    $sourceConfig = Join-Path $projectPath ("CONFIG\\{0}" -f $configName)
    if (-not (Test-Path -LiteralPath $sourceConfig)) {
        throw "Missing active migration config: $sourceConfig"
    }

    Copy-Item -LiteralPath $sourceConfig -Destination $packageConfig -Force
    [void]$copiedConfigs.Add($configName)
}

$sourceExperts = Join-Path $resolvedSourceTerminalDataDir "MQL5\\Experts\\MicroBots"
if (Test-Path -LiteralPath $sourceExperts) {
    foreach ($row in @($registry.symbols)) {
        $expert = [string]$row.expert
        $sourceEx5 = Join-Path $sourceExperts ("{0}.ex5" -f $expert)
        if (-not (Test-Path -LiteralPath $sourceEx5)) {
            throw "Missing compiled active expert: $sourceEx5"
        }

        Copy-Item -LiteralPath $sourceEx5 -Destination $packageExperts -Force
        [void]$copiedExperts.Add([System.IO.Path]::GetFileName($sourceEx5))
    }
}

$activeSymbols = @($registry.symbols | ForEach-Object { [string]$_.symbol })

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
        "CONFIG\\selected_runtime_json"
    )
    source_terminal_data_dir = $resolvedSourceTerminalDataDir
    active_symbols = $activeSymbols
    copied_inventory = [ordered]@{
        experts = @($copiedExperts | Sort-Object -Unique)
        profiles = @($copiedProfiles | Sort-Object -Unique)
        strategies = @($copiedStrategies | Sort-Object -Unique)
        presets = @($copiedPresets | Sort-Object -Unique)
        active_presets = @($copiedActivePresets | Sort-Object -Unique)
        configs = @($copiedConfigs | Sort-Object -Unique)
    }
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $profilePath "server_profile_manifest.json") -Encoding UTF8
Write-Host "Exported MT5 server profile package to $profilePath"
