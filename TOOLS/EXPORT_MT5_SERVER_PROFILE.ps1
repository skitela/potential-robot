param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfileRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\PACKAGE",
    [string]$SourceTerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-CodeSymbolFromRegistryRow {
    param(
        [psobject]$Row
    )

    if ($Row.PSObject.Properties.Name -contains 'code_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$Row.code_symbol)) {
        return [string]$Row.code_symbol
    }

    return ([string]$Row.expert).Replace("MicroBot_", "")
}

function Resolve-ResearchPython {
    param([string]$PreferredPath)

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path -LiteralPath $PreferredPath)) {
        return (Resolve-Path -LiteralPath $PreferredPath).Path
    }

    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        return [string]$command.Source
    }

    throw "Python executable not found for teacher package export."
}

function Get-DeploymentBucketForSymbol {
    param(
        [string]$Symbol,
        [object]$UniversePlan
    )

    $paperLiveFirstWave = @($UniversePlan.paper_live_first_wave | ForEach-Object { [string]$_ })
    $paperLiveSecondWave = @($UniversePlan.paper_live_second_wave | ForEach-Object { [string]$_ })
    $paperLiveHold = @($UniversePlan.paper_live_hold | ForEach-Object { [string]$_ })

    if ($paperLiveFirstWave -contains $Symbol) {
        return "PAPER_LIVE_FIRST_WAVE"
    }
    if ($paperLiveSecondWave -contains $Symbol) {
        return "PAPER_LIVE_SECOND_WAVE"
    }
    if ($paperLiveHold -contains $Symbol) {
        return "PAPER_LIVE_HOLD"
    }

    return "GLOBAL_TEACHER_ONLY"
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

function Resolve-CompiledExpertPath {
    param(
        [string]$PreferredTerminalDataDir,
        [string]$ExpertName
    )

    $preferredPath = Join-Path $PreferredTerminalDataDir ("MQL5\\Experts\\MicroBots\\{0}.ex5" -f $ExpertName)
    if (Test-Path -LiteralPath $preferredPath) {
        return $preferredPath
    }

    $terminalRoot = Split-Path -Path $PreferredTerminalDataDir -Parent
    if (-not (Test-Path -LiteralPath $terminalRoot)) {
        return $null
    }

    $matches = @(Get-ChildItem -LiteralPath $terminalRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Common', 'Community', 'Help') } |
        ForEach-Object {
            Join-Path $_.FullName ("MQL5\\Experts\\MicroBots\\{0}.ex5" -f $ExpertName)
        } |
        Where-Object { Test-Path -LiteralPath $_ })

    if ($matches.Count -gt 0) {
        return [string]$matches[0]
    }

    return $null
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$profilePath = $ProfileRoot
$registryPath = Join-Path $projectPath "CONFIG\microbots_registry.json"
$planPath = Join-Path $projectPath "CONFIG\scalping_universe_plan.json"
$curriculaRegistryPath = Join-Path $projectPath "CONFIG\personal_teacher_curricula_registry_v1.json"
$globalCurriculumPath = Join-Path $projectPath "CONFIG\global_teacher_curriculum_v1.json"
$teacherPolicyPath = Join-Path $projectPath "CONFIG\teacher_promotion_policy_v1.json"
$teacherPackageBuilderPath = Join-Path $projectPath "CONTROL\build_teacher_package.py"

foreach ($requiredPath in @($registryPath, $planPath, $curriculaRegistryPath, $globalCurriculumPath, $teacherPackageBuilderPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Missing required export dependency: $requiredPath"
    }
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
$curriculaRegistry = Get-Content -LiteralPath $curriculaRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$planHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $planPath).Hash
$paperLiveSymbols = @($plan.paper_live_first_wave | ForEach-Object { [string]$_ })
$trainingUniverse = @($plan.training_universe | ForEach-Object { [string]$_ })
$retiredSymbols = @($plan.retired_symbols | ForEach-Object { [string]$_ })
$teacherPackagePython = Resolve-ResearchPython -PreferredPath $ResearchPython

$curriculumFileBySymbol = @{}
foreach ($entry in @($curriculaRegistry.active_training_universe)) {
    $curriculumFileBySymbol[[string]$entry.symbol] = [string]$entry.curriculum_file
}

$resolvedSourceTerminalDataDir = $null
if (-not [string]::IsNullOrWhiteSpace($SourceTerminalDataDir) -and (Test-Path -LiteralPath $SourceTerminalDataDir)) {
    $resolvedSourceTerminalDataDir = (Resolve-Path -LiteralPath $SourceTerminalDataDir).Path
}
else {
    $resolvedSourceTerminalDataDir = Resolve-PreferredCompiledSourceDir -ProjectPath $projectPath -FallbackDir $SourceTerminalDataDir
}

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
    (Join-Path $profilePath "COMMON\\Files\\MAKRO_I_MIKRO_BOT"),
    (Join-Path $profilePath "COMMON\\Files\\MAKRO_I_MIKRO_BOT\\state")
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
$packageCommonStateRoot = Join-Path $profilePath "COMMON\\Files\\MAKRO_I_MIKRO_BOT\\state"
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

foreach ($cleanDir in @($packageExperts, $packageCore, $packageProfiles, $packageStrategies, $packagePresets, $packageActivePresets, $packageConfig, $packageCommonStateRoot)) {
    if (Test-Path -LiteralPath $cleanDir) {
        Get-ChildItem -LiteralPath $cleanDir -Force | Remove-Item -Recurse -Force
    }
}

foreach ($dir in @($packageExperts, $packageCore, $packageProfiles, $packageStrategies, $packagePresets, $packageActivePresets, $packageConfig, $packageCommonStateRoot)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$copiedExperts = New-Object System.Collections.Generic.List[string]
$copiedProfiles = New-Object System.Collections.Generic.List[string]
$copiedStrategies = New-Object System.Collections.Generic.List[string]
$copiedPresets = New-Object System.Collections.Generic.List[string]
$copiedActivePresets = New-Object System.Collections.Generic.List[string]
$copiedConfigs = New-Object System.Collections.Generic.List[string]
$copiedTeacherPackageStates = New-Object System.Collections.Generic.List[string]

foreach ($row in @($registry.symbols)) {
    $expert = [string]$row.expert
    $preset = [string]$row.preset
    $symbol = [string]$row.symbol
    $codeSymbol = Get-CodeSymbolFromRegistryRow -Row $row

    $sourceMq5 = Join-Path $projectPath ("MQL5\\Experts\\MicroBots\\{0}.mq5" -f $expert)
    $sourceProfile = Join-Path $projectPath ("MQL5\\Include\\Profiles\\Profile_{0}.mqh" -f $codeSymbol)
    $sourceStrategy = Join-Path $projectPath ("MQL5\\Include\\Strategies\\Strategy_{0}.mqh" -f $codeSymbol)
    $sourcePreset = Join-Path $projectPath ("MQL5\\Presets\\{0}" -f $preset)
    $shouldGenerateActivePreset = ($paperLiveSymbols -contains $symbol)
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

    [void]$copiedExperts.Add([System.IO.Path]::GetFileName($sourceMq5))
    [void]$copiedProfiles.Add([System.IO.Path]::GetFileName($sourceProfile))
    [void]$copiedStrategies.Add([System.IO.Path]::GetFileName($sourceStrategy))
    [void]$copiedPresets.Add([System.IO.Path]::GetFileName($sourcePreset))
    if ($shouldGenerateActivePreset) {
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
        [void]$copiedActivePresets.Add($activePresetName)
    }

    if (-not $curriculumFileBySymbol.ContainsKey($symbol)) {
        throw "Missing personal curriculum registry entry for symbol: $symbol"
    }

    $curriculumFile = [string]$curriculumFileBySymbol[$symbol]
    $curriculumPath = Join-Path $projectPath ("CONFIG\\{0}" -f $curriculumFile)
    if (-not (Test-Path -LiteralPath $curriculumPath)) {
        throw "Missing curriculum file for symbol ${symbol}: $curriculumPath"
    }

    $teacherOutDir = Join-Path $packageCommonStateRoot $symbol
    New-Item -ItemType Directory -Force -Path $teacherOutDir | Out-Null

    $teacherBuildArgs = @(
        $teacherPackageBuilderPath,
        "--curriculum", $curriculumPath,
        "--global-curriculum", $globalCurriculumPath,
        "--out-dir", $teacherOutDir,
        "--deployment-bucket", (Get-DeploymentBucketForSymbol -Symbol $symbol -UniversePlan $plan)
    )
    if (Test-Path -LiteralPath $teacherPolicyPath) {
        $teacherBuildArgs += @("--policy", $teacherPolicyPath)
    }

    & $teacherPackagePython @teacherBuildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Teacher package build failed for symbol: $symbol"
    }

    [void]$copiedTeacherPackageStates.Add($symbol)
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
        $sourceEx5 = Resolve-CompiledExpertPath -PreferredTerminalDataDir $resolvedSourceTerminalDataDir -ExpertName $expert
        if ([string]::IsNullOrWhiteSpace($sourceEx5)) {
            throw "Missing compiled active expert across MT5 terminals: $expert"
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
    universe_version = [string]$plan.universe_version
    plan_hash = $planHash
    runtime_model = "mql5_only_microbots"
    deployment_model = "one_microbot_per_chart"
    training_universe = $trainingUniverse
    paper_live_universe = $paperLiveSymbols
    paper_live_second_wave = @($plan.paper_live_second_wave | ForEach-Object { [string]$_ })
    paper_live_hold = @($plan.paper_live_hold | ForEach-Object { [string]$_ })
    global_teacher_only = @($plan.global_teacher_only | ForEach-Object { [string]$_ })
    retired_symbols = $retiredSymbols
    copied = @(
        "MQL5\\Experts\\MicroBots\\*.mq5",
        "MQL5\\Include\\Core\\*.mqh",
        "MQL5\\Include\\Profiles\\*.mqh",
        "MQL5\\Include\\Strategies\\*.mqh",
        "MQL5\\Presets\\*.set",
        "MQL5\\Presets\\ActiveLive\\*.set",
        "MQL5\\Experts\\MicroBots\\*.ex5",
        "CONFIG\\selected_runtime_json",
        "COMMON\\Files\\MAKRO_I_MIKRO_BOT\\state\\<symbol>\\teacher_package_contract.csv",
        "COMMON\\Files\\MAKRO_I_MIKRO_BOT\\state\\<symbol>\\teacher_package_manifest_latest.json"
    )
    source_terminal_data_dir = $resolvedSourceTerminalDataDir
    teacher_package_python = $teacherPackagePython
    active_symbols = $activeSymbols
    active_live_symbols = $paperLiveSymbols
    copied_inventory = [ordered]@{
        experts = @($copiedExperts | Sort-Object -Unique)
        profiles = @($copiedProfiles | Sort-Object -Unique)
        strategies = @($copiedStrategies | Sort-Object -Unique)
        presets = @($copiedPresets | Sort-Object -Unique)
        active_presets = @($copiedActivePresets | Sort-Object -Unique)
        configs = @($copiedConfigs | Sort-Object -Unique)
        teacher_package_state = @($copiedTeacherPackageStates | Sort-Object -Unique)
    }
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $profilePath "server_profile_manifest.json") -Encoding UTF8
Write-Host "Exported MT5 server profile package to $profilePath"
