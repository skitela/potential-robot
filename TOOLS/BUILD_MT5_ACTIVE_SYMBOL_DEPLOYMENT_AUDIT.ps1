param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalDataRoot = "",
    [string]$CommonRoot = "",
    [switch]$FailOnIssues
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-OandaMt5TerminalDataRoot {
    param([string]$RequestedRoot)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        return (Resolve-Path -LiteralPath $RequestedRoot).Path
    }

    $terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    if (-not (Test-Path -LiteralPath $terminalRoot)) {
        throw "Missing MetaQuotes terminal root: $terminalRoot"
    }

    $candidates = Get-ChildItem -LiteralPath $terminalRoot -Directory -Force | Sort-Object Name
    foreach ($candidate in $candidates) {
        $originPath = Join-Path $candidate.FullName "origin.txt"
        if (-not (Test-Path -LiteralPath $originPath)) {
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($originPath)
        $originText = [System.Text.Encoding]::Unicode.GetString($bytes).Trim([char]0xFEFF, [char]0, [char]13, [char]10, [char]9, ' ')
        if ($originText -like "*OANDA TMS MT5 Terminal*") {
            return $candidate.FullName
        }
    }

    throw "Could not auto-detect OANDA TMS MT5 terminal data root under $terminalRoot"
}

function Resolve-CommonRootPath {
    param([string]$RequestedRoot)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        return $RequestedRoot
    }

    return (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT")
}

