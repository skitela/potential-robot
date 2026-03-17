param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-KeyValueTabFile {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $parts = $_ -split "`t", 2
        if ($parts.Length -eq 2) {
            $map[$parts[0]] = $parts[1]
        }
    }
    return $map
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($CommonFilesRoot)) {
    $CommonFilesRoot = Join-Path $env:APPDATA "MetaQuotes\\Terminal\\Common\\Files\\MAKRO_I_MIKRO_BOT"
}

$registryPath = Join-Path $projectPath "CONFIG\\tuning_fleet_registry.json"
if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing tuning fleet registry: $registryPath"
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$issues = New-Object System.Collections.Generic.List[string]
$familyReports = @()

foreach ($family in $registry.families) {
    $policyPath = Join-Path ([string]$family.expected_state_dir) "tuning_family_policy.csv"
    $actionLogPath = Join-Path ([string]$family.expected_log_dir) "tuning_family_actions.csv"
    $seedPath = [string]$family.local_seed_file

    if (-not (Test-Path -LiteralPath $seedPath)) { $issues.Add("Missing seed for family $($family.family): $seedPath") }
    if (-not (Test-Path -LiteralPath $policyPath)) { $issues.Add("Missing family state for $($family.family): $policyPath") }
    if (-not (Test-Path -LiteralPath $actionLogPath)) { $issues.Add("Missing family log for $($family.family): $actionLogPath") }

    $policy = Read-KeyValueTabFile -Path $policyPath
    if ($policy.Count -gt 0) {
        foreach ($requiredKey in @("enabled","trusted_data","freeze_new_changes","symbol_count","dominant_confidence_cap","dominant_risk_cap","last_action_code")) {
            if (-not $policy.ContainsKey($requiredKey)) {
                $issues.Add("Family policy $($family.family) missing key: $requiredKey")
            }
        }
    }

    $familyReports += [pscustomobject]@{
        family = $family.family
        state_present = (Test-Path -LiteralPath $policyPath)
        log_present = (Test-Path -LiteralPath $actionLogPath)
        trusted_data = $policy["trusted_data"]
        freeze_new_changes = $policy["freeze_new_changes"]
        last_action_code = $policy["last_action_code"]
    }
}

$coordStatePath = Join-Path ([string]$registry.coordinator.expected_state_dir) "tuning_coordinator_state.csv"
$coordActionLogPath = Join-Path ([string]$registry.coordinator.expected_log_dir) "tuning_coordinator_actions.csv"
if (-not (Test-Path -LiteralPath $coordStatePath)) { $issues.Add("Missing coordinator state: $coordStatePath") }
if (-not (Test-Path -LiteralPath $coordActionLogPath)) { $issues.Add("Missing coordinator log: $coordActionLogPath") }

$coordState = Read-KeyValueTabFile -Path $coordStatePath
if ($coordState.Count -gt 0) {
    foreach ($requiredKey in @("enabled","trusted_data","freeze_new_changes","family_count","global_confidence_cap","global_risk_cap","max_local_changes_per_cycle","last_action_code")) {
        if (-not $coordState.ContainsKey($requiredKey)) {
            $issues.Add("Coordinator state missing key: $requiredKey")
        }
    }
}

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    common_files_root = $CommonFilesRoot
    ok = ($issues.Count -eq 0)
    family_reports = @($familyReports)
    coordinator = [ordered]@{
        state_present = (Test-Path -LiteralPath $coordStatePath)
        log_present = (Test-Path -LiteralPath $coordActionLogPath)
        trusted_data = $coordState["trusted_data"]
        freeze_new_changes = $coordState["freeze_new_changes"]
        last_action_code = $coordState["last_action_code"]
    }
    issues = @($issues)
}

$evidenceDir = Join-Path $projectPath "EVIDENCE"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$jsonPath = Join-Path $evidenceDir "tuning_hierarchy_validation_report.json"
$txtPath = Join-Path $evidenceDir "tuning_hierarchy_validation_report.txt"

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
@(
    "TUNING HIERARCHY VALIDATION",
    "",
    ("ok={0}" -f $result.ok),
    ("families={0}" -f $familyReports.Count),
    ("coordinator_state_present={0}" -f $result.coordinator.state_present),
    ("coordinator_log_present={0}" -f $result.coordinator.log_present),
    ("coordinator_last_action={0}" -f $result.coordinator.last_action_code),
    "",
    "issues:"
 ) + @($issues | ForEach-Object { "- $_" }) | Set-Content -LiteralPath $txtPath -Encoding UTF8

$result | ConvertTo-Json -Depth 6
