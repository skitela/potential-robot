param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$packageRoot = Join-Path $projectPath "SERVER_PROFILE\PACKAGE"
$handoffRoot = Join-Path $projectPath "SERVER_PROFILE\HANDOFF"
$issues = New-Object System.Collections.Generic.List[string]
$registryPath = Join-Path $projectPath "CONFIG\microbots_registry.json"
$planPath = Join-Path $projectPath "CONFIG\scalping_universe_plan.json"

if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing registry: $registryPath"
}
if (-not (Test-Path -LiteralPath $planPath)) {
    throw "Missing scalping universe plan: $planPath"
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
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

function Get-CodeSymbolFromRegistryRow {
    param(
        [psobject]$Row
    )

    if ($Row.PSObject.Properties.Name -contains 'code_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$Row.code_symbol)) {
        return [string]$Row.code_symbol
    }

    return ([string]$Row.expert).Replace("MicroBot_", "")
}

function Get-RelativeNames {
    param(
        [string]$LiteralPath,
        [string]$Filter = "*"
    )

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $LiteralPath -File -Filter $Filter |
            Select-Object -ExpandProperty Name |
            Sort-Object -Unique
    )
}

$required = @(
    (Join-Path $packageRoot "server_profile_manifest.json"),
    (Join-Path $handoffRoot "handoff_manifest.json"),
    (Join-Path $handoffRoot "HANDOFF_SUMMARY.txt"),
    (Join-Path $handoffRoot "DOCS\06_MT5_CHART_ATTACHMENT_PLAN.json"),
    (Join-Path $handoffRoot "DOCS\10_OPERATOR_ROLLOUT_CHECKLIST.md"),
    (Join-Path $handoffRoot "DOCS\11_REMOTE_MT5_INSTALL.md"),
    (Join-Path $handoffRoot "DOCS\24_FAMILY_SCENARIO_TESTS_AND_OPERATOR_REPORTS.md"),
    (Join-Path $handoffRoot "DOCS\25_DZIENNE_RAPORTY_I_DASHBOARD_PL.md"),
    (Join-Path $handoffRoot "DOCS\26_RAPORT_WIECZORNY_WLASCICIELA_PL.md"),
    (Join-Path $handoffRoot "EVIDENCE\prepare_mt5_rollout_report.json"),
    (Join-Path $handoffRoot "EVIDENCE\deployment_readiness_report.json"),
    (Join-Path $handoffRoot "EVIDENCE\preset_safety_report.json"),
    (Join-Path $handoffRoot "EVIDENCE\family_scenario_test_report.json"),
    (Join-Path $handoffRoot "EVIDENCE\family_operator_report.json"),
    (Join-Path $handoffRoot "EVIDENCE\runtime_control_summary.json"),
    (Join-Path $handoffRoot "EVIDENCE\OPS\mt5_pretrade_execution_truth_status_latest.json"),
    (Join-Path $handoffRoot "EVIDENCE\OPS\mt5_pretrade_execution_truth_status_latest.md"),
    (Join-Path $handoffRoot "EVIDENCE\daily_reports_generation_report.json"),
    (Join-Path $handoffRoot "EVIDENCE\evening_reports_generation_report.json"),
    (Join-Path $handoffRoot "EVIDENCE\DAILY\raport_dzienny_latest.txt"),
    (Join-Path $handoffRoot "EVIDENCE\DAILY\dashboard_dzienny_latest.html"),
    (Join-Path $handoffRoot "EVIDENCE\DAILY\raport_wieczorny_latest.txt"),
    (Join-Path $handoffRoot "EVIDENCE\DAILY\dashboard_wieczorny_latest.html"),
    (Join-Path $handoffRoot "EVIDENCE\simulate_mt5_server_install_report.json"),
    (Join-Path $handoffRoot "TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1"),
    (Join-Path $handoffRoot "TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1"),
    (Join-Path $handoffRoot "TOOLS\GENERATE_FAMILY_OPERATOR_REPORT.ps1"),
    (Join-Path $handoffRoot "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1"),
    (Join-Path $handoffRoot "TOOLS\REGISTER_DAILY_REPORT_TASK.ps1"),
    (Join-Path $handoffRoot "TOOLS\GENERATE_EVENING_OWNER_REPORT.ps1"),
    (Join-Path $handoffRoot "TOOLS\REGISTER_EVENING_REPORT_TASK.ps1"),
    (Join-Path $handoffRoot "TOOLS\SET_RUNTIME_CONTROL_PL.ps1"),
    (Join-Path $handoffRoot "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"),
    (Join-Path $handoffRoot "RUN\GENERATE_DAILY_REPORTS_NOW.ps1"),
    (Join-Path $handoffRoot "RUN\GENERATE_EVENING_REPORT_NOW.ps1"),
    (Join-Path $handoffRoot "RUN\PANEL_OPERATORA_PL.ps1"),
    (Join-Path $handoffRoot "RUN\WLACZ_TRYB_NORMALNY_SYSTEMU.ps1"),
    (Join-Path $handoffRoot "RUN\WLACZ_CLOSE_ONLY_SYSTEMU.ps1"),
    (Join-Path $handoffRoot "RUN\ZATRZYMAJ_SYSTEM.ps1")
)

foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        $issues.Add("MISSING:" + $path)
    }
}

$packageManifest = $null
$handoffManifest = $null

if (Test-Path -LiteralPath (Join-Path $packageRoot "server_profile_manifest.json")) {
    $packageManifest = Get-Content -Raw (Join-Path $packageRoot "server_profile_manifest.json") | ConvertFrom-Json
}

if (Test-Path -LiteralPath (Join-Path $handoffRoot "handoff_manifest.json")) {
    $handoffManifest = Get-Content -Raw (Join-Path $handoffRoot "handoff_manifest.json") | ConvertFrom-Json
}

if ($null -ne $packageManifest) {
    if ($packageManifest.runtime_model -ne "mql5_only_microbots") {
        $issues.Add("PACKAGE_RUNTIME_MODEL_INVALID")
    }
    if ($packageManifest.deployment_model -ne "one_microbot_per_chart") {
        $issues.Add("PACKAGE_DEPLOYMENT_MODEL_INVALID")
    }
}

if ($null -ne $handoffManifest) {
    if (-not ($handoffManifest.copied -contains "DOCS\10_OPERATOR_ROLLOUT_CHECKLIST.md")) {
        $issues.Add("HANDOFF_CHECKLIST_NOT_DECLARED")
    }
    if (-not ($handoffManifest.copied -contains "EVIDENCE\prepare_mt5_rollout_report.json")) {
        $issues.Add("HANDOFF_PREFLIGHT_REPORT_NOT_DECLARED")
    }
    if (-not ($handoffManifest.copied -contains "EVIDENCE\family_operator_report.json")) {
        $issues.Add("HANDOFF_FAMILY_OPERATOR_REPORT_NOT_DECLARED")
    }
    if (-not ($handoffManifest.copied -contains "EVIDENCE\OPS\mt5_pretrade_execution_truth_status_latest.json")) {
        $issues.Add("HANDOFF_TRUTH_STATUS_JSON_NOT_DECLARED")
    }
    if (-not ($handoffManifest.copied -contains "EVIDENCE\OPS\mt5_pretrade_execution_truth_status_latest.md")) {
        $issues.Add("HANDOFF_TRUTH_STATUS_MD_NOT_DECLARED")
    }
    if (-not ($handoffManifest.copied -contains "RUN\GENERATE_DAILY_REPORTS_NOW.ps1")) {
        $issues.Add("HANDOFF_DAILY_REPORT_RUNNER_NOT_DECLARED")
    }
    if (-not ($handoffManifest.copied -contains "RUN\GENERATE_EVENING_REPORT_NOW.ps1")) {
        $issues.Add("HANDOFF_EVENING_REPORT_RUNNER_NOT_DECLARED")
    }
}

$expectedExperts = New-Object System.Collections.Generic.List[string]
$expectedProfiles = New-Object System.Collections.Generic.List[string]
$expectedStrategies = New-Object System.Collections.Generic.List[string]
$expectedPresets = New-Object System.Collections.Generic.List[string]
$expectedActivePresets = New-Object System.Collections.Generic.List[string]
$expectedActiveSymbols = New-Object System.Collections.Generic.List[string]
$paperLiveSymbols = @($plan.paper_live_first_wave | ForEach-Object { [string]$_ })

foreach ($row in @($registry.symbols)) {
    $expert = [string]$row.expert
    $preset = [string]$row.preset
    $codeSymbol = Get-CodeSymbolFromRegistryRow -Row $row
    $activePresetName = "{0}_ACTIVE.set" -f ([System.IO.Path]::GetFileNameWithoutExtension($preset))

    [void]$expectedExperts.Add(("{0}.mq5" -f $expert))
    [void]$expectedExperts.Add(("{0}.ex5" -f $expert))
    [void]$expectedProfiles.Add(("Profile_{0}.mqh" -f $codeSymbol))
    [void]$expectedStrategies.Add(("Strategy_{0}.mqh" -f $codeSymbol))
    [void]$expectedPresets.Add($preset)
    if ($paperLiveSymbols -contains [string]$row.symbol) {
        [void]$expectedActivePresets.Add($activePresetName)
    }
    [void]$expectedActiveSymbols.Add([string]$row.symbol)
}

$expectedExperts = @($expectedExperts | Sort-Object -Unique)
$expectedProfiles = @($expectedProfiles | Sort-Object -Unique)
$expectedStrategies = @($expectedStrategies | Sort-Object -Unique)
$expectedPresets = @($expectedPresets | Sort-Object -Unique)
$expectedActivePresets = @($expectedActivePresets | Sort-Object -Unique)
$expectedActiveSymbols = @($expectedActiveSymbols | Sort-Object -Unique)

