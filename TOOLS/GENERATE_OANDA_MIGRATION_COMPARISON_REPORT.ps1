param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$BaselinePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\oanda_paper_live_baseline_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Load-Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Normalize-Inputs {
    param($Value)
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @()
        }
        return @($Value)
    }
    if ($Value -is [System.Array]) {
        return @($Value)
    }
    if ($Value -is [pscustomobject]) {
        if (@($Value.PSObject.Properties).Count -eq 0) {
            return @()
        }
        return @($Value)
    }
    if ($Value -is [hashtable]) {
        if ($Value.Count -eq 0) {
            return @()
        }
        return @($Value)
    }
    if (-not $Value.PSObject -or @($Value.PSObject.Properties).Count -eq 0) {
        return @()
    }
    return @($Value)
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$baseline = Load-Json -Path $BaselinePath
$prepare = Load-Json -Path (Join-Path $projectPath "EVIDENCE\prepare_mt5_rollout_report.json")
$install = Load-Json -Path (Join-Path $projectPath "EVIDENCE\install_mt5_server_package_report.json")
$validate = Load-Json -Path (Join-Path $projectPath "EVIDENCE\validate_mt5_server_install_report.json")
$profile = Load-Json -Path (Join-Path $projectPath "EVIDENCE\mt5_microbots_profile_setup_report.json")
$paperLive = Load-Json -Path (Join-Path $projectPath "EVIDENCE\OPS\paper_live_feedback_latest.json")
$hosting = Load-Json -Path (Join-Path $projectPath "EVIDENCE\OPS\mt5_hosting_daily_report_latest.json")
$profit = Load-Json -Path (Join-Path $projectPath "EVIDENCE\OPS\profit_tracking_latest.json")
$nearProfit = Load-Json -Path (Join-Path $projectPath "EVIDENCE\OPS\near_profit_optimization_queue_latest.json")
$fullStack = Load-Json -Path (Join-Path $projectPath "EVIDENCE\OPS\full_stack_audit_latest.json")

$profitRows = @{}
if ($profit) {
    foreach ($section in @("live_positive", "tester_positive", "near_profit", "runtime_watchlist", "all")) {
        if (-not ($profit.PSObject.Properties.Name -contains $section)) {
            continue
        }
        foreach ($row in @($profit.$section)) {
            if ($row.symbol_alias) {
                $profitRows[$row.symbol_alias] = $row
            }
        }
    }
}

$currentProcesses = Get-Process terminal64 -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -like "*OANDA TMS Brokers S.A.*" } |
    Select-Object Id, MainWindowTitle, StartTime

$localProcesses = @($currentProcesses | Where-Object { $_.MainWindowTitle -notmatch '\[VPS\]' })
$vpsProcesses = @($currentProcesses | Where-Object { $_.MainWindowTitle -match '\[VPS\]' })

