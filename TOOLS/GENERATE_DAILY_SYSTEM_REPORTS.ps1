param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [datetime]$NowLocal = (Get-Date)
)

$ErrorActionPreference = "Stop"

function Read-KeyValueCsv {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($row in (Import-Csv -Delimiter "`t" -Header key,value -Path $Path)) {
        if ($null -ne $row.key -and $row.key -ne "key") {
            $map[[string]$row.key] = [string]$row.value
        }
    }
    return $map
}

function Read-JsonOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { return $null }
}

function To-DoubleOrZero {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 0.0 }
    return [double]$Value
}

function To-LongOrZero {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 0L }
    return [long]$Value
}

function Format-PL {
    param(
        [double]$Value,
        [int]$Decimals = 2
    )
    return $Value.ToString(("N{0}" -f $Decimals), [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL"))
}

function Format-Duration {
    param([long]$Seconds)
    if ($Seconds -le 0) { return "0 min" }
    $span = [TimeSpan]::FromSeconds($Seconds)
    if ($span.TotalHours -ge 1) {
        return ("{0} h {1} min" -f [math]::Floor($span.TotalHours), $span.Minutes)
    }
    return ("{0} min" -f [math]::Max(1, [math]::Floor($span.TotalMinutes)))
}

function Convert-FromUnixLocal {
    param([long]$Ts)
    if ($Ts -le 0) { return $null }
    return [DateTimeOffset]::FromUnixTimeSeconds($Ts).ToLocalTime().DateTime
}

function Get-SymbolCode {
    param($Item)
    if ($Item.PSObject.Properties.Name -contains "code_symbol" -and -not [string]::IsNullOrWhiteSpace([string]$Item.code_symbol)) {
        return [string]$Item.code_symbol
    }
    return ([string]$Item.symbol) -replace '\.pro$',''
}

function Get-LearningStats {
    param(
        [string]$Path,
        [long]$TodayStartTs,
        [long]$YesterdayStartTs,
        [long]$NowTs
    )

    $stats = [ordered]@{
        net_today = 0.0
        net_yesterday = 0.0
        wins_today = 0
        losses_today = 0
        closes_today = 0
        wins_yesterday = 0
        losses_yesterday = 0
        closes_yesterday = 0
    }

    if (-not (Test-Path -LiteralPath $Path)) { return $stats }

    foreach ($row in (Import-Csv -Delimiter "`t" -Path $Path)) {
        $ts = To-LongOrZero $row.ts
        if ($ts -lt $YesterdayStartTs -or $ts -gt $NowTs) { continue }

        $pnl = To-DoubleOrZero $row.pnl
        if ($ts -ge $TodayStartTs) {
            $stats.net_today += $pnl
            $stats.closes_today++
            if ($pnl -gt 0) { $stats.wins_today++ }
            elseif ($pnl -lt 0) { $stats.losses_today++ }
        } else {
            $stats.net_yesterday += $pnl
            $stats.closes_yesterday++
            if ($pnl -gt 0) { $stats.wins_yesterday++ }
            elseif ($pnl -lt 0) { $stats.losses_yesterday++ }
        }
    }

    $stats.net_today = [math]::Round($stats.net_today, 2)
    $stats.net_yesterday = [math]::Round($stats.net_yesterday, 2)
    return $stats
}

function Get-DecisionStats {
    param(
        [string]$Path,
        [long]$TodayStartTs
    )

    $stats = [ordered]@{
        opens_today = 0
        last_reason = ""
    }

    if (-not (Test-Path -LiteralPath $Path)) { return $stats }

    foreach ($row in (Import-Csv -Delimiter "`t" -Path $Path)) {
        $ts = To-LongOrZero $row.ts
        if ($ts -lt $TodayStartTs) { continue }
        if ([string]$row.phase -eq "PAPER_OPEN" -and [string]$row.verdict -eq "OK") {
            $stats.opens_today++
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$row.reason)) {
            $stats.last_reason = [string]$row.reason
        }
    }

    return $stats
}

function Get-FamilyLabel {
    param([string]$Family)
    switch ($Family) {
        "FX_MAIN" { return "Waluty glowne" }
        "FX_ASIA" { return "Waluty azjatyckie" }
        "FX_CROSS" { return "Crossy walutowe" }
        "METALS_SPOT_PM" { return "Metale spot" }
        "METALS_FUTURES" { return "Metale futures" }
        "INDEX_EU" { return "Indeksy europejskie" }
        "INDEX_US" { return "Indeksy amerykanskie" }
        default { return $Family }
    }
}

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
$dailyDir = Join-Path $ProjectRoot "EVIDENCE\DAILY"
New-Item -ItemType Directory -Force -Path $dailyDir | Out-Null

$nowTs = [long]([DateTimeOffset]$NowLocal).ToUnixTimeSeconds()
$todayStartLocal = Get-Date -Date $NowLocal.Date
$todayStartTsDefault = [long]([DateTimeOffset]$todayStartLocal).ToUnixTimeSeconds()
$yesterdayStartTsDefault = $todayStartTsDefault - 86400
$reportTs = $NowLocal.ToString("yyyyMMdd_HHmmss")

$rows = @()
foreach ($item in $registry.symbols) {
    $code = Get-SymbolCode -Item $item
    $display = $code
    $family = [string]$item.session_profile

    $stateMap = Read-KeyValueCsv (Join-Path $CommonFilesRoot ("state\{0}\runtime_state.csv" -f $code))
    $summary = Read-JsonOrNull (Join-Path $CommonFilesRoot ("state\{0}\execution_summary.json" -f $code))
    $policy = Read-JsonOrNull (Join-Path $CommonFilesRoot ("state\{0}\informational_policy.json" -f $code))
    $learning = Get-LearningStats -Path (Join-Path $CommonFilesRoot ("logs\{0}\learning_observations_v2.csv" -f $code)) -TodayStartTs $todayStartTsDefault -YesterdayStartTs $yesterdayStartTsDefault -NowTs $nowTs
    $decision = Get-DecisionStats -Path (Join-Path $CommonFilesRoot ("logs\{0}\decision_events.csv" -f $code)) -TodayStartTs $todayStartTsDefault

    $startedAt = To-LongOrZero $stateMap["started_at"]
    $lastHeartbeatAt = To-LongOrZero $stateMap["last_heartbeat_at"]
    $freshnessSec = if ($lastHeartbeatAt -gt 0) { [math]::Max(0, $nowTs - $lastHeartbeatAt) } else { 999999 }
    $workStartTs = [math]::Max($startedAt, $todayStartTsDefault)
    $workEndTs = if ($lastHeartbeatAt -gt 0) { [math]::Min($lastHeartbeatAt, $nowTs) } else { 0 }
    $workTodaySec = if ($workEndTs -gt $workStartTs) { $workEndTs - $workStartTs } else { 0 }
    $fresh = ($freshnessSec -le 300)
    $status = if ($fresh) { "Pracuje" } elseif ($freshnessSec -le 900) { "Uwaga" } else { "Stare dane" }

    $pingMs = if ($summary) { To-DoubleOrZero $summary.terminal_ping_ms } elseif ($policy) { To-DoubleOrZero $policy.terminal_ping_ms } else { 0.0 }
    $latencyAvgUs = if ($summary) { To-DoubleOrZero $summary.local_latency_us_avg } elseif ($policy) { To-DoubleOrZero $policy.local_latency_us_avg } else { 0.0 }
    $latencyMaxUs = if ($summary) { To-DoubleOrZero $summary.local_latency_us_max } elseif ($policy) { To-DoubleOrZero $policy.local_latency_us_max } else { 0.0 }
    $trustState = if ($summary) { [string]$summary.trust_state } elseif ($policy) { [string]$policy.trust_state } else { "" }
    $executionState = if ($summary) { [string]$summary.execution_quality_state } elseif ($policy) { [string]$policy.execution_quality_state } else { "" }
    $costState = if ($summary) { [string]$summary.cost_pressure_state } elseif ($policy) { [string]$policy.cost_pressure_state } else { "" }
    $lastReason = if ($policy -and -not [string]::IsNullOrWhiteSpace([string]$policy.reason_code)) { [string]$policy.reason_code } elseif ($summary -and -not [string]::IsNullOrWhiteSpace([string]$summary.reason_code)) { [string]$summary.reason_code } else { [string]$decision.last_reason }

    $rows += [pscustomobject]@{
        instrument = $display
        rodzina = $family
        rodzina_label = Get-FamilyLabel -Family $family
        status_pracy = $status
        swiezy = $fresh
        swiezosc_s = $freshnessSec
        swiezosc_label = Format-Duration -Seconds $freshnessSec
        pracuje_od = if ($startedAt -gt 0) { (Convert-FromUnixLocal $startedAt).ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        ostatni_heartbeat = if ($lastHeartbeatAt -gt 0) { (Convert-FromUnixLocal $lastHeartbeatAt).ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        czas_pracy_dzis_s = $workTodaySec
        czas_pracy_dzis_label = Format-Duration -Seconds $workTodaySec
        netto_dzis = [math]::Round($learning.net_today, 2)
        netto_wczoraj = [math]::Round($learning.net_yesterday, 2)
        zmiana_do_wczoraj = [math]::Round(($learning.net_today - $learning.net_yesterday), 2)
        zamkniecia_dzis = $learning.closes_today
        wygrane_dzis = $learning.wins_today
        przegrane_dzis = $learning.losses_today
        otwarcia_dzis = $decision.opens_today
        skutecznosc_dzis_proc = if ($learning.closes_today -gt 0) { [math]::Round(($learning.wins_today / $learning.closes_today) * 100.0, 1) } else { 0.0 }
        ping_ms = [math]::Round($pingMs, 2)
        latencja_sr_us = [math]::Round($latencyAvgUs, 2)
        latencja_max_us = [math]::Round($latencyMaxUs, 2)
        trust_state = $trustState
        execution_quality = $executionState
        cost_pressure = $costState
        ostatni_powod = $lastReason
    }
}

$freshRows = @($rows | Where-Object { $_.swiezy })
$activeRows = @($rows | Where-Object { $_.czas_pracy_dzis_s -gt 0 })
$systemStart = ($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.pracuje_od) } | Sort-Object pracuje_od | Select-Object -First 1).pracuje_od
$netToday = [math]::Round((($rows | Measure-Object -Property netto_dzis -Sum).Sum), 2)
$netYesterday = [math]::Round((($rows | Measure-Object -Property netto_wczoraj -Sum).Sum), 2)
$winsToday = (($rows | Measure-Object -Property wygrane_dzis -Sum).Sum)
$lossesToday = (($rows | Measure-Object -Property przegrane_dzis -Sum).Sum)
$closesToday = (($rows | Measure-Object -Property zamkniecia_dzis -Sum).Sum)
$winsYesterday = 0
$lossesYesterday = 0
$closesYesterday = 0
foreach ($item in $registry.symbols) {
    $code = Get-SymbolCode -Item $item
    $learning = Get-LearningStats -Path (Join-Path $CommonFilesRoot ("logs\{0}\learning_observations_v2.csv" -f $code)) -TodayStartTs $todayStartTsDefault -YesterdayStartTs $yesterdayStartTsDefault -NowTs $nowTs
    $winsYesterday += $learning.wins_yesterday
    $lossesYesterday += $learning.losses_yesterday
    $closesYesterday += $learning.closes_yesterday
}
$opensToday = (($rows | Measure-Object -Property otwarcia_dzis -Sum).Sum)
$avgPingRaw = ((@($rows | Where-Object { $_.ping_ms -gt 0 }) | Measure-Object -Property ping_ms -Average).Average)
$avgLatencyRaw = ((@($rows | Where-Object { $_.latencja_sr_us -gt 0 }) | Measure-Object -Property latencja_sr_us -Average).Average)
$avgPing = if ($null -ne $avgPingRaw) { [math]::Round($avgPingRaw, 2) } else { 0.0 }
$avgLatencyUs = if ($null -ne $avgLatencyRaw) { [math]::Round($avgLatencyRaw, 2) } else { 0.0 }
$maxLatencyUs = [math]::Round((($rows | Measure-Object -Property latencja_max_us -Maximum).Maximum), 2)
$avgFreshness = [math]::Round((($rows | Measure-Object -Property swiezosc_s -Average).Average), 0)
$maxFreshness = [math]::Round((($rows | Measure-Object -Property swiezosc_s -Maximum).Maximum), 0)
$workTotal = (($rows | Measure-Object -Property czas_pracy_dzis_s -Sum).Sum)
$workAvg = [math]::Round((($rows | Measure-Object -Property czas_pracy_dzis_s -Average).Average), 0)

$systemState = if ($freshRows.Count -eq 0) { "PADL" } elseif ($freshRows.Count -lt $rows.Count) { "UWAGA" } else { "DZIALA" }
$systemNote = switch ($systemState) {
    "DZIALA" { "{0}/{1} instrumentow ma swiezy heartbeat." -f $freshRows.Count, $rows.Count }
    "UWAGA" { "{0}/{1} instrumentow ma swiezy heartbeat, ale czesc danych jest przeterminowana." -f $freshRows.Count, $rows.Count }
    default { "Brak swiezych heartbeatow. System wymaga pilnej kontroli." }
}

$familyRows = @(
    foreach ($familyGroup in ($rows | Group-Object rodzina | Sort-Object Name)) {
        $groupRows = @($familyGroup.Group)
        $familyLatencyRaw = ((@($groupRows | Where-Object { $_.latencja_sr_us -gt 0 }) | Measure-Object -Property latencja_sr_us -Average).Average)
        [pscustomobject]@{
            rodzina = $familyGroup.Name
            rodzina_label = Get-FamilyLabel -Family $familyGroup.Name
            instrumenty = $groupRows.Count
            swieze = @($groupRows | Where-Object { $_.swiezy }).Count
            netto_dzis = [math]::Round((($groupRows | Measure-Object -Property netto_dzis -Sum).Sum), 2)
            zmiana_do_wczoraj = [math]::Round((($groupRows | Measure-Object -Property zmiana_do_wczoraj -Sum).Sum), 2)
            wygrane_dzis = (($groupRows | Measure-Object -Property wygrane_dzis -Sum).Sum)
            przegrane_dzis = (($groupRows | Measure-Object -Property przegrane_dzis -Sum).Sum)
            otwarcia_dzis = (($groupRows | Measure-Object -Property otwarcia_dzis -Sum).Sum)
            ping_sr_ms = [math]::Round((($groupRows | Measure-Object -Property ping_ms -Average).Average), 2)
            latencja_sr_us = if ($null -ne $familyLatencyRaw) { [math]::Round($familyLatencyRaw, 2) } else { 0.0 }
        }
    }
)

$summary = [ordered]@{
    data_raportu = $NowLocal.ToString("yyyy-MM-dd")
    godzina_raportu = $NowLocal.ToString("HH:mm:ss")
    stan_systemu = $systemState
    opis_stanu = $systemNote
    liczba_instrumentow = $rows.Count
    liczba_swiezych = $freshRows.Count
    liczba_nieswiezych = $rows.Count - $freshRows.Count
    liczba_pracujacych_dzis = $activeRows.Count
    system_pracuje_od = $systemStart
    laczny_czas_pracy_dzis_s = $workTotal
    laczny_czas_pracy_dzis_label = Format-Duration -Seconds $workTotal
    sredni_czas_pracy_na_instrument_s = $workAvg
    sredni_czas_pracy_na_instrument_label = Format-Duration -Seconds $workAvg
    netto_dzis = $netToday
    netto_wczoraj = $netYesterday
    zmiana_netto_do_wczoraj = [math]::Round(($netToday - $netYesterday), 2)
    otwarcia_dzis = $opensToday
    zamkniecia_dzis = $closesToday
    wygrane_dzis = $winsToday
    przegrane_dzis = $lossesToday
    skutecznosc_dzis_proc = if ($closesToday -gt 0) { [math]::Round(($winsToday / $closesToday) * 100.0, 1) } else { 0.0 }
    zamkniecia_wczoraj = $closesYesterday
    wygrane_wczoraj = $winsYesterday
    przegrane_wczoraj = $lossesYesterday
    skutecznosc_wczoraj_proc = if ($closesYesterday -gt 0) { [math]::Round(($winsYesterday / $closesYesterday) * 100.0, 1) } else { 0.0 }
    sredni_ping_ms = $avgPing
    srednia_latencja_bota_us = $avgLatencyUs
    maksymalna_latencja_bota_us = $maxLatencyUs
    srednia_swiezosc_s = $avgFreshness
    maksymalna_swiezosc_s = $maxFreshness
}

$report = [ordered]@{
    schema_version = "3.0"
    wygenerowano_utc = (Get-Date).ToUniversalTime().ToString("o")
    raport_dzienny = $summary
    rodziny = $familyRows
    instrumenty = ($rows | Sort-Object instrument)
}

$jsonPath = Join-Path $dailyDir ("raport_dzienny_{0}.json" -f $reportTs)
$txtPath = Join-Path $dailyDir ("raport_dzienny_{0}.txt" -f $reportTs)
$htmlPath = Join-Path $dailyDir ("dashboard_dzienny_{0}.html" -f $reportTs)
$latestJson = Join-Path $dailyDir "raport_dzienny_latest.json"
$latestTxt = Join-Path $dailyDir "raport_dzienny_latest.txt"
$latestHtml = Join-Path $dailyDir "dashboard_dzienny_latest.html"

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJson -Encoding UTF8

$txt = @()
$txt += "RAPORT DZIENNY SYSTEMU"
$txt += "Data: $($summary.data_raportu)  Godzina: $($summary.godzina_raportu)"
$txt += ""
$txt += "STAN SYSTEMU"
$txt += ("Status: {0}" -f $summary.stan_systemu)
$txt += $summary.opis_stanu
$txt += ("Czas pracy dzis: {0}" -f $summary.laczny_czas_pracy_dzis_label)
$txt += ("Sredni czas pracy na instrument: {0}" -f $summary.sredni_czas_pracy_na_instrument_label)
$txt += ""
$txt += "WYNIK PAPER"
$txt += ("Netto dzis: {0}" -f (Format-PL -Value $summary.netto_dzis))
$txt += ("Netto wczoraj: {0}" -f (Format-PL -Value $summary.netto_wczoraj))
$txt += ("Zmiana do wczoraj: {0}" -f (Format-PL -Value $summary.zmiana_netto_do_wczoraj))
$txt += ("Wygrane / przegrane dzis: {0} / {1}" -f $summary.wygrane_dzis, $summary.przegrane_dzis)
$txt += ("Otwarcia dzis: {0} | Zamkniecia dzis: {1} | Skutecznosc: {2}%" -f $summary.otwarcia_dzis, $summary.zamkniecia_dzis, (Format-PL -Value $summary.skutecznosc_dzis_proc -Decimals 1))
$txt += ""
$txt += "TECHNIKA"
$txt += ("Sredni ping: {0} ms" -f (Format-PL -Value $summary.sredni_ping_ms -Decimals 2))
$txt += ("Srednia latencja bota: {0} us" -f (Format-PL -Value $summary.srednia_latencja_bota_us -Decimals 2))
$txt += ("Maksymalna latencja bota: {0} us" -f (Format-PL -Value $summary.maksymalna_latencja_bota_us -Decimals 2))
$txt += ("Swieze instrumenty: {0}/{1}" -f $summary.liczba_swiezych, $summary.liczba_instrumentow)
$txt += ""
$txt += "RODZINY"
foreach ($family in $familyRows) {
    $txt += ("- {0}: netto {1}, zmiana {2}, W/P {3}/{4}, otwarcia {5}, swieze {6}/{7}" -f
        $family.rodzina_label,
        (Format-PL -Value $family.netto_dzis),
        (Format-PL -Value $family.zmiana_do_wczoraj),
        $family.wygrane_dzis,
        $family.przegrane_dzis,
        $family.otwarcia_dzis,
        $family.swieze,
        $family.instrumenty)
}
$txt += ""
$txt += "INSTRUMENTY"
foreach ($row in ($rows | Sort-Object instrument)) {
    $txt += ("- {0} | {1} | praca {2} | swiezosc {3} | netto {4} | zmiana {5} | W/P {6}/{7} | otwarcia {8} | ping {9} ms | latencja {10}/{11} us | trust {12} | exec {13} | cost {14}" -f
        $row.instrument,
        $row.status_pracy,
        $row.czas_pracy_dzis_label,
        $row.swiezosc_label,
        (Format-PL -Value $row.netto_dzis),
        (Format-PL -Value $row.zmiana_do_wczoraj),
        $row.wygrane_dzis,
        $row.przegrane_dzis,
        $row.otwarcia_dzis,
        (Format-PL -Value $row.ping_ms -Decimals 2),
        (Format-PL -Value $row.latencja_sr_us -Decimals 2),
        (Format-PL -Value $row.latencja_max_us -Decimals 2),
        $row.trust_state,
        $row.execution_quality,
        $row.cost_pressure)
}
$txt | Set-Content -LiteralPath $txtPath -Encoding UTF8
$txt | Set-Content -LiteralPath $latestTxt -Encoding UTF8

$familyHtml = ($familyRows | ForEach-Object {
    "<tr><td>$($_.rodzina_label)</td><td>$($_.swieze)/$($_.instrumenty)</td><td>$(Format-PL -Value $_.netto_dzis)</td><td>$(Format-PL -Value $_.zmiana_do_wczoraj)</td><td>$($_.wygrane_dzis)/$($_.przegrane_dzis)</td><td>$($_.otwarcia_dzis)</td><td>$(Format-PL -Value $_.ping_sr_ms -Decimals 2)</td><td>$(Format-PL -Value $_.latencja_sr_us -Decimals 2)</td></tr>"
}) -join "`n"

$workingRowsHtml = ((@($rows | Where-Object { $_.swiezy -and $_.status_pracy -eq "Pracuje" } | Sort-Object netto_dzis -Descending | Select-Object -First 5)) | ForEach-Object {
    "<li><b>$($_.instrument)</b> - praca $($_.czas_pracy_dzis_label), netto $(Format-PL -Value $_.netto_dzis), ping $(Format-PL -Value $_.ping_ms -Decimals 2) ms</li>"
}) -join "`n"
if ([string]::IsNullOrWhiteSpace($workingRowsHtml)) { $workingRowsHtml = "<li>Brak swiezych, aktywnych instrumentow.</li>" }

$blockedRowsHtml = ((@($rows | Where-Object { $_.trust_state -and $_.trust_state -ne "TRUSTED" } | Sort-Object trust_state, instrument | Select-Object -First 7)) | ForEach-Object {
    "<li><b>$($_.instrument)</b> - trust $($_.trust_state), execution $($_.execution_quality), cost $($_.cost_pressure), powod $($_.ostatni_powod)</li>"
}) -join "`n"
if ([string]::IsNullOrWhiteSpace($blockedRowsHtml)) { $blockedRowsHtml = "<li>Brak aktywnych blokad trust.</li>" }

$staleRowsHtml = ((@($rows | Where-Object { -not $_.swiezy } | Sort-Object swiezosc_s -Descending | Select-Object -First 5)) | ForEach-Object {
    "<li><b>$($_.instrument)</b> - status $($_.status_pracy), swiezosc $($_.swiezosc_label), heartbeat $($_.ostatni_heartbeat)</li>"
}) -join "`n"
if ([string]::IsNullOrWhiteSpace($staleRowsHtml)) { $staleRowsHtml = "<li>Wszystkie instrumenty sa swieze.</li>" }

$instrumentHtml = (($rows | Sort-Object instrument) | ForEach-Object {
    $rowClass = if ($_.netto_dzis -gt 0) { "plus" } elseif ($_.netto_dzis -lt 0) { "minus" } else { "zero" }
    "<tr class='$rowClass'><td>$($_.instrument)</td><td>$($_.rodzina_label)</td><td>$($_.status_pracy)</td><td>$($_.czas_pracy_dzis_label)</td><td>$($_.swiezosc_label)</td><td>$(Format-PL -Value $_.netto_dzis)</td><td>$(Format-PL -Value $_.zmiana_do_wczoraj)</td><td>$($_.wygrane_dzis)/$($_.przegrane_dzis)</td><td>$($_.otwarcia_dzis)</td><td>$(Format-PL -Value $_.ping_ms -Decimals 2)</td><td>$(Format-PL -Value $_.latencja_sr_us -Decimals 2)</td><td>$(Format-PL -Value $_.latencja_max_us -Decimals 2)</td><td>$($_.trust_state)</td><td>$($_.execution_quality)</td><td>$($_.cost_pressure)</td><td>$($_.ostatni_powod)</td></tr>"
}) -join "`n"

$html = @"
<!doctype html>
<html lang="pl">
<head>
  <meta charset="utf-8">
  <title>Dashboard dzienny systemu</title>
  <style>
    body{font-family:Segoe UI,Tahoma,sans-serif;background:#f4efe8;color:#1e1a16;margin:0}
    .wrap{max-width:1580px;margin:0 auto;padding:24px}
    .panel{background:#fffaf4;border:1px solid #ddcfbf;border-radius:18px;padding:18px;margin-bottom:18px;box-shadow:0 10px 28px rgba(30,26,22,.06)}
    .hero{display:grid;grid-template-columns:2fr 1fr;gap:18px}
    .cards{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
    .triplet{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
    .card{background:#f8f1e6;border:1px solid #ddcfbf;border-radius:14px;padding:12px}
    .card span{display:block;font-size:12px;color:#6b6158;text-transform:uppercase}
    .card b{display:block;font-size:22px;margin-top:6px}
    .card ul{margin:0;padding-left:18px}
    .card li{margin:6px 0;line-height:1.4}
    table{width:100%;border-collapse:collapse;font-size:14px}
    th,td{padding:9px 8px;border-bottom:1px solid #eadfce;text-align:left;vertical-align:top}
    th{color:#6b6158}
    tr.plus td:nth-child(6),tr.plus td:nth-child(7){color:#1f6a39;font-weight:700}
    tr.minus td:nth-child(6),tr.minus td:nth-child(7){color:#a3312e;font-weight:700}
    tr.zero td:nth-child(6),tr.zero td:nth-child(7){color:#75685a;font-weight:700}
    h1,h2{margin:0 0 10px 0}
    .muted{color:#6b6158}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div class="panel">
        <h1>Dashboard dzienny systemu</h1>
        <div class="muted">Data: $($summary.data_raportu) | Godzina: $($summary.godzina_raportu)</div>
        <p>Ten widok jest ustawiony pod to, co dla Ciebie najważniejsze: czy system zyje, jak swieze sa dane, ile naprawde pracowal, jaki jest wynik netto, ile bylo wygranych i przegranych oraz czy dzisiejszy obraz jest lepszy czy gorszy od wczorajszego.</p>
      </div>
      <div class="panel">
        <h2>Stan systemu</h2>
        <div style="font-size:28px;font-weight:700;margin-bottom:8px">$($summary.stan_systemu)</div>
        <div class="muted">$($summary.opis_stanu)</div>
      </div>
    </div>
    <div class="panel">
      <div class="cards">
        <div class="card"><span>Netto dzis</span><b>$(Format-PL -Value $summary.netto_dzis)</b></div>
        <div class="card"><span>Zmiana do wczoraj</span><b>$(Format-PL -Value $summary.zmiana_netto_do_wczoraj)</b></div>
        <div class="card"><span>Wygrane / przegrane</span><b>$($summary.wygrane_dzis) / $($summary.przegrane_dzis)</b></div>
        <div class="card"><span>Otwarcia dzis</span><b>$($summary.otwarcia_dzis)</b></div>
        <div class="card"><span>Sredni ping</span><b>$(Format-PL -Value $summary.sredni_ping_ms -Decimals 2) ms</b></div>
        <div class="card"><span>Srednia latencja bota</span><b>$(Format-PL -Value $summary.srednia_latencja_bota_us -Decimals 2) us</b></div>
        <div class="card"><span>Czas pracy dzis</span><b>$($summary.laczny_czas_pracy_dzis_label)</b></div>
        <div class="card"><span>Swieze instrumenty</span><b>$($summary.liczba_swiezych) / $($summary.liczba_instrumentow)</b></div>
      </div>
    </div>
    <div class="panel">
      <h2>Na szybko: co zyje, co sie blokuje, co jest stare</h2>
      <div class="triplet">
        <div class="card">
          <span>Co pracuje</span>
          <ul>$workingRowsHtml</ul>
        </div>
        <div class="card">
          <span>Co sie blokuje</span>
          <ul>$blockedRowsHtml</ul>
        </div>
        <div class="card">
          <span>Co jest stare</span>
          <ul>$staleRowsHtml</ul>
        </div>
      </div>
    </div>
    <div class="panel">
      <h2>Rodziny</h2>
      <table>
        <thead><tr><th>Rodzina</th><th>Swieze</th><th>Netto dzis</th><th>Zmiana do wczoraj</th><th>Wygrane / przegrane</th><th>Otwarcia</th><th>Ping sr ms</th><th>Latencja sr us</th></tr></thead>
        <tbody>$familyHtml</tbody>
      </table>
    </div>
    <div class="panel">
      <h2>Instrumenty</h2>
      <table>
        <thead><tr><th>Instrument</th><th>Rodzina</th><th>Status</th><th>Czas pracy</th><th>Swiezosc</th><th>Netto dzis</th><th>Zmiana do wczoraj</th><th>W / P</th><th>Otwarcia</th><th>Ping</th><th>Latencja sr</th><th>Latencja max</th><th>Trust</th><th>Execution</th><th>Cost</th><th>Ostatni powod</th></tr></thead>
        <tbody>$instrumentHtml</tbody>
      </table>
    </div>
  </div>
</body>
</html>
"@

$html | Set-Content -LiteralPath $htmlPath -Encoding UTF8
$html | Set-Content -LiteralPath $latestHtml -Encoding UTF8

$result = [ordered]@{
    schema_version = "3.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    json_report = $jsonPath
    txt_report = $txtPath
    html_dashboard = $htmlPath
    latest_json = $latestJson
    latest_txt = $latestTxt
    latest_html = $latestHtml
}

$resultPath = Join-Path $ProjectRoot "EVIDENCE\daily_reports_generation_report.json"
$resultTxtPath = Join-Path $ProjectRoot "EVIDENCE\daily_reports_generation_report.txt"
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
@(
    "DAILY REPORTS GENERATION"
    ("JSON={0}" -f $jsonPath)
    ("TXT={0}" -f $txtPath)
    ("HTML={0}" -f $htmlPath)
    ("LATEST_HTML={0}" -f $latestHtml)
) | Set-Content -LiteralPath $resultTxtPath -Encoding UTF8

$result | ConvertTo-Json -Depth 6