$packageExperts = Get-RelativeNames -LiteralPath (Join-Path $packageRoot "MQL5\Experts\MicroBots")
$packageProfiles = Get-RelativeNames -LiteralPath (Join-Path $packageRoot "MQL5\Include\Profiles")
$packageStrategies = Get-RelativeNames -LiteralPath (Join-Path $packageRoot "MQL5\Include\Strategies")
$packagePresets = Get-RelativeNames -LiteralPath (Join-Path $packageRoot "MQL5\Presets") -Filter "*.set"
$packageActivePresets = Get-RelativeNames -LiteralPath (Join-Path $packageRoot "MQL5\Presets\ActiveLive") -Filter "*.set"
$packageConfigs = Get-RelativeNames -LiteralPath (Join-Path $packageRoot "CONFIG") -Filter "*.json"

$extraExperts = @($packageExperts | Where-Object { $_ -notin $expectedExperts })
$extraProfiles = @($packageProfiles | Where-Object { $_ -notin $expectedProfiles })
$extraStrategies = @($packageStrategies | Where-Object { $_ -notin $expectedStrategies })
$extraPresets = @($packagePresets | Where-Object { $_ -notin $expectedPresets })
$extraActivePresets = @($packageActivePresets | Where-Object { $_ -notin $expectedActivePresets })
$extraConfigs = @($packageConfigs | Where-Object { $_ -notin $configAllowList })

foreach ($name in @($expectedExperts | Where-Object { $_ -notin $packageExperts })) {
    $issues.Add("PACKAGE_MISSING_EXPERT:" + $name)
}
foreach ($name in @($expectedProfiles | Where-Object { $_ -notin $packageProfiles })) {
    $issues.Add("PACKAGE_MISSING_PROFILE:" + $name)
}
foreach ($name in @($expectedStrategies | Where-Object { $_ -notin $packageStrategies })) {
    $issues.Add("PACKAGE_MISSING_STRATEGY:" + $name)
}
foreach ($name in @($expectedPresets | Where-Object { $_ -notin $packagePresets })) {
    $issues.Add("PACKAGE_MISSING_PRESET:" + $name)
}
foreach ($name in @($expectedActivePresets | Where-Object { $_ -notin $packageActivePresets })) {
    $issues.Add("PACKAGE_MISSING_ACTIVE_PRESET:" + $name)
}
foreach ($name in @($extraExperts)) {
    $issues.Add("PACKAGE_EXTRA_EXPERT:" + $name)
}
foreach ($name in @($extraProfiles)) {
    $issues.Add("PACKAGE_EXTRA_PROFILE:" + $name)
}
foreach ($name in @($extraStrategies)) {
    $issues.Add("PACKAGE_EXTRA_STRATEGY:" + $name)
}
foreach ($name in @($extraPresets)) {
    $issues.Add("PACKAGE_EXTRA_PRESET:" + $name)
}
foreach ($name in @($extraActivePresets)) {
    $issues.Add("PACKAGE_EXTRA_ACTIVE_PRESET:" + $name)
}
foreach ($name in @($configAllowList | Where-Object { $_ -notin $packageConfigs })) {
    $issues.Add("PACKAGE_MISSING_CONFIG:" + $name)
}
foreach ($name in @($extraConfigs)) {
    $issues.Add("PACKAGE_EXTRA_CONFIG:" + $name)
}

if ($null -ne $packageManifest) {
    $manifestActiveSymbols = @($packageManifest.active_symbols | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if (@($manifestActiveSymbols).Count -ne @($expectedActiveSymbols).Count -or (Compare-Object -ReferenceObject $expectedActiveSymbols -DifferenceObject $manifestActiveSymbols)) {
        $issues.Add("PACKAGE_MANIFEST_ACTIVE_SYMBOLS_MISMATCH")
    }
}

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    ok = ($issues.Count -eq 0)
    package_root = $packageRoot
    handoff_root = $handoffRoot
    issues = @($issues)
}

$jsonPath = Join-Path $projectPath "EVIDENCE\transfer_package_report.json"
$txtPath = Join-Path $projectPath "EVIDENCE\transfer_package_report.txt"

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$txt = @()
$txt += "TRANSFER PACKAGE REPORT"
$txt += ("OK={0}" -f $result.ok)
$txt += ""
foreach ($issue in $issues) {
    $txt += $issue
}
if ($issues.Count -eq 0) {
    $txt += "PACKAGE_AND_HANDOFF_OK"
}
$txt | Set-Content -LiteralPath $txtPath -Encoding ASCII

$result | ConvertTo-Json -Depth 6

if (-not $result.ok) {
    exit 1
}
