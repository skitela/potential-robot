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

function Resolve-SymbolDbPath {
    param([string]$TerminalDataRootPath)

    $symbolsRoot = Join-Path $TerminalDataRootPath "bases\OANDATMS-MT5\symbols"
    if (-not (Test-Path -LiteralPath $symbolsRoot)) {
        return ""
    }

    $candidate = Get-ChildItem -LiteralPath $symbolsRoot -File -Filter "symbols-*.dat" | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $candidate) {
        return ""
    }

    return $candidate.FullName
}

function Get-RegexValue {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return ""
}

function Get-RepoSpecSnapshot {
    param([string]$SpecPath)

    $raw = Get-Content -Raw -LiteralPath $SpecPath
    $metadataImportEnabled = ($raw -match 'MbEnableBrokerMetadataImport\s*\(')
    return [ordered]@{
        raw = $raw
        profile_symbol = Get-RegexValue -Text $raw -Pattern 'out\.symbol\s*=\s*"([^"]+)"'
        session_profile = Get-RegexValue -Text $raw -Pattern 'out\.session_profile\s*=\s*"([^"]+)"'
        trade_window_start_hour = Get-RegexValue -Text $raw -Pattern 'out\.trade_window_start_hour\s*=\s*([0-9]+)'
        trade_window_end_hour = Get-RegexValue -Text $raw -Pattern 'out\.trade_window_end_hour\s*=\s*([0-9]+)'
        max_spread_points = Get-RegexValue -Text $raw -Pattern 'out\.max_spread_points\s*=\s*([0-9.]+)'
        caution_spread_points = Get-RegexValue -Text $raw -Pattern 'out\.caution_spread_points\s*=\s*([0-9.]+)'
        max_tick_age_sec = Get-RegexValue -Text $raw -Pattern 'out\.max_tick_age_sec\s*=\s*([0-9]+)'
        min_seconds_between_entries = Get-RegexValue -Text $raw -Pattern 'out\.min_seconds_between_entries\s*=\s*([0-9]+)'
        kill_switch_token_name = Get-RegexValue -Text $raw -Pattern 'out\.kill_switch_token_name\s*=\s*"([^"]+)"'
        has_volume_constraints = ($metadataImportEnabled -or ($raw -match 'out\.import_volume_limits\s*=\s*true'))
        has_tick_contract = ($metadataImportEnabled -or ($raw -match 'out\.import_tick_contract\s*=\s*true'))
        has_stop_freeze = ($metadataImportEnabled -or ($raw -match 'out\.import_stop_freeze_levels\s*=\s*true'))
    }
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$resolvedTerminalDataRoot = Resolve-OandaMt5TerminalDataRoot -RequestedRoot $TerminalDataRoot
$resolvedCommonRoot = Resolve-CommonRootPath -RequestedRoot $CommonRoot
$resolvedSymbolsDbPath = Resolve-SymbolDbPath -TerminalDataRootPath $resolvedTerminalDataRoot

$helperPath = Join-Path $resolvedProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registryPath = Join-Path $resolvedProjectRoot "CONFIG\microbots_registry.json"
$planPath = Join-Path $resolvedProjectRoot "CONFIG\scalping_universe_plan.json"
$opsRoot = Join-Path $resolvedProjectRoot "EVIDENCE\OPS"
$jsonPath = Join-Path $opsRoot "mt5_symbol_metadata_profile_audit_latest.json"
$mdPath = Join-Path $opsRoot "mt5_symbol_metadata_profile_audit_latest.md"

$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
$plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json

$symbolsAscii = ""
if (-not [string]::IsNullOrWhiteSpace($resolvedSymbolsDbPath)) {
    $symbolsAscii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($resolvedSymbolsDbPath))
}

$activeUniverse = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($symbol in @($plan.training_universe)) {
    [void]$activeUniverse.Add([string]$symbol)
}

$activeSymbols = @(
    $registry.symbols | Where-Object {
        $activeUniverse.Contains((Get-RegistryCanonicalSymbol -RegistryItem $_))
    } | Sort-Object symbol
)

$rows = New-Object System.Collections.Generic.List[object]
$issues = New-Object System.Collections.Generic.List[string]