function Get-FileHashOrEmpty {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    return [string](Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$resolvedTerminalDataRoot = Resolve-OandaMt5TerminalDataRoot -RequestedRoot $TerminalDataRoot
$resolvedCommonRoot = Resolve-CommonRootPath -RequestedRoot $CommonRoot

$helperPath = Join-Path $resolvedProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registryPath = Join-Path $resolvedProjectRoot "CONFIG\microbots_registry.json"
$planPath = Join-Path $resolvedProjectRoot "CONFIG\scalping_universe_plan.json"
$opsRoot = Join-Path $resolvedProjectRoot "EVIDENCE\OPS"
$jsonPath = Join-Path $opsRoot "mt5_active_symbol_deployment_audit_latest.json"
$mdPath = Join-Path $opsRoot "mt5_active_symbol_deployment_audit_latest.md"

$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json

$activeUniverse = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($symbol in @($plan.training_universe)) {
    [void]$activeUniverse.Add([string]$symbol)
}

$activeSymbols = @(
    $registry.symbols | Where-Object {
        $activeUniverse.Contains((Get-RegistryCanonicalSymbol -RegistryItem $_))
    } | Sort-Object symbol
)

$reportRows = New-Object System.Collections.Generic.List[object]
$issues = New-Object System.Collections.Generic.List[string]

foreach ($row in $activeSymbols) {
    $symbolIssues = New-Object System.Collections.Generic.List[string]

    $expertName = [string]$row.expert
    $presetName = [string]$row.preset
    $codeSymbol = [string]$row.code_symbol

    $repoExpertSourcePath = Join-Path $resolvedProjectRoot ("MQL5\Experts\MicroBots\{0}.mq5" -f $expertName)
    $repoPresetPath = Join-Path $resolvedProjectRoot ("MQL5\Presets\{0}" -f $presetName)
    $repoProfilePath = Join-Path $resolvedProjectRoot ("MQL5\Include\Profiles\Profile_{0}.mqh" -f $codeSymbol)
    $repoStrategyPath = Join-Path $resolvedProjectRoot ("MQL5\Include\Strategies\Strategy_{0}.mqh" -f $codeSymbol)

    $terminalExpertSourcePath = Join-Path $resolvedTerminalDataRoot ("MQL5\Experts\MicroBots\{0}.mq5" -f $expertName)
    $terminalExpertBinaryPath = Join-Path $resolvedTerminalDataRoot ("MQL5\Experts\MicroBots\{0}.ex5" -f $expertName)
    $terminalPresetPath = Join-Path $resolvedTerminalDataRoot ("MQL5\Presets\{0}" -f $presetName)
    $terminalProfilePath = Join-Path $resolvedTerminalDataRoot ("MQL5\Include\Profiles\Profile_{0}.mqh" -f $codeSymbol)
    $terminalStrategyPath = Join-Path $resolvedTerminalDataRoot ("MQL5\Include\Strategies\Strategy_{0}.mqh" -f $codeSymbol)

    $repoExpertSourcePresent = Test-Path -LiteralPath $repoExpertSourcePath
    $repoPresetPresent = Test-Path -LiteralPath $repoPresetPath
    $repoProfilePresent = Test-Path -LiteralPath $repoProfilePath
    $repoStrategyPresent = Test-Path -LiteralPath $repoStrategyPath
    $terminalExpertSourcePresent = Test-Path -LiteralPath $terminalExpertSourcePath
    $terminalExpertBinaryPresent = Test-Path -LiteralPath $terminalExpertBinaryPath
    $terminalPresetPresent = Test-Path -LiteralPath $terminalPresetPath
    $terminalProfilePresent = Test-Path -LiteralPath $terminalProfilePath
    $terminalStrategyPresent = Test-Path -LiteralPath $terminalStrategyPath

    if (-not $repoExpertSourcePresent) { [void]$symbolIssues.Add("REPO_MQ5_MISSING") }
    if (-not $repoPresetPresent) { [void]$symbolIssues.Add("REPO_PRESET_MISSING") }
    if (-not $repoProfilePresent) { [void]$symbolIssues.Add("REPO_PROFILE_MISSING") }
    if (-not $repoStrategyPresent) { [void]$symbolIssues.Add("REPO_STRATEGY_MISSING") }
    if (-not $terminalExpertSourcePresent) { [void]$symbolIssues.Add("TERMINAL_MQ5_MISSING") }
    if (-not $terminalExpertBinaryPresent) { [void]$symbolIssues.Add("TERMINAL_EX5_MISSING") }
    if (-not $terminalPresetPresent) { [void]$symbolIssues.Add("TERMINAL_PRESET_MISSING") }
    if (-not $terminalProfilePresent) { [void]$symbolIssues.Add("TERMINAL_PROFILE_MISSING") }
    if (-not $terminalStrategyPresent) { [void]$symbolIssues.Add("TERMINAL_STRATEGY_MISSING") }

    $expertSourceHashRepo = Get-FileHashOrEmpty -Path $repoExpertSourcePath
    $expertSourceHashTerminal = Get-FileHashOrEmpty -Path $terminalExpertSourcePath
    $presetHashRepo = Get-FileHashOrEmpty -Path $repoPresetPath
    $presetHashTerminal = Get-FileHashOrEmpty -Path $terminalPresetPath
    $profileHashRepo = Get-FileHashOrEmpty -Path $repoProfilePath
    $profileHashTerminal = Get-FileHashOrEmpty -Path $terminalProfilePath
    $strategyHashRepo = Get-FileHashOrEmpty -Path $repoStrategyPath
    $strategyHashTerminal = Get-FileHashOrEmpty -Path $terminalStrategyPath

    $expertSourceHashMatch = ($expertSourceHashRepo -ne "" -and $expertSourceHashRepo -eq $expertSourceHashTerminal)
    $presetHashMatch = ($presetHashRepo -ne "" -and $presetHashRepo -eq $presetHashTerminal)
    $profileHashMatch = ($profileHashRepo -ne "" -and $profileHashRepo -eq $profileHashTerminal)
    $strategyHashMatch = ($strategyHashRepo -ne "" -and $strategyHashRepo -eq $strategyHashTerminal)

    if ($repoExpertSourcePresent -and $terminalExpertSourcePresent -and -not $expertSourceHashMatch) { [void]$symbolIssues.Add("EXPERT_SOURCE_HASH_MISMATCH") }
    if ($repoPresetPresent -and $terminalPresetPresent -and -not $presetHashMatch) { [void]$symbolIssues.Add("PRESET_HASH_MISMATCH") }
    if ($repoProfilePresent -and $terminalProfilePresent -and -not $profileHashMatch) { [void]$symbolIssues.Add("PROFILE_HASH_MISMATCH") }
    if ($repoStrategyPresent -and $terminalStrategyPresent -and -not $strategyHashMatch) { [void]$symbolIssues.Add("STRATEGY_HASH_MISMATCH") }

    $stateAlias = Resolve-RegistryStateAlias -RegistryItem $row -CommonFilesRoot $resolvedCommonRoot -RequiredFiles @("runtime_control.csv")
    $stateDir = Join-Path $resolvedCommonRoot ("state\{0}" -f $stateAlias)
    $statePresent = Test-Path -LiteralPath $stateDir
    $runtimeControlPath = Join-Path $stateDir "runtime_control.csv"
    $runtimeStatusPath = Join-Path $stateDir "runtime_status.json"
    $studentGatePath = Join-Path $stateDir "student_gate_contract.csv"
    $teacherPackagePath = Join-Path $stateDir "teacher_package_contract.csv"
    $brokerProfilePath = Join-Path $stateDir "broker_profile.json"

    $runtimeControlPresent = Test-Path -LiteralPath $runtimeControlPath
    $runtimeStatusPresent = Test-Path -LiteralPath $runtimeStatusPath
    $studentGatePresent = Test-Path -LiteralPath $studentGatePath
    $teacherPackagePresent = Test-Path -LiteralPath $teacherPackagePath
    $brokerProfilePresent = Test-Path -LiteralPath $brokerProfilePath

    if (-not $statePresent) { [void]$symbolIssues.Add("STATE_DIR_MISSING") }
    if (-not $runtimeControlPresent) { [void]$symbolIssues.Add("RUNTIME_CONTROL_MISSING") }
    if (-not $runtimeStatusPresent) { [void]$symbolIssues.Add("RUNTIME_STATUS_MISSING") }
    if (-not $studentGatePresent) { [void]$symbolIssues.Add("STUDENT_GATE_CONTRACT_MISSING") }
    if (-not $teacherPackagePresent) { [void]$symbolIssues.Add("TEACHER_PACKAGE_CONTRACT_MISSING") }

    foreach ($symbolIssue in $symbolIssues) {
        [void]$issues.Add(("{0}:{1}" -f $row.symbol, $symbolIssue))
    }

    $reportRows.Add([ordered]@{
        symbol = [string]$row.symbol
        broker_symbol = [string]$row.broker_symbol
        code_symbol = $codeSymbol
        expert = $expertName
        preset = $presetName
        session_profile = [string]$row.session_profile
        state_alias = $stateAlias
        repo_expert_source_present = $repoExpertSourcePresent
        terminal_expert_source_present = $terminalExpertSourcePresent
        terminal_expert_binary_present = $terminalExpertBinaryPresent
        repo_preset_present = $repoPresetPresent
        terminal_preset_present = $terminalPresetPresent
        repo_profile_present = $repoProfilePresent
        terminal_profile_present = $terminalProfilePresent
        repo_strategy_present = $repoStrategyPresent
        terminal_strategy_present = $terminalStrategyPresent
        expert_source_hash_match = $expertSourceHashMatch
        preset_hash_match = $presetHashMatch
        profile_hash_match = $profileHashMatch
        strategy_hash_match = $strategyHashMatch
        runtime_control_present = $runtimeControlPresent
        runtime_status_present = $runtimeStatusPresent
        student_gate_contract_present = $studentGatePresent
        teacher_package_contract_present = $teacherPackagePresent
        broker_profile_present = $brokerProfilePresent
        overall_ok = ($symbolIssues.Count -eq 0)
        issues = $symbolIssues.ToArray()
    }) | Out-Null
}

$rows = $reportRows.ToArray()
$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $resolvedProjectRoot
    terminal_data_root = $resolvedTerminalDataRoot
    common_root = $resolvedCommonRoot
    total_symbols = $rows.Count
    ok_symbols = @($rows | Where-Object { $_.overall_ok }).Count
    missing_ex5_symbols = @($rows | Where-Object { -not $_.terminal_expert_binary_present } | ForEach-Object { $_.symbol })
    source_or_preset_mismatch_symbols = @($rows | Where-Object { -not $_.expert_source_hash_match -or -not $_.preset_hash_match -or -not $_.profile_hash_match -or -not $_.strategy_hash_match } | ForEach-Object { $_.symbol } | Select-Object -Unique)
    state_contract_gap_symbols = @($rows | Where-Object { -not $_.runtime_control_present -or -not $_.student_gate_contract_present -or -not $_.teacher_package_contract_present } | ForEach-Object { $_.symbol } | Select-Object -Unique)
    ok = ($issues.Count -eq 0)
    issues = $issues.ToArray()
    symbols = $rows
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# MT5 Active Symbol Deployment Audit") | Out-Null
$md.Add("") | Out-Null
$md.Add(("- generated_at_utc: {0}" -f $report.generated_at_utc)) | Out-Null
$md.Add(("- terminal_data_root: {0}" -f $resolvedTerminalDataRoot)) | Out-Null
$md.Add(("- common_root: {0}" -f $resolvedCommonRoot)) | Out-Null
$md.Add(("- total_symbols: {0}" -f $report.total_symbols)) | Out-Null
$md.Add(("- ok_symbols: {0}" -f $report.ok_symbols)) | Out-Null
$md.Add(("- overall_ok: {0}" -f $report.ok)) | Out-Null
$md.Add("") | Out-Null
$md.Add("## Symbols") | Out-Null
$md.Add("") | Out-Null
foreach ($row in $rows) {
    $issueText = if (@($row.issues).Count -eq 0) { "NONE" } else { (@($row.issues) -join ", ") }
    $md.Add(("- {0} | state_alias={1} | ex5={2} | src_hash={3} | preset_hash={4} | profile_hash={5} | strategy_hash={6} | runtime_control={7} | teacher_package={8} | issues={9}" -f $row.symbol, $row.state_alias, $row.terminal_expert_binary_present, $row.expert_source_hash_match, $row.preset_hash_match, $row.profile_hash_match, $row.strategy_hash_match, $row.runtime_control_present, $row.teacher_package_contract_present, $issueText)) | Out-Null
}

$md | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8

if ($FailOnIssues -and -not $report.ok) {
    exit 1
}
