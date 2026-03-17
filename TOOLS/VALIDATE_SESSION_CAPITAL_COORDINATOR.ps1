param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($CommonFilesRoot)) {
    $CommonFilesRoot = Join-Path $env:APPDATA "MetaQuotes\\Terminal\\Common\\Files\\MAKRO_I_MIKRO_BOT"
}

$registryPath = Join-Path $projectPath "CONFIG\\microbots_registry.json"
$coordPath = Join-Path $projectPath "CONFIG\\session_capital_coordinator_v1.json"
$capitalPath = Join-Path $projectPath "CONFIG\\capital_risk_contract_v1.json"
$rolloverPath = Join-Path $projectPath "CONFIG\\rollover_guard_v1.json"
$globalPath = Join-Path $CommonFilesRoot "state\\_global\\session_capital_coordinator.csv"
$issues = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $registryPath)) {
    $issues.Add("Missing registry: $registryPath")
}
if (-not (Test-Path -LiteralPath $coordPath)) {
    $issues.Add("Missing config: $coordPath")
}
if (-not (Test-Path -LiteralPath $capitalPath)) {
    $issues.Add("Missing capital contract: $capitalPath")
}
if (-not (Test-Path -LiteralPath $rolloverPath)) {
    $issues.Add("Missing rollover guard config: $rolloverPath")
}

$coord = $null
$groupBudgetSum = 0.0
if (Test-Path -LiteralPath $coordPath) {
    $coord = Get-Content -LiteralPath $coordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($group in $coord.groups) {
        $groupBudgetSum += [double]$group.budget_share_of_day
    }
    if ([math]::Abs($groupBudgetSum - 1.0) -gt 0.0001) {
        $issues.Add(("Group budget share sum must equal 1.0, got {0}" -f $groupBudgetSum))
    }
    if ([string]::IsNullOrWhiteSpace([string]$coord.rules.paper_requested_mode)) {
        $issues.Add("Coordinator rules must define paper_requested_mode")
    }
    if ([double]$coord.rules.reentry_recover_fraction -le 0.0) {
        $issues.Add("Coordinator rules must define positive reentry_recover_fraction")
    }
    if ([double]$coord.rules.defensive_family_loss_fraction -le 0.0) {
        $issues.Add("Coordinator rules must define positive defensive_family_loss_fraction")
    }
    if ([double]$coord.rules.reentry_probation_risk_cap -le 0.0 -or [double]$coord.rules.reentry_probation_risk_cap -gt 1.0) {
        $issues.Add("Coordinator rules must define reentry_probation_risk_cap in (0,1]")
    }
    if ([double]$coord.rules.reserve_takeover_risk_cap -le 0.0 -or [double]$coord.rules.reserve_takeover_risk_cap -gt 1.0) {
        $issues.Add("Coordinator rules must define reserve_takeover_risk_cap in (0,1]")
    }
}

if (Test-Path -LiteralPath $rolloverPath) {
    $rollover = Get-Content -LiteralPath $rolloverPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$rollover.daily.enabled) {
        $issues.Add("Rollover guard must keep daily protection enabled")
    }
    if ([int]$rollover.daily.block_before_min -le 0) {
        $issues.Add("Daily rollover guard must define positive block_before_min")
    }
    if ([int]$rollover.daily.force_flatten_before_min -lt 0) {
        $issues.Add("Daily rollover guard must define non-negative force_flatten_before_min")
    }
    if (-not [bool]$rollover.quarterly.enabled) {
        $issues.Add("Rollover guard must keep quarterly protection enabled")
    }
}

if (-not (Test-Path -LiteralPath $globalPath)) {
    $issues.Add("Missing global coordinator state: $globalPath")
}

$domainReports = @()
if ($null -ne $coord) {
    foreach ($domain in $coord.domains) {
        $domainName = [string]$domain.domain
        $runtimePath = Join-Path $CommonFilesRoot ("state\\_domains\\{0}\\runtime_control.csv" -f $domainName)
        $statePath = Join-Path $CommonFilesRoot ("state\\_domains\\{0}\\session_capital_state.csv" -f $domainName)
        if (-not (Test-Path -LiteralPath $runtimePath)) {
            $issues.Add("Missing domain runtime control: $runtimePath")
        }
        if (-not (Test-Path -LiteralPath $statePath)) {
            $issues.Add("Missing domain state: $statePath")
        }
        $domainReports += [pscustomobject]@{
            domain = $domainName
            runtime_control_present = (Test-Path -LiteralPath $runtimePath)
            state_present = (Test-Path -LiteralPath $statePath)
        }
    }
}

$result = [ordered]@{
    schema_version = "1.1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    common_files_root = $CommonFilesRoot
    config_path = $coordPath
    global_state_present = (Test-Path -LiteralPath $globalPath)
    group_budget_sum = [math]::Round($groupBudgetSum,6)
    domain_reports = @($domainReports)
    ok = ($issues.Count -eq 0)
    issues = @($issues)
}

$result | ConvertTo-Json -Depth 6