foreach ($row in $activeSymbols) {
    $profileIssues = New-Object System.Collections.Generic.List[string]
    $specPath = Join-Path $resolvedProjectRoot ("MQL5\Include\Profiles\Profile_{0}.mqh" -f [string]$row.code_symbol)

    if (-not (Test-Path -LiteralPath $specPath)) {
        [void]$profileIssues.Add("REPO_PROFILE_MISSING")
        foreach ($profileIssue in $profileIssues) {
            [void]$issues.Add(("{0}:{1}" -f $row.symbol, $profileIssue))
        }

        $rows.Add([ordered]@{
            symbol = [string]$row.symbol
            broker_symbol = [string]$row.broker_symbol
            state_alias = ""
            broker_profile_present = $false
            metadata_ok = $false
            issues = $profileIssues.ToArray()
        }) | Out-Null
        continue
    }

    $repoSpec = Get-RepoSpecSnapshot -SpecPath $specPath
    $stateAlias = Resolve-RegistryStateAlias -RegistryItem $row -CommonFilesRoot $resolvedCommonRoot -RequiredFiles @("broker_profile.json")
    $stateDir = Join-Path $resolvedCommonRoot ("state\{0}" -f $stateAlias)
    $brokerProfilePath = Join-Path $stateDir "broker_profile.json"
    $brokerProfilePresent = Test-Path -LiteralPath $brokerProfilePath
    $brokerProfile = $null
    if ($brokerProfilePresent) {
        $brokerProfile = Get-Content -Raw -LiteralPath $brokerProfilePath | ConvertFrom-Json
    }

    $symbolCandidates = @(Get-RegistrySymbolCandidates -RegistryItem $row)
    $symbolsDbAnyMatch = $false
    foreach ($candidate in $symbolCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($symbolsAscii) -and $symbolsAscii.IndexOf([string]$candidate, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $symbolsDbAnyMatch = $true
            break
        }
    }

    $canonicalSymbol = (Get-RegistryCanonicalSymbol -RegistryItem $row)
    $profileCanonical = ([string]$repoSpec.profile_symbol -replace '\.pro$','')
    $repoProfileCanonicalMatch = $profileCanonical.Equals($canonicalSymbol, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $repoProfileCanonicalMatch) {
        [void]$profileIssues.Add("PROFILE_SYMBOL_MISMATCH")
    }

    $brokerSymbolMatch = $false
    $sessionProfileMatch = $false
    $spreadWithinCaution = $null
    $spreadWithinMax = $null
    $tradePermissionsOk = $null
    $cacheValid = $null
    $terminalConnected = $null
    $brokerSymbolActual = ""

    if ($brokerProfilePresent) {
        $brokerSymbolActual = [string]$brokerProfile.symbol
        $brokerSymbolMatch = $brokerSymbolActual.Equals([string]$row.broker_symbol, [System.StringComparison]::OrdinalIgnoreCase)
        $sessionProfileMatch = ([string]$brokerProfile.session_profile).Equals([string]$repoSpec.session_profile, [System.StringComparison]::OrdinalIgnoreCase)
        $spreadWithinCaution = ([double]$brokerProfile.spread_points -le [double]$repoSpec.caution_spread_points)
        $spreadWithinMax = ([double]$brokerProfile.spread_points -le [double]$repoSpec.max_spread_points)
        $tradePermissionsOk = [bool]$brokerProfile.trade_permissions_ok
        $cacheValid = [bool]$brokerProfile.cache_valid
        $terminalConnected = [bool]$brokerProfile.terminal_connected

        if (-not $brokerSymbolMatch) { [void]$profileIssues.Add("BROKER_SYMBOL_MISMATCH") }
        if (-not $sessionProfileMatch) { [void]$profileIssues.Add("SESSION_PROFILE_MISMATCH") }
        if (-not $tradePermissionsOk) { [void]$profileIssues.Add("TRADE_PERMISSIONS_NOT_OK") }
        if (-not $cacheValid) { [void]$profileIssues.Add("BROKER_CACHE_INVALID") }
        if (-not $terminalConnected) { [void]$profileIssues.Add("TERMINAL_NOT_CONNECTED") }
    }
    else {
        [void]$profileIssues.Add("BROKER_PROFILE_MISSING")
    }

    $importGaps = New-Object System.Collections.Generic.List[string]
    if (-not $repoSpec.has_volume_constraints) { [void]$importGaps.Add("IMPORT_VOLUME_LIMITS") }
    if (-not $repoSpec.has_tick_contract) { [void]$importGaps.Add("IMPORT_TICK_VALUE_AND_TICK_SIZE") }
    if (-not $repoSpec.has_stop_freeze) { [void]$importGaps.Add("IMPORT_STOPS_AND_FREEZE_LEVEL") }

    foreach ($profileIssue in $profileIssues) {
        [void]$issues.Add(("{0}:{1}" -f $row.symbol, $profileIssue))
    }

    $rows.Add([ordered]@{
        symbol = [string]$row.symbol
        broker_symbol = [string]$row.broker_symbol
        code_symbol = [string]$row.code_symbol
        state_alias = $stateAlias
        symbols_db_any_match = $symbolsDbAnyMatch
        repo_profile_symbol = [string]$repoSpec.profile_symbol
        broker_profile_symbol = $brokerSymbolActual
        repo_profile_session = [string]$repoSpec.session_profile
        repo_trade_window = (([string]$repoSpec.trade_window_start_hour) + "-" + ([string]$repoSpec.trade_window_end_hour))
        repo_max_spread_points = [string]$repoSpec.max_spread_points
        repo_caution_spread_points = [string]$repoSpec.caution_spread_points
        broker_profile_present = $brokerProfilePresent
        broker_symbol_match = $brokerSymbolMatch
        session_profile_match = $sessionProfileMatch
        current_spread_within_caution = $spreadWithinCaution
        current_spread_within_max = $spreadWithinMax
        trade_permissions_ok = $tradePermissionsOk
        cache_valid = $cacheValid
        terminal_connected = $terminalConnected
        broker_tick_size = if ($brokerProfilePresent) { [string]$brokerProfile.tick_size } else { "" }
        broker_tick_value = if ($brokerProfilePresent) { [string]$brokerProfile.tick_value } else { "" }
        broker_volume_min = if ($brokerProfilePresent) { [string]$brokerProfile.volume_min } else { "" }
        broker_volume_step = if ($brokerProfilePresent) { [string]$brokerProfile.volume_step } else { "" }
        broker_volume_max = if ($brokerProfilePresent) { [string]$brokerProfile.volume_max } else { "" }
        broker_stops_level = if ($brokerProfilePresent) { [string]$brokerProfile.stops_level } else { "" }
        broker_freeze_level = if ($brokerProfilePresent) { [string]$brokerProfile.freeze_level } else { "" }
        import_gaps = $importGaps.ToArray()
        metadata_ok = ($profileIssues.Count -eq 0)
        issues = $profileIssues.ToArray()
    }) | Out-Null
}

