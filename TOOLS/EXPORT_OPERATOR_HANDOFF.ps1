param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$HandoffRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\HANDOFF"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
New-Item -ItemType Directory -Force -Path $HandoffRoot | Out-Null

$dirs = @(
    $HandoffRoot,
    (Join-Path $HandoffRoot "DOCS"),
    (Join-Path $HandoffRoot "EVIDENCE"),
    (Join-Path $HandoffRoot "RUN"),
    (Join-Path $HandoffRoot "CONFIG"),
    (Join-Path $HandoffRoot "TOOLS")
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$copies = @(
    @{ src = "DOCS\02_MODEL_WDROZENIA_11_BOTOW_OANDA_MT5.md"; dst = "DOCS\02_MODEL_WDROZENIA_11_BOTOW_OANDA_MT5.md" },
    @{ src = "DOCS\06_MT5_CHART_ATTACHMENT_PLAN.md"; dst = "DOCS\06_MT5_CHART_ATTACHMENT_PLAN.md" },
    @{ src = "DOCS\06_MT5_CHART_ATTACHMENT_PLAN.txt"; dst = "DOCS\06_MT5_CHART_ATTACHMENT_PLAN.txt" },
    @{ src = "DOCS\06_MT5_CHART_ATTACHMENT_PLAN.json"; dst = "DOCS\06_MT5_CHART_ATTACHMENT_PLAN.json" },
    @{ src = "DOCS\09_KILL_SWITCH_MODEL.md"; dst = "DOCS\09_KILL_SWITCH_MODEL.md" },
    @{ src = "DOCS\10_OPERATOR_ROLLOUT_CHECKLIST.md"; dst = "DOCS\10_OPERATOR_ROLLOUT_CHECKLIST.md" },
    @{ src = "DOCS\11_REMOTE_MT5_INSTALL.md"; dst = "DOCS\11_REMOTE_MT5_INSTALL.md" },
    @{ src = "DOCS\24_FAMILY_SCENARIO_TESTS_AND_OPERATOR_REPORTS.md"; dst = "DOCS\24_FAMILY_SCENARIO_TESTS_AND_OPERATOR_REPORTS.md" },
    @{ src = "DOCS\25_DZIENNE_RAPORTY_I_DASHBOARD_PL.md"; dst = "DOCS\25_DZIENNE_RAPORTY_I_DASHBOARD_PL.md" },
    @{ src = "DOCS\26_RAPORT_WIECZORNY_WLASCICIELA_PL.md"; dst = "DOCS\26_RAPORT_WIECZORNY_WLASCICIELA_PL.md" },
    @{ src = "RUN\README_RUN.txt"; dst = "RUN\README_RUN.txt" },
    @{ src = "RUN\PREPARE_MT5_ROLLOUT.ps1"; dst = "RUN\PREPARE_MT5_ROLLOUT.ps1" },
    @{ src = "RUN\GENERATE_DAILY_REPORTS_NOW.ps1"; dst = "RUN\GENERATE_DAILY_REPORTS_NOW.ps1" },
    @{ src = "RUN\GENERATE_EVENING_REPORT_NOW.ps1"; dst = "RUN\GENERATE_EVENING_REPORT_NOW.ps1" },
    @{ src = "RUN\PANEL_OPERATORA_PL.ps1"; dst = "RUN\PANEL_OPERATORA_PL.ps1" },
    @{ src = "RUN\WLACZ_TRYB_NORMALNY_SYSTEMU.ps1"; dst = "RUN\WLACZ_TRYB_NORMALNY_SYSTEMU.ps1" },
    @{ src = "RUN\WLACZ_CLOSE_ONLY_SYSTEMU.ps1"; dst = "RUN\WLACZ_CLOSE_ONLY_SYSTEMU.ps1" },
    @{ src = "RUN\ZATRZYMAJ_SYSTEM.ps1"; dst = "RUN\ZATRZYMAJ_SYSTEM.ps1" },
    @{ src = "TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1"; dst = "TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1" },
    @{ src = "TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1"; dst = "TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1" },
    @{ src = "TOOLS\SIMULATE_MT5_SERVER_INSTALL.ps1"; dst = "TOOLS\SIMULATE_MT5_SERVER_INSTALL.ps1" },
    @{ src = "TOOLS\GENERATE_FAMILY_OPERATOR_REPORT.ps1"; dst = "TOOLS\GENERATE_FAMILY_OPERATOR_REPORT.ps1" },
    @{ src = "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1"; dst = "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1" },
    @{ src = "TOOLS\REGISTER_DAILY_REPORT_TASK.ps1"; dst = "TOOLS\REGISTER_DAILY_REPORT_TASK.ps1" },
    @{ src = "TOOLS\GENERATE_EVENING_OWNER_REPORT.ps1"; dst = "TOOLS\GENERATE_EVENING_OWNER_REPORT.ps1" },
    @{ src = "TOOLS\REGISTER_EVENING_REPORT_TASK.ps1"; dst = "TOOLS\REGISTER_EVENING_REPORT_TASK.ps1" },
    @{ src = "TOOLS\SET_RUNTIME_CONTROL_PL.ps1"; dst = "TOOLS\SET_RUNTIME_CONTROL_PL.ps1" },
    @{ src = "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"; dst = "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1" },
    @{ src = "CONFIG\microbots_registry.json"; dst = "CONFIG\microbots_registry.json" },
    @{ src = "EVIDENCE\prepare_mt5_rollout_report.json"; dst = "EVIDENCE\prepare_mt5_rollout_report.json" },
    @{ src = "EVIDENCE\prepare_mt5_rollout_report.txt"; dst = "EVIDENCE\prepare_mt5_rollout_report.txt" },
    @{ src = "EVIDENCE\deployment_readiness_report.json"; dst = "EVIDENCE\deployment_readiness_report.json" },
    @{ src = "EVIDENCE\deployment_readiness_report.txt"; dst = "EVIDENCE\deployment_readiness_report.txt" },
    @{ src = "EVIDENCE\preset_safety_report.json"; dst = "EVIDENCE\preset_safety_report.json" },
    @{ src = "EVIDENCE\preset_safety_report.txt"; dst = "EVIDENCE\preset_safety_report.txt" },
    @{ src = "EVIDENCE\active_live_presets_report.json"; dst = "EVIDENCE\active_live_presets_report.json" },
    @{ src = "EVIDENCE\family_scenario_test_report.json"; dst = "EVIDENCE\family_scenario_test_report.json" },
    @{ src = "EVIDENCE\family_scenario_test_report.txt"; dst = "EVIDENCE\family_scenario_test_report.txt" },
    @{ src = "EVIDENCE\family_operator_report.json"; dst = "EVIDENCE\family_operator_report.json" },
    @{ src = "EVIDENCE\family_operator_report.txt"; dst = "EVIDENCE\family_operator_report.txt" },
    @{ src = "EVIDENCE\runtime_control_summary.json"; dst = "EVIDENCE\runtime_control_summary.json" },
    @{ src = "EVIDENCE\runtime_control_summary.txt"; dst = "EVIDENCE\runtime_control_summary.txt" },
    @{ src = "EVIDENCE\runtime_control_set_report.json"; dst = "EVIDENCE\runtime_control_set_report.json" },
    @{ src = "EVIDENCE\runtime_control_set_report.txt"; dst = "EVIDENCE\runtime_control_set_report.txt" },
    @{ src = "EVIDENCE\daily_reports_generation_report.json"; dst = "EVIDENCE\daily_reports_generation_report.json" },
    @{ src = "EVIDENCE\daily_reports_generation_report.txt"; dst = "EVIDENCE\daily_reports_generation_report.txt" },
    @{ src = "EVIDENCE\evening_reports_generation_report.json"; dst = "EVIDENCE\evening_reports_generation_report.json" },
    @{ src = "EVIDENCE\evening_reports_generation_report.txt"; dst = "EVIDENCE\evening_reports_generation_report.txt" },
    @{ src = "EVIDENCE\DAILY\raport_dzienny_latest.json"; dst = "EVIDENCE\DAILY\raport_dzienny_latest.json" },
    @{ src = "EVIDENCE\DAILY\raport_dzienny_latest.txt"; dst = "EVIDENCE\DAILY\raport_dzienny_latest.txt" },
    @{ src = "EVIDENCE\DAILY\dashboard_dzienny_latest.html"; dst = "EVIDENCE\DAILY\dashboard_dzienny_latest.html" },
    @{ src = "EVIDENCE\DAILY\raport_wieczorny_latest.json"; dst = "EVIDENCE\DAILY\raport_wieczorny_latest.json" },
    @{ src = "EVIDENCE\DAILY\raport_wieczorny_latest.txt"; dst = "EVIDENCE\DAILY\raport_wieczorny_latest.txt" },
    @{ src = "EVIDENCE\DAILY\dashboard_wieczorny_latest.html"; dst = "EVIDENCE\DAILY\dashboard_wieczorny_latest.html" },
    @{ src = "EVIDENCE\simulate_mt5_server_install_report.json"; dst = "EVIDENCE\simulate_mt5_server_install_report.json" },
    @{ src = "EVIDENCE\simulate_mt5_server_install_report.txt"; dst = "EVIDENCE\simulate_mt5_server_install_report.txt" }
)

$copied = @()
foreach ($item in $copies) {
    $src = Join-Path $projectPath $item.src
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Missing handoff artifact: $src"
    }

    $dst = Join-Path $HandoffRoot $item.dst
    $dstDir = Split-Path -Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    $copied += $item.dst
}