$instrumentRows = @()
foreach ($row in @($baseline.instrument_rows)) {
    $symbol = [string]$row.symbol
    $profitRow = $profitRows[$symbol]
    $parameterChangeSurface = "none_detected"
    if ($row.repo_live_entries -ne $row.terminal_active_live_entries) {
        $parameterChangeSurface = "active_live_toggle_and_new_ex5"
    }
    $instrumentRows += [ordered]@{
        symbol = $symbol
        broker_symbol = $row.broker_symbol
        session_profile = $row.session_profile
        friday_net = $row.friday_net
        friday_opens = $row.friday_opens
        friday_wins = $row.friday_wins
        friday_losses = $row.friday_losses
        friday_trust = $row.friday_trust
        friday_exec = $row.friday_exec
        friday_cost = $row.friday_cost
        sunday_net = $row.sunday_net
        sunday_opens = $row.sunday_opens
        sunday_wins = $row.sunday_wins
        sunday_losses = $row.sunday_losses
        sunday_trust = $row.sunday_trust
        sunday_exec = $row.sunday_exec
        sunday_cost = $row.sunday_cost
        sunday_ping_ms = $row.sunday_ping_ms
        sunday_latency_avg_us = $row.sunday_latency_avg_us
        sunday_latency_max_us = $row.sunday_latency_max_us
        repo_live_entries = $row.repo_live_entries
        package_live_entries = $row.package_active_live_entries
        terminal_live_entries = $row.terminal_active_live_entries
        parameter_change_surface = $parameterChangeSurface
        terminal_ex5_mtime = $row.terminal_ex5_mtime
        terminal_ex5_size = $row.terminal_ex5_size
        current_status = if ($profitRow) { $profitRow.status } else { "" }
        current_live_net_24h = if ($profitRow) { $profitRow.live_net_24h } else { $null }
        best_tester_pnl = if ($profitRow) { $profitRow.best_tester_pnl } else { $null }
        best_tester_inputs = if ($profitRow) { Normalize-Inputs $profitRow.best_tester_optimization_inputs } else { @() }
        active_candidate_pnl = if ($profitRow) { $profitRow.active_optimization_candidate_pnl } else { $null }
        active_candidate_inputs = if ($profitRow) { Normalize-Inputs $profitRow.active_optimization_candidate_inputs } else { @() }
        current_priority_score = if ($profitRow) { $profitRow.current_priority_score } else { $null }
        current_priority_trust = if ($profitRow) { $profitRow.current_priority_trust } else { "" }
        current_priority_cost = if ($profitRow) { $profitRow.current_priority_cost } else { "" }
        current_priority_spread_points = if ($profitRow) { $profitRow.current_priority_spread_points } else { $null }
        qdm_custom_pilot_ready = if ($profitRow) { [bool]$profitRow.qdm_custom_pilot_ready } else { $false }
        qdm_custom_symbol = if ($profitRow) { $profitRow.qdm_custom_symbol } else { "" }
        qdm_pilot_result = if ($profitRow) { $profitRow.qdm_pilot_result } else { "" }
        recommended_action = if ($profitRow) { $profitRow.recommended_action } else { "" }
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    baseline_path = $BaselinePath
    migration_preflight_ok = [bool]$prepare.ok
    install_ok = [bool]$validate.ok
    profile_setup_ok = [bool]$profile.ok
    profile_launch_visible = if ($profile.launch_report) { [bool]$profile.launch_report.launched } else { [bool]$profile.launched }
    profile_launch_note = if ($profile.launch_report) { $profile.launch_report.launch_note } else { "" }
    current_oanda_process_count = @($currentProcesses).Count
    current_local_oanda_process_count = @($localProcesses).Count
    current_vps_process_count = @($vpsProcesses).Count
    current_processes = @($currentProcesses)
    rollout_window_basis = [ordered]@{
        friday_report_path = $baseline.friday_report_path
        sunday_report_path = $baseline.sunday_report_path
        friday_net = $baseline.friday_summary.netto_dzis
        friday_opens = $baseline.friday_summary.otwarcia_dzis
        friday_closes = $baseline.friday_summary.zamkniecia_dzis
        friday_wins = $baseline.friday_summary.wygrane_dzis
        friday_losses = $baseline.friday_summary.przegrane_dzis
        friday_ping_ms = $baseline.friday_summary.sredni_ping_ms
        sunday_net = $baseline.sunday_summary.netto_dzis
        sunday_opens = $baseline.sunday_summary.otwarcia_dzis
        sunday_closes = $baseline.sunday_summary.zamkniecia_dzis
        sunday_wins = $baseline.sunday_summary.wygrane_dzis
        sunday_losses = $baseline.sunday_summary.przegrane_dzis
        sunday_ping_ms = $baseline.sunday_summary.sredni_ping_ms
        sunday_latency_avg_us = $baseline.sunday_summary.srednia_latencja_bota_us
        sunday_latency_max_us = $baseline.sunday_summary.maksymalna_latencja_bota_us
    }
    hosting = [ordered]@{
        friday = $baseline.hosting_friday
        sunday = $baseline.hosting_sunday
        latest = $hosting
    }
    live_runtime = $paperLive
    current_learning = [ordered]@{
        near_profit = $nearProfit
        full_stack = $fullStack
    }
    instrument_rows = $instrumentRows
}

$opsDir = Join-Path $projectPath "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $opsDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonLatest = Join-Path $opsDir "oanda_migration_comparison_latest.json"
$jsonStamp = Join-Path $opsDir ("oanda_migration_comparison_{0}.json" -f $stamp)
$mdLatest = Join-Path $opsDir "oanda_migration_comparison_latest.md"
$mdStamp = Join-Path $opsDir ("oanda_migration_comparison_{0}.md" -f $stamp)

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonStamp -Encoding UTF8

$lines = @()
$lines += "# OANDA Migration Comparison"
$lines += ""
$lines += "- generated_at_local: $($report.generated_at_local)"
$lines += "- migration_preflight_ok: $($report.migration_preflight_ok)"
$lines += "- install_ok: $($report.install_ok)"
$lines += "- profile_setup_ok: $($report.profile_setup_ok)"
$lines += "- profile_launch_visible: $($report.profile_launch_visible)"
$lines += "- profile_launch_note: $($report.profile_launch_note)"
$lines += "- current_oanda_process_count: $($report.current_oanda_process_count)"
$lines += "- current_local_oanda_process_count: $($report.current_local_oanda_process_count)"
$lines += "- current_vps_process_count: $($report.current_vps_process_count)"
$lines += ""
$lines += "## Friday vs Sunday"
$lines += "- friday_net: $($report.rollout_window_basis.friday_net)"
$lines += "- friday_opens: $($report.rollout_window_basis.friday_opens)"
$lines += "- friday_wins: $($report.rollout_window_basis.friday_wins)"
$lines += "- friday_losses: $($report.rollout_window_basis.friday_losses)"
$lines += "- friday_ping_ms: $($report.rollout_window_basis.friday_ping_ms)"
$lines += "- sunday_net: $($report.rollout_window_basis.sunday_net)"
$lines += "- sunday_opens: $($report.rollout_window_basis.sunday_opens)"
$lines += "- sunday_wins: $($report.rollout_window_basis.sunday_wins)"
$lines += "- sunday_losses: $($report.rollout_window_basis.sunday_losses)"
$lines += "- sunday_ping_ms: $($report.rollout_window_basis.sunday_ping_ms)"
$lines += "- sunday_latency_avg_us: $($report.rollout_window_basis.sunday_latency_avg_us)"
$lines += ""
$lines += "## Current Learning Highlights"
$lines += "- near_profit_symbol: $($nearProfit.current_symbol)"
$lines += "- near_profit_best_pass_pnl: $($nearProfit.active_sandbox.best_tester_pass_realized_pnl)"
$lines += "- near_profit_best_pass_inputs: $(([string]::Join(', ', @($nearProfit.active_sandbox.best_tester_pass_inputs))))"
$lines += ""
$lines += "## Instrument Summary"
foreach ($row in $instrumentRows) {
    $lines += "- $($row.symbol) [$($row.broker_symbol)] status=$($row.current_status) friday_net=$($row.friday_net) sunday_opens=$($row.sunday_opens) terminal_live=$($row.terminal_live_entries) repo_live=$($row.repo_live_entries) best_tester_pnl=$($row.best_tester_pnl) active_candidate_pnl=$($row.active_candidate_pnl) spread=$($row.current_priority_spread_points) qdm_ready=$($row.qdm_custom_pilot_ready)"
}

$lines | Set-Content -LiteralPath $mdLatest -Encoding UTF8
$lines | Set-Content -LiteralPath $mdStamp -Encoding UTF8

$report | ConvertTo-Json -Depth 8
