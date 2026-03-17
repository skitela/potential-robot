param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$packageRoot = Join-Path $projectPath "SERVER_PROFILE\PACKAGE"
$handoffRoot = Join-Path $projectPath "SERVER_PROFILE\HANDOFF"
$issues = New-Object System.Collections.Generic.List[string]

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
    if (-not ($handoffManifest.copied -contains "RUN\GENERATE_DAILY_REPORTS_NOW.ps1")) {
        $issues.Add("HANDOFF_DAILY_REPORT_RUNNER_NOT_DECLARED")
    }
    if (-not ($handoffManifest.copied -contains "RUN\GENERATE_EVENING_REPORT_NOW.ps1")) {
        $issues.Add("HANDOFF_EVENING_REPORT_RUNNER_NOT_DECLARED")
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