$summary = @()
$summary += "OPERATOR HANDOFF"
$summary += ""
$summary += "Najwazniejsze wejscie operatorskie:"
$summary += "powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\PREPARE_MT5_ROLLOUT.ps1"
$summary += ""
$summary += "Sprawdz przed attach:"
$summary += "- EVIDENCE\\prepare_mt5_rollout_report.json"
$summary += "- EVIDENCE\\deployment_readiness_report.json"
$summary += "- EVIDENCE\\preset_safety_report.json"
$summary += "- EVIDENCE\\family_scenario_test_report.json"
$summary += "- EVIDENCE\\family_operator_report.json"
$summary += "- EVIDENCE\\DAILY\\raport_dzienny_latest.txt"
$summary += "- EVIDENCE\\DAILY\\dashboard_dzienny_latest.html"
$summary += "- EVIDENCE\\DAILY\\raport_wieczorny_latest.txt"
$summary += "- EVIDENCE\\DAILY\\dashboard_wieczorny_latest.html"
$summary += "- DOCS\\10_OPERATOR_ROLLOUT_CHECKLIST.md"
$summary += "- DOCS\\11_REMOTE_MT5_INSTALL.md"
$summary += "- DOCS\\24_FAMILY_SCENARIO_TESTS_AND_OPERATOR_REPORTS.md"
$summary += "- DOCS\\25_DZIENNE_RAPORTY_I_DASHBOARD_PL.md"
$summary += "- DOCS\\26_RAPORT_WIECZORNY_WLASCICIELA_PL.md"
$summary += ""
$summary += "Domyslne presety repo sa bezpieczne (`InpEnableLiveEntries=false`)."
$summary += "Presety aktywne sa generowane swiadomie do SERVER_PROFILE\\PACKAGE\\MQL5\\Presets\\ActiveLive."

$summaryPath = Join-Path $HandoffRoot "HANDOFF_SUMMARY.txt"
$summary | Set-Content -LiteralPath $summaryPath -Encoding ASCII

$manifest = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    handoff_root = $HandoffRoot
    copied = $copied
    summary = "HANDOFF_SUMMARY.txt"
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $HandoffRoot "handoff_manifest.json") -Encoding UTF8
Write-Host "Exported operator handoff to $HandoffRoot"
