param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$DailyReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\DAILY\raport_dzienny_latest.json",
    [string]$HostingReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_hosting_daily_report_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function To-Int {
    param([object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return 0
    }

    return [int]$Value
}

function To-Double {
    param([object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return 0.0
    }

    return [double]$Value
}

function Read-JsonOrNull {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

if (-not (Test-Path -LiteralPath $DailyReportPath)) {
    throw "Daily system report not found: $DailyReportPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$daily = Get-Content -LiteralPath $DailyReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$dailySummary = $daily.raport_dzienny
$instrumentRows = @($daily.instrumenty)
$hosting = Read-JsonOrNull -Path $HostingReportPath
$hostingOperationalPingMs = if ($null -ne $hosting) { [math]::Round((To-Double $hosting.ping_avg_ms), 2) } else { 0.0 }

$generatedRuntimeLocal = ""
if ($null -ne $dailySummary) {
    $generatedRuntimeLocal = ("{0} {1}" -f [string]$dailySummary.data_raportu, [string]$dailySummary.godzina_raportu).Trim()
}

$windowStartLocal = ""
if ($null -ne $dailySummary -and -not [string]::IsNullOrWhiteSpace([string]$dailySummary.data_raportu)) {
    $windowStartLocal = ("{0} 00:00:00" -f [string]$dailySummary.data_raportu)
}

$keyInstruments = foreach ($row in $instrumentRows) {
    $closes = To-Int $row.zamkniecia_dzis
    $wins = To-Int $row.wygrane_dzis
    $losses = To-Int $row.przegrane_dzis
    $neutral = [math]::Max(0, ($closes - $wins - $losses))

    [pscustomobject]@{
        instrument = [string]$row.instrument
        opens = To-Int $row.otwarcia_dzis
        closes = $closes
        wins = $wins
        losses = $losses
        neutral = $neutral
        net = [math]::Round((To-Double $row.netto_dzis), 2)
        trust = [string]$row.trust_state
        cost = [string]$row.cost_pressure
        market = [string]$row.rodzina
        last_event = [string]$row.ostatni_powod
        fresh = [bool]$row.swiezy
        freshness_seconds = To-Int $row.swiezosc_s
        last_heartbeat = [string]$row.ostatni_heartbeat
        ping_ms = [math]::Round((To-Double $(if ($row.PSObject.Properties.Name -contains 'ping_operacyjny_ms') { $row.ping_operacyjny_ms } else { $row.ping_ms })), 2)
        operational_ping_ms = [math]::Round((To-Double $(if ($row.PSObject.Properties.Name -contains 'ping_operacyjny_ms') { $row.ping_operacyjny_ms } else { $row.ping_ms })), 2)
        terminal_ping_ms = [math]::Round((To-Double $(if ($row.PSObject.Properties.Name -contains 'ping_terminalny_ms') { $row.ping_terminalny_ms } else { $row.ping_ms })), 2)
        local_latency_us_avg = [math]::Round((To-Double $row.latencja_sr_us), 2)
        local_latency_us_max = [math]::Round((To-Double $row.latencja_max_us), 2)
    }
}

$topActive = @(
    $keyInstruments |
        Where-Object { $_.opens -gt 0 -or $_.closes -gt 0 -or [math]::Abs($_.net) -gt 0.000001 } |
        Sort-Object `
            @{ Expression = "opens"; Descending = $true }, `
            @{ Expression = { [math]::Abs($_.net) }; Descending = $true }, `
            @{ Expression = "instrument"; Descending = $false }
)

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    source = "makro_daily_runtime"
    project_root = $ProjectRoot
    source_paths = [ordered]@{
        daily_report = $DailyReportPath
    }
    generated_local = $generatedRuntimeLocal
    window_start_local = $windowStartLocal
    net = [math]::Round((To-Double $dailySummary.netto_dzis), 2)
    active_instruments = @($keyInstruments | Where-Object { $_.opens -gt 0 -or $_.closes -gt 0 -or [math]::Abs($_.net) -gt 0.000001 }).Count
    warnings = 0
    summary = [ordered]@{
        state = [string]$dailySummary.stan_systemu
        state_description = [string]$dailySummary.opis_stanu
        total_instruments = To-Int $dailySummary.liczba_instrumentow
        fresh_instruments = To-Int $dailySummary.liczba_swiezych
        opens = To-Int $dailySummary.otwarcia_dzis
        closes = To-Int $dailySummary.zamkniecia_dzis
        wins = To-Int $dailySummary.wygrane_dzis
        losses = To-Int $dailySummary.przegrane_dzis
        success_rate_pct = [math]::Round((To-Double $dailySummary.skutecznosc_dzis_proc), 2)
        operational_ping_ms_avg = if ($hostingOperationalPingMs -gt 0) { $hostingOperationalPingMs } else { [math]::Round((To-Double $(if ($dailySummary.PSObject.Properties.Name -contains 'sredni_ping_operacyjny_ms') { $dailySummary.sredni_ping_operacyjny_ms } else { $dailySummary.sredni_ping_ms })), 2) }
        terminal_ping_ms_avg = [math]::Round((To-Double $(if ($dailySummary.PSObject.Properties.Name -contains 'sredni_ping_terminalny_ms') { $dailySummary.sredni_ping_terminalny_ms } else { $dailySummary.sredni_ping_ms })), 2)
        local_latency_us_avg = [math]::Round((To-Double $dailySummary.srednia_latencja_bota_us), 2)
        local_latency_us_max = [math]::Round((To-Double $dailySummary.maksymalna_latencja_bota_us), 2)
    }
    top_active = $topActive
    key_instruments = $keyInstruments
}

$jsonLatest = Join-Path $OutputRoot "paper_live_feedback_latest.json"
$mdLatest = Join-Path $OutputRoot "paper_live_feedback_latest.md"

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Canonical Paper Live Feedback")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- source: {0}" -f $report.source))
$lines.Add(("- generated_local: {0}" -f $report.generated_local))
$lines.Add(("- window_start_local: {0}" -f $report.window_start_local))
$lines.Add(("- net: {0}" -f $report.net))
$lines.Add(("- active_instruments: {0}" -f $report.active_instruments))
$lines.Add(("- operational_ping_ms_avg: {0}" -f $report.summary.operational_ping_ms_avg))
$lines.Add(("- terminal_ping_ms_avg: {0}" -f $report.summary.terminal_ping_ms_avg))
$lines.Add(("- local_latency_us_avg: {0}" -f $report.summary.local_latency_us_avg))
$lines.Add(("- local_latency_us_max: {0}" -f $report.summary.local_latency_us_max))
$lines.Add("")
$lines.Add("## Top Active")
$lines.Add("")
if (@($topActive).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in ($topActive | Select-Object -First 8)) {
        $lines.Add(("- {0}: net={1} opens={2} closes={3} wins={4} losses={5} trust={6} cost={7}" -f
            $item.instrument,
            $item.net,
            $item.opens,
            $item.closes,
            $item.wins,
            $item.losses,
            $item.trust,
            $item.cost))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
$report