$reportRows = $rows.ToArray()
$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $resolvedProjectRoot
    terminal_data_root = $resolvedTerminalDataRoot
    common_root = $resolvedCommonRoot
    symbols_db_path = $resolvedSymbolsDbPath
    total_symbols = $reportRows.Count
    symbols_db_any_match_count = @($reportRows | Where-Object { $_.symbols_db_any_match }).Count
    broker_profile_present_count = @($reportRows | Where-Object { $_.broker_profile_present }).Count
    metadata_ok_count = @($reportRows | Where-Object { $_.metadata_ok }).Count
    broker_profile_missing_symbols = @($reportRows | Where-Object { -not $_.broker_profile_present } | ForEach-Object { $_.symbol })
    symbols_db_unconfirmed_symbols = @($reportRows | Where-Object { -not $_.symbols_db_any_match } | ForEach-Object { $_.symbol })
    import_gap_symbols = @($reportRows | Where-Object { @($_.import_gaps).Count -gt 0 } | ForEach-Object { $_.symbol })
    ok = ($issues.Count -eq 0)
    issues = $issues.ToArray()
    symbols = $reportRows
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# MT5 Symbol Metadata vs Repo Profile Audit") | Out-Null
$md.Add("") | Out-Null
$md.Add(("- generated_at_utc: {0}" -f $report.generated_at_utc)) | Out-Null
$md.Add(("- terminal_data_root: {0}" -f $resolvedTerminalDataRoot)) | Out-Null
$md.Add(("- common_root: {0}" -f $resolvedCommonRoot)) | Out-Null
$md.Add(("- symbols_db_path: {0}" -f $resolvedSymbolsDbPath)) | Out-Null
$md.Add(("- total_symbols: {0}" -f $report.total_symbols)) | Out-Null
$md.Add(("- symbols_db_any_match_count: {0}" -f $report.symbols_db_any_match_count)) | Out-Null
$md.Add(("- broker_profile_present_count: {0}" -f $report.broker_profile_present_count)) | Out-Null
$md.Add(("- metadata_ok_count: {0}" -f $report.metadata_ok_count)) | Out-Null
$md.Add(("- overall_ok: {0}" -f $report.ok)) | Out-Null
$md.Add("") | Out-Null
$md.Add("## Symbols") | Out-Null
$md.Add("") | Out-Null
foreach ($row in $reportRows) {
    $issueText = if (@($row.issues).Count -eq 0) { "NONE" } else { (@($row.issues) -join ", ") }
    $gapText = if (@($row.import_gaps).Count -eq 0) { "NONE" } else { (@($row.import_gaps) -join ", ") }
    $md.Add(("- {0} | state_alias={1} | symbols_db_match={2} | broker_profile={3} | symbol_match={4} | session_match={5} | spread_caution={6} | spread_max={7} | import_gaps={8} | issues={9}" -f $row.symbol, $row.state_alias, $row.symbols_db_any_match, $row.broker_profile_present, $row.broker_symbol_match, $row.session_profile_match, $row.current_spread_within_caution, $row.current_spread_within_max, $gapText, $issueText)) | Out-Null
}

$md | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8

if ($FailOnIssues -and -not $report.ok) {
    exit 1
}
