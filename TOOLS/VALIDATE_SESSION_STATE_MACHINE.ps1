param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = "Stop"

$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Read-KeyValueTsv {
    param([string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $map[[string]$parts[0]] = [string]$parts[1]
    }

    return $map
}

function Parse-InvariantDouble {
    param([string]$Value)

    $out = 0.0
    if ([double]::TryParse($Value,[System.Globalization.NumberStyles]::Float,$InvariantCulture,[ref]$out)) {
        return $out
    }
    return 0.0
}

function Resolve-SymbolStateKey {
    param($RegistryItem)

    $codeSymbolProp = $RegistryItem.PSObject.Properties["code_symbol"]
    if ($null -ne $codeSymbolProp) {
        $codeSymbol = [string]$codeSymbolProp.Value
        if (-not [string]::IsNullOrWhiteSpace($codeSymbol)) {
            return $codeSymbol.ToUpperInvariant()
        }
    }

    $symbol = [string]$RegistryItem.symbol
    if ([string]::IsNullOrWhiteSpace($symbol)) {
        return ""
    }

    $upper = $symbol.Trim().ToUpperInvariant()
    $dot = $upper.IndexOf('.')
    if ($dot -gt 0) {
        return $upper.Substring(0,$dot)
    }
    return $upper
}

function Add-Issue {
    param([System.Collections.Generic.List[string]]$Issues,[string]$Message)
    $Issues.Add($Message) | Out-Null
}

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$domainReports = @()
$symbolReports = @()

$domainRegistryPath = Join-Path $ProjectRoot "CONFIG\domain_architecture_registry_v1.json"
$coordPath = Join-Path $ProjectRoot "CONFIG\session_capital_coordinator_v1.json"
$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"

$domainRegistry = Get-Content -LiteralPath $domainRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$coord = Get-Content -LiteralPath $coordPath -Raw -Encoding UTF8 | ConvertFrom-Json
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json

$allowedStates = @{}
foreach ($state in @($domainRegistry.shared_state_model)) {
    $allowedStates[[string]$state] = $true
}

$expectedStates = @(
    "SLEEP",
    "PREWARM",
    "LIVE",
    "LIVE_DEFENSIVE",
    "PAPER_ACTIVE",
    "PAPER_SHADOW",
    "REENTRY_PROBATION"
)
foreach ($expected in $expectedStates) {
    if (-not $allowedStates.ContainsKey($expected)) {
        Add-Issue $issues "Missing expected shared state '$expected' in domain architecture registry."
    }
}

$allowedRequestedModes = @{
    "HALT" = $true
    "PAPER_ONLY" = $true
    "CLOSE_ONLY" = $true
    "RUN" = $true
    "READY" = $true
}

$domains = @()
foreach ($domain in @($domainRegistry.domains)) {
    $domains += [string]$domain.domain
}

foreach ($group in @($coord.groups)) {
    foreach ($reserve in @($group.reserve_domains)) {
        if ($domains -notcontains [string]$reserve) {
            Add-Issue $issues "Coordinator group '$($group.group)' references unknown reserve domain '$reserve'."
        }
    }
}

$runDomains = New-Object System.Collections.Generic.List[string]

foreach ($domain in $domains) {
    $statePath = Join-Path $CommonFilesRoot ("state\_domains\{0}\session_capital_state.csv" -f $domain)
    $runtimeControlPath = Join-Path $CommonFilesRoot ("state\_domains\{0}\runtime_control.csv" -f $domain)

    if (-not (Test-Path -LiteralPath $statePath)) {
        Add-Issue $issues "Missing domain session state for '$domain'."
        continue
    }
    if (-not (Test-Path -LiteralPath $runtimeControlPath)) {
        Add-Issue $issues "Missing domain runtime control for '$domain'."
        continue
    }

    $state = Read-KeyValueTsv -Path $statePath
    $runtime = Read-KeyValueTsv -Path $runtimeControlPath

    $requiredStateKeys = @(
        "domain","state","active_group","window_state","requested_mode","requested_risk_cap",
        "reason_code","paper_lock","family_paper_lock","fleet_paper_lock",
        "defensive_mode","reentry_ready","reserve_candidate","reserve_requested_by","reserve_activated"
    )

    foreach ($key in $requiredStateKeys) {
        if (-not $state.ContainsKey($key)) {
            Add-Issue $issues "Domain '$domain' session state is missing key '$key'."
        }
    }

    $domainState = [string]$state["state"]
    $windowState = [string]$state["window_state"]
    $requestedMode = [string]$state["requested_mode"]
    $runtimeRequestedMode = [string]$runtime["requested_mode"]
    $activeGroup = [string]$state["active_group"]
    $reserveCandidate = [string]$state["reserve_candidate"]
    $reserveRequestedBy = [string]$state["reserve_requested_by"]
    $reserveActivated = ([int]([string]$state["reserve_activated"]) -ne 0)
    $requestedRiskCap = Parse-InvariantDouble ([string]$state["requested_risk_cap"])
    $runtimeRiskCap = Parse-InvariantDouble ([string]$runtime["risk_cap"])

    if (-not $allowedStates.ContainsKey($domainState)) {
        Add-Issue $issues "Domain '$domain' uses unknown state '$domainState'."
    }
    if (-not $allowedStates.ContainsKey($windowState)) {
        Add-Issue $issues "Domain '$domain' uses unknown window_state '$windowState'."
    }
    if (-not $allowedRequestedModes.ContainsKey($requestedMode)) {
        Add-Issue $issues "Domain '$domain' uses invalid requested_mode '$requestedMode' in session state."
    }
    if (-not $allowedRequestedModes.ContainsKey($runtimeRequestedMode)) {
        Add-Issue $issues "Domain '$domain' uses invalid requested_mode '$runtimeRequestedMode' in runtime control."
    }
    if ($requestedMode -ne $runtimeRequestedMode) {
        Add-Issue $issues "Domain '$domain' has session/runtime requested_mode mismatch ('$requestedMode' vs '$runtimeRequestedMode')."
    }
    if ([math]::Abs($requestedRiskCap - $runtimeRiskCap) -gt 0.0001) {
        Add-Issue $issues "Domain '$domain' has session/runtime risk_cap mismatch ($requestedRiskCap vs $runtimeRiskCap)."
    }
    if ($requestedRiskCap -lt 0.0 -or $requestedRiskCap -gt 1.0) {
        Add-Issue $issues "Domain '$domain' requested_risk_cap must be in [0,1]."
    }

    if ($domainState -eq "SLEEP" -and -not [string]::IsNullOrWhiteSpace($activeGroup)) {
        Add-Issue $issues "Domain '$domain' is SLEEP but still has active_group '$activeGroup'."
    }

    if ($domainState -in @("PREWARM","LIVE","LIVE_DEFENSIVE","PAPER_ACTIVE","PAPER_SHADOW","REENTRY_PROBATION")) {
        if ([string]::IsNullOrWhiteSpace($activeGroup)) {
            Add-Issue $issues "Domain '$domain' state '$domainState' requires non-empty active_group."
        }
    }

    if ($domainState -eq "LIVE_DEFENSIVE" -and $requestedMode -ne "RUN") {
        Add-Issue $issues "Domain '$domain' is LIVE_DEFENSIVE but requested_mode is '$requestedMode' instead of RUN."
    }
    if ($domainState -eq "REENTRY_PROBATION" -and $requestedMode -ne "RUN") {
        Add-Issue $issues "Domain '$domain' is REENTRY_PROBATION but requested_mode is '$requestedMode' instead of RUN."
    }
    if ($domainState -eq "PAPER_ACTIVE" -and $requestedMode -ne "PAPER_ONLY") {
        Add-Issue $issues "Domain '$domain' is PAPER_ACTIVE but requested_mode is '$requestedMode' instead of PAPER_ONLY."
    }

    if ($reserveActivated -and [string]::IsNullOrWhiteSpace($reserveCandidate)) {
        Add-Issue $issues "Domain '$domain' has reserve_activated=1 but empty reserve_candidate."
    }
    if (-not [string]::IsNullOrWhiteSpace($reserveRequestedBy) -and [string]::IsNullOrWhiteSpace($reserveCandidate)) {
        Add-Issue $issues "Domain '$domain' has reserve_requested_by but empty reserve_candidate."
    }

    if ($requestedMode -eq "RUN") {
        $runDomains.Add($domain) | Out-Null
    }

    $domainReports += [pscustomobject]@{
        domain = $domain
        state = $domainState
        window_state = $windowState
        requested_mode = $requestedMode
        requested_risk_cap = [math]::Round($requestedRiskCap,4)
        reserve_candidate = $reserveCandidate
        reserve_requested_by = $reserveRequestedBy
        reserve_activated = $reserveActivated
    }
}

if ($runDomains.Count -gt 1) {
    Add-Issue $issues ("More than one domain currently requests RUN: " + ($runDomains -join ", "))
}

foreach ($item in @($registry.symbols)) {
    $symbol = [string]$item.symbol
    $symbolStateKey = Resolve-SymbolStateKey $item
    $sessionProfile = [string]$item.session_profile
    $symbolStateDir = Join-Path $CommonFilesRoot ("state\{0}" -f $symbolStateKey)
    $runtimeControlPath = Join-Path $symbolStateDir "runtime_control.csv"
    if (-not (Test-Path -LiteralPath $runtimeControlPath)) {
        if (-not (Test-Path -LiteralPath $symbolStateDir)) {
            $warnings.Add("Symbol '$symbol' has no runtime state directory yet; runtime may not be attached on chart.") | Out-Null
        }
        else {
            Add-Issue $issues "Missing symbol runtime control for '$symbol'."
        }
        continue
    }

    $runtime = Read-KeyValueTsv -Path $runtimeControlPath
    $requestedMode = [string]$runtime["requested_mode"]
    if (-not $allowedRequestedModes.ContainsKey($requestedMode)) {
        Add-Issue $issues "Symbol '$symbol' uses invalid requested_mode '$requestedMode'."
    }

    $symbolReports += [pscustomobject]@{
        symbol = $symbol
        session_profile = $sessionProfile
        requested_mode = $requestedMode
        reason_code = [string]$runtime["reason_code"]
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    common_files_root = $CommonFilesRoot
    ok = ($issues.Count -eq 0)
    run_domain_count = $runDomains.Count
    run_domains = @($runDomains)
    domain_reports = $domainReports
    symbol_runtime_controls = $symbolReports
    warnings = @($warnings)
    issues = @($issues)
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\session_state_machine_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\session_state_machine_report.txt"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @(
    "SESSION STATE MACHINE REPORT",
    ("OK={0}" -f $report.ok),
    ("RUN_DOMAIN_COUNT={0}" -f $report.run_domain_count),
    ("RUN_DOMAINS={0}" -f (($report.run_domains) -join ",")),
    ""
)
foreach ($issue in @($report.issues)) {
    $lines += ("ISSUE | {0}" -f $issue)
}
foreach ($warning in @($report.warnings)) {
    $lines += ("WARN | {0}" -f $warning)
}
$lines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$report | ConvertTo-Json -Depth 8
