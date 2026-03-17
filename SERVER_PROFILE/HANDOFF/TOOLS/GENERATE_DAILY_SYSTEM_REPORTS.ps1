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
    foreach ($row in Import-Csv -Delimiter "`t" -Header key,value -Path $Path) {
        if ($null -ne $row.key -and $row.key -ne "key") {
            $map[[string]$row.key] = [string]$row.value
        }
    }
    return $map
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

function Get-DecisionStats24h {
    param(
        [string]$Path,
        [long]$CutoffTs
    )

    $stats = [ordered]@{
        decyzje_24h = 0
        ready_24h = 0
        pominiete_24h = 0
        blokady_24h = 0
        ostatni_powod = ""
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $stats }

    $rows = Import-Csv -Delimiter "`t" -Path $Path
    foreach ($row in $rows) {
        $ts = To-LongOrZero $row.ts
        if ($ts -lt $CutoffTs) { continue }
        $stats.decyzje_24h++
        $verdict = [string]$row.verdict
        if ($verdict -eq "READY") { $stats.ready_24h++ }
        elseif ($verdict -eq "SKIP") { $stats.pominiete_24h++ }
        else { $stats.blokady_24h++ }
        $stats.ostatni_powod = [string]$row.reason
    }

    return $stats
}

function New-FamilyAggregate {
    param(
        [string]$Family,
        [object[]]$Rows
    )

    return [pscustomobject]@{
        rodzina = $Family
        liczba_par = $Rows.Count
        wynik_sumaryczny_kwota = [math]::Round((($Rows | Measure-Object -Property wynik_24h_kwota -Sum).Sum), 2)
        srednia_latencja_ms = if ($Rows.Count -gt 0) { [math]::Round((($Rows | Measure-Object -Property srednia_latencja_ms -Average).Average), 4) } else { 0.0 }
        maksymalna_latencja_ms = if ($Rows.Count -gt 0) { [math]::Round((($Rows | Measure-Object -Property maksymalna_latencja_ms -Maximum).Maximum), 4) } else { 0.0 }
        sredni_execution_pressure = if ($Rows.Count -gt 0) { [math]::Round((($Rows | Measure-Object -Property execution_pressure -Average).Average), 4) } else { 0.0 }
        sredni_learning_confidence = if ($Rows.Count -gt 0) { [math]::Round((($Rows | Measure-Object -Property learning_confidence -Average).Average), 4) } else { 0.0 }
        ready_24h = (($Rows | Measure-Object -Property ready_24h -Sum).Sum)
        decyzje_24h = (($Rows | Measure-Object -Property decyzje_24h -Sum).Sum)
        dominujacy_powod = (($Rows | Group-Object -Property ostatni_powod | Sort-Object Count -Descending | Select-Object -First 1).Name)
    }
}

$registry = Get-Content (Join-Path $ProjectRoot "CONFIG\microbots_registry.json") -Raw | ConvertFrom-Json
$reportTs = $NowLocal.ToString("yyyyMMdd_HHmmss")
$reportDate = $NowLocal.ToString("yyyy-MM-dd")
$reportTime = $NowLocal.ToString("HH:mm:ss")
$dailyDir = Join-Path $ProjectRoot "EVIDENCE\DAILY"
New-Item -ItemType Directory -Force -Path $dailyDir | Out-Null

$cutoff = [DateTimeOffset]$NowLocal.AddHours(-24)
$cutoffTs = [long]$cutoff.ToUnixTimeSeconds()

$perSymbol = @()
foreach ($item in $registry.symbols) {
    $symbol = [string]$item.symbol
    $family = [string]$item.session_profile

    $stateMap = Read-KeyValueCsv (Join-Path $CommonFilesRoot ("state\{0}\runtime_state.csv" -f $symbol))
    $summaryPath = Join-Path $CommonFilesRoot ("state\{0}\execution_summary.json" -f $symbol)
    $policyPath = Join-Path $CommonFilesRoot ("state\{0}\informational_policy.json" -f $symbol)
    $decisionPath = Join-Path $CommonFilesRoot ("logs\{0}\decision_events.csv" -f $symbol)

    $summary = if (Test-Path -LiteralPath $summaryPath) { Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json } else { $null }
    $policy = if (Test-Path -LiteralPath $policyPath) { Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json } else { $null }
    $decisionStats = Get-DecisionStats24h -Path $decisionPath -CutoffTs $cutoffTs

    $realizedDay = To-DoubleOrZero $stateMap["realized_pnl_day"]
    $equityAnchorDay = To-DoubleOrZero $stateMap["equity_anchor_day"]
    $wynikPct = if ($equityAnchorDay -gt 0) { [math]::Round(($realizedDay / $equityAnchorDay) * 100.0, 3) } else { 0.0 }
    $latencyAvgMs = if ($summary) { [math]::Round(([double]$summary.local_latency_us_avg / 1000.0), 4) } else { 0.0 }
    $latencyMaxMs = if ($summary) { [math]::Round(([double]$summary.local_latency_us_max / 1000.0), 4) } else { 0.0 }
    $runtimeMode = if ($summary) { [string]$summary.runtime_mode } elseif ($policy) { [string]$policy.runtime_mode } else { "BRAK_DANYCH" }
    $executionPressure = if ($summary) { [double]$summary.execution_pressure } else { 0.0 }
    $learningConfidence = if ($policy -and ($policy.PSObject.Properties.Name -contains "learning_confidence")) { [double]$policy.learning_confidence } else { 0.0 }
    $spreadPoints = if ($summary) { [double]$summary.spread_points } else { 0.0 }
    $statusWyniku = if ($realizedDay -gt 0) { "zysk" } elseif ($realizedDay -lt 0) { "strata" } else { "bez zmian" }

    $perSymbol += [pscustomobject]@{
        para_walutowa = $symbol
        rodzina = $family
        status_wyniku_24h = $statusWyniku
        wynik_24h_kwota = [math]::Round($realizedDay, 2)
        wynik_24h_proc_kapitalu_start = $wynikPct
        kapital_start_dnia = [math]::Round($equityAnchorDay, 2)
        tryb_runtime = $runtimeMode
        srednia_latencja_ms = $latencyAvgMs
        maksymalna_latencja_ms = $latencyMaxMs
        execution_pressure = [math]::Round($executionPressure, 4)
        learning_confidence = [math]::Round($learningConfidence, 4)
        spread_punkty = [math]::Round($spreadPoints, 2)
        decyzje_24h = $decisionStats.decyzje_24h
        ready_24h = $decisionStats.ready_24h
        pominiete_24h = $decisionStats.pominiete_24h
        blokady_24h = $decisionStats.blokady_24h
        ostatni_powod = $decisionStats.ostatni_powod
    }
}

$familyRows = @(
    New-FamilyAggregate -Family "FX_MAIN" -Rows @($perSymbol | Where-Object { $_.rodzina -eq "FX_MAIN" })
    New-FamilyAggregate -Family "FX_ASIA" -Rows @($perSymbol | Where-Object { $_.rodzina -eq "FX_ASIA" })
    New-FamilyAggregate -Family "FX_CROSS" -Rows @($perSymbol | Where-Object { $_.rodzina -eq "FX_CROSS" })
    New-FamilyAggregate -Family "METALS_SPOT_PM" -Rows @($perSymbol | Where-Object { $_.rodzina -eq "METALS_SPOT_PM" })
    New-FamilyAggregate -Family "METALS_FUTURES" -Rows @($perSymbol | Where-Object { $_.rodzina -eq "METALS_FUTURES" })
    New-FamilyAggregate -Family "INDEX_EU" -Rows @($perSymbol | Where-Object { $_.rodzina -eq "INDEX_EU" })
    New-FamilyAggregate -Family "INDEX_US" -Rows @($perSymbol | Where-Object { $_.rodzina -eq "INDEX_US" })
)
$runtimeControlSummaryPath = Join-Path $ProjectRoot "EVIDENCE\runtime_control_summary.json"
if (Test-Path -LiteralPath $runtimeControlSummaryPath) {
    $runtimeControlSummary = Get-Content -Raw -LiteralPath $runtimeControlSummaryPath | ConvertFrom-Json
    $controlRows = @($runtimeControlSummary.kontrola)
} else {
    $controlRows = @()
}

$zyski = @($perSymbol | Where-Object { $_.wynik_24h_kwota -gt 0 })
$straty = @($perSymbol | Where-Object { $_.wynik_24h_kwota -lt 0 })
$bezZmian = @($perSymbol | Where-Object { $_.wynik_24h_kwota -eq 0 })
$topReady = @($perSymbol | Sort-Object ready_24h -Descending | Select-Object -First 3)
$topLatency = @($perSymbol | Sort-Object srednia_latencja_ms | Select-Object -First 3)
$hotRisks = @($perSymbol | Sort-Object execution_pressure -Descending | Select-Object -First 3)

$summary = [ordered]@{
    data_raportu = $reportDate
    godzina_raportu = $reportTime
    liczba_par = $perSymbol.Count
    liczba_par_zysk = $zyski.Count
    liczba_par_strata = $straty.Count
    liczba_par_bez_zmian = $bezZmian.Count
    wynik_sumaryczny_kwota = [math]::Round((($perSymbol | Measure-Object -Property wynik_24h_kwota -Sum).Sum), 2)
    srednia_latencja_dobowa_ms = if ($perSymbol.Count -gt 0) { [math]::Round((($perSymbol | Measure-Object -Property srednia_latencja_ms -Average).Average), 4) } else { 0.0 }
    maksymalna_latencja_dobowa_ms = if ($perSymbol.Count -gt 0) { [math]::Round((($perSymbol | Measure-Object -Property maksymalna_latencja_ms -Maximum).Maximum), 4) } else { 0.0 }
    sredni_execution_pressure = if ($perSymbol.Count -gt 0) { [math]::Round((($perSymbol | Measure-Object -Property execution_pressure -Average).Average), 4) } else { 0.0 }
    sredni_learning_confidence = if ($perSymbol.Count -gt 0) { [math]::Round((($perSymbol | Measure-Object -Property learning_confidence -Average).Average), 4) } else { 0.0 }
}

$report = [ordered]@{
    schema_version = "2.0"
    wygenerowano_utc = (Get-Date).ToUniversalTime().ToString("o")
    raport_dzienny = $summary
    rodziny = $familyRows
    liderzy = [ordered]@{
        najwiecej_ready = $topReady
        najnizsza_latencja = $topLatency
        najwyzszy_execution_pressure = $hotRisks
    }
    pary = $perSymbol
}

$jsonPath = Join-Path $dailyDir ("raport_dzienny_{0}.json" -f $reportTs)
$txtPath = Join-Path $dailyDir ("raport_dzienny_{0}.txt" -f $reportTs)
$htmlPath = Join-Path $dailyDir ("dashboard_dzienny_{0}.html" -f $reportTs)
$latestJson = Join-Path $dailyDir "raport_dzienny_latest.json"
$latestTxt = Join-Path $dailyDir "raport_dzienny_latest.txt"
$latestHtml = Join-Path $dailyDir "dashboard_dzienny_latest.html"

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJson -Encoding UTF8

$lines = @()
$lines += "RAPORT DZIENNY MAKRO I MIKRO BOT"
$lines += "Data: $reportDate"
$lines += "Godzina: $reportTime"
$lines += ""
$lines += "PODSUMOWANIE"
$lines += ("Liczba par: {0}" -f $summary.liczba_par)
$lines += ("Pary z zyskiem: {0}" -f $summary.liczba_par_zysk)
$lines += ("Pary ze strata: {0}" -f $summary.liczba_par_strata)
$lines += ("Pary bez zmian: {0}" -f $summary.liczba_par_bez_zmian)
$lines += ("Wynik sumaryczny 24h: {0}" -f (Format-PL -Value $summary.wynik_sumaryczny_kwota))
$lines += ("Srednia latencja dobowa [ms]: {0}" -f (Format-PL -Value $summary.srednia_latencja_dobowa_ms -Decimals 4))
$lines += ("Maksymalna latencja dobowa [ms]: {0}" -f (Format-PL -Value $summary.maksymalna_latencja_dobowa_ms -Decimals 4))
$lines += ("Sredni execution pressure: {0}" -f (Format-PL -Value $summary.sredni_execution_pressure -Decimals 4))
$lines += ("Sredni learning confidence: {0}" -f (Format-PL -Value $summary.sredni_learning_confidence -Decimals 4))
$lines += ""
$lines += "RODZINY"
foreach ($family in $familyRows) {
    $lines += ("- {0} | pary={1} | wynik={2} | srednia_latencja={3} ms | ready24h={4} | dominujacy_powod={5}" -f
        $family.rodzina,
        $family.liczba_par,
        (Format-PL -Value $family.wynik_sumaryczny_kwota),
        (Format-PL -Value $family.srednia_latencja_ms -Decimals 4),
        $family.ready_24h,
        $family.dominujacy_powod)
}
$lines += ""
$lines += "PARY WALUTOWE"
foreach ($row in ($perSymbol | Sort-Object para_walutowa)) {
    $lines += ("- {0} | rodzina={1} | wynik={2} ({3}% kapitalu startowego dnia) | tryb={4} | srednia_latencja={5} ms | decyzje24h={6} | ready24h={7} | ostatni_powod={8}" -f
        $row.para_walutowa,
        $row.rodzina,
        (Format-PL -Value $row.wynik_24h_kwota),
        (Format-PL -Value $row.wynik_24h_proc_kapitalu_start -Decimals 3),
        $row.tryb_runtime,
        (Format-PL -Value $row.srednia_latencja_ms -Decimals 4),
        $row.decyzje_24h,
        $row.ready_24h,
        $row.ostatni_powod)
}
$lines | Set-Content -LiteralPath $txtPath -Encoding UTF8
$lines | Set-Content -LiteralPath $latestTxt -Encoding UTF8

$tableRows = ($perSymbol | Sort-Object para_walutowa | ForEach-Object {
    $cls = if ($_.wynik_24h_kwota -gt 0) { "profit" } elseif ($_.wynik_24h_kwota -lt 0) { "loss" } else { "flat" }
    "<tr class='$cls'><td>$($_.para_walutowa)</td><td>$($_.rodzina)</td><td>$($_.status_wyniku_24h)</td><td>$(Format-PL -Value $_.wynik_24h_kwota)</td><td>$(Format-PL -Value $_.wynik_24h_proc_kapitalu_start -Decimals 3)%</td><td>$($_.tryb_runtime)</td><td>$(Format-PL -Value $_.srednia_latencja_ms -Decimals 4)</td><td>$(Format-PL -Value $_.maksymalna_latencja_ms -Decimals 4)</td><td>$($_.decyzje_24h)</td><td>$($_.ready_24h)</td><td>$($_.ostatni_powod)</td></tr>"
}) -join "`n"

$familyCards = ($familyRows | ForEach-Object {
    "<div class='family-card'><h3>$($_.rodzina)</h3><div class='family-grid'><div><span>Wynik</span><b>$(Format-PL -Value $_.wynik_sumaryczny_kwota)</b></div><div><span>Srednia latencja</span><b>$(Format-PL -Value $_.srednia_latencja_ms -Decimals 4) ms</b></div><div><span>READY 24h</span><b>$($_.ready_24h)</b></div><div><span>Dominujacy powod</span><b>$($_.dominujacy_powod)</b></div></div></div>"
}) -join "`n"

$topReadyRows = ($topReady | ForEach-Object {
    "<li><b>$($_.para_walutowa)</b> - READY 24h: $($_.ready_24h), decyzje: $($_.decyzje_24h)</li>"
}) -join "`n"

$topLatencyRows = ($topLatency | ForEach-Object {
    "<li><b>$($_.para_walutowa)</b> - srednia latencja: $(Format-PL -Value $_.srednia_latencja_ms -Decimals 4) ms</li>"
}) -join "`n"

$riskRows = ($hotRisks | ForEach-Object {
    "<li><b>$($_.para_walutowa)</b> - execution pressure: $(Format-PL -Value $_.execution_pressure -Decimals 4), ostatni powod: $($_.ostatni_powod)</li>"
}) -join "`n"

$controlRowsHtml = ($controlRows | Sort-Object para_walutowa | ForEach-Object {
    "<tr><td>$($_.para_walutowa)</td><td>$($_.rodzina)</td><td>$($_.requested_mode)</td><td>$($_.reason_code)</td></tr>"
}) -join "`n"

$projectRootUri = $ProjectRoot -replace '\\','/'
$rolloutLink = "file:///$projectRootUri/RUN/PREPARE_MT5_ROLLOUT.ps1"
$dailyNowLink = "file:///$projectRootUri/RUN/GENERATE_DAILY_REPORTS_NOW.ps1"
$eveningNowLink = "file:///$projectRootUri/RUN/GENERATE_EVENING_REPORT_NOW.ps1"
$chartPlanLink = "file:///$projectRootUri/DOCS/06_MT5_CHART_ATTACHMENT_PLAN.txt"
$panelLink = "file:///$projectRootUri/RUN/PANEL_OPERATORA_PL.ps1"
$normalLink = "file:///$projectRootUri/RUN/WLACZ_TRYB_NORMALNY_SYSTEMU.ps1"
$closeOnlyLink = "file:///$projectRootUri/RUN/WLACZ_CLOSE_ONLY_SYSTEMU.ps1"
$haltLink = "file:///$projectRootUri/RUN/ZATRZYMAJ_SYSTEM.ps1"

$html = @"
<!doctype html>
<html lang="pl">
<head>
  <meta charset="utf-8">
  <title>Dashboard operatorski Makro i Mikro Bot</title>
  <style>
    :root { --bg:#efe7db; --panel:#fffaf3; --ink:#201a16; --muted:#6d6155; --line:#dccfbe; --profit:#236a3b; --loss:#a3322f; --flat:#7e6f5d; --accent:#153f6b; --warn:#c77f12; }
    * { box-sizing:border-box; }
    body { margin:0; font-family:"Segoe UI",Tahoma,sans-serif; background:radial-gradient(circle at top,#f6f2ea,#e9dfd1 70%); color:var(--ink); }
    .wrap { max-width:1600px; margin:0 auto; padding:28px; }
    .hero { display:grid; grid-template-columns: 2.2fr 1fr; gap:20px; margin-bottom:20px; }
    .panel { background:var(--panel); border:1px solid var(--line); border-radius:20px; box-shadow:0 12px 36px rgba(32,26,22,.08); padding:22px; }
    .title { font-size:34px; margin:0 0 8px 0; }
    .meta { color:var(--muted); font-size:14px; }
    .subtitle { margin-top:10px; color:var(--muted); line-height:1.5; }
    .stats { display:grid; grid-template-columns:repeat(3,1fr); gap:12px; }
    .stat { background:#f8f1e6; border:1px solid var(--line); border-radius:14px; padding:14px; }
    .stat span { display:block; font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.06em; }
    .stat b { display:block; font-size:24px; margin-top:6px; }
    .section-grid { display:grid; grid-template-columns:repeat(3,1fr); gap:20px; margin-bottom:20px; }
    .family-card { background:#faf5ec; border:1px solid var(--line); border-radius:16px; padding:16px; }
    .family-card h3 { margin:0 0 10px 0; }
    .family-grid { display:grid; grid-template-columns:repeat(2,1fr); gap:10px; }
    .family-grid span { color:var(--muted); font-size:12px; display:block; }
    .family-grid b { font-size:18px; }
    .lists { display:grid; grid-template-columns:repeat(3,1fr); gap:20px; margin-bottom:20px; }
    .lists ul { margin:0; padding-left:18px; }
    .lists li { margin:6px 0; line-height:1.45; }
    .actions { display:grid; grid-template-columns:repeat(4,1fr); gap:12px; margin-bottom:20px; }
    .action { display:block; text-decoration:none; color:var(--ink); background:#f8f1e6; border:1px solid var(--line); border-radius:14px; padding:14px; }
    .action strong { display:block; margin-bottom:4px; color:var(--accent); }
    table { width:100%; border-collapse:collapse; font-size:14px; }
    th,td { padding:10px 8px; border-bottom:1px solid var(--line); text-align:left; vertical-align:top; }
    th { color:var(--muted); font-weight:600; }
    tr.profit td:nth-child(4), tr.profit td:nth-child(5) { color:var(--profit); font-weight:700; }
    tr.loss td:nth-child(4), tr.loss td:nth-child(5) { color:var(--loss); font-weight:700; }
    tr.flat td:nth-child(4), tr.flat td:nth-child(5) { color:var(--flat); font-weight:700; }
    .foot { margin-top:18px; color:var(--muted); font-size:13px; line-height:1.5; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div class="panel">
        <h1 class="title">Dashboard operatorski Makro i Mikro Bot</h1>
        <div class="meta">Data raportu: $reportDate | Godzina: $reportTime</div>
        <div class="subtitle">Widok dla operatora: wynik 24h, aktywnosc par, latencja, pressure wykonania, gotowosc do decyzji oraz ostatnie powody blokad. To jest ekran do codziennej kontroli pracy systemu.</div>
      </div>
      <div class="panel">
        <h2>Podsumowanie dnia</h2>
        <div class="stats">
          <div class="stat"><span>Wynik 24h</span><b>$(Format-PL -Value $summary.wynik_sumaryczny_kwota)</b></div>
          <div class="stat"><span>Srednia latencja</span><b>$(Format-PL -Value $summary.srednia_latencja_dobowa_ms -Decimals 4) ms</b></div>
          <div class="stat"><span>Maks. latencja</span><b>$(Format-PL -Value $summary.maksymalna_latencja_dobowa_ms -Decimals 4) ms</b></div>
          <div class="stat"><span>Pary z zyskiem</span><b>$($summary.liczba_par_zysk)</b></div>
          <div class="stat"><span>Pary ze strata</span><b>$($summary.liczba_par_strata)</b></div>
          <div class="stat"><span>Sredni learning confidence</span><b>$(Format-PL -Value $summary.sredni_learning_confidence -Decimals 4)</b></div>
        </div>
      </div>
    </div>

    <div class="panel" style="margin-bottom:20px;">
      <h2>Rodziny instrumentow</h2>
      <div class="section-grid">
        $familyCards
      </div>
    </div>

    <div class="panel" style="margin-bottom:20px;">
      <h2>Akcje operatora</h2>
      <div class="actions">
        <a class="action" href="$rolloutLink"><strong>Preflight i rollout</strong>Uruchom kompletna walidacje i paczke operatorska.</a>
        <a class="action" href="$dailyNowLink"><strong>Raport dzienny teraz</strong>Wygeneruj raport dzienny i odswiez dashboard.</a>
        <a class="action" href="$eveningNowLink"><strong>Raport wieczorny teraz</strong>Wygeneruj prostszy raport biznesowy dla wlasciciela.</a>
        <a class="action" href="$panelLink"><strong>Otworz panel operatora</strong>Uruchom natywne okno sterowania Windows.</a>
        <a class="action" href="$chartPlanLink"><strong>Plan wykresow</strong>Sprawdz przypiecie botow do wykresow i par.</a>
        <a class="action" href="$normalLink"><strong>Wlacz tryb normalny</strong>Ustaw READY dla calego systemu.</a>
        <a class="action" href="$closeOnlyLink"><strong>Wlacz close-only</strong>Zablokuj nowe wejscia, zostaw wyjscia.</a>
        <a class="action" href="$haltLink"><strong>Zatrzymaj system</strong>Ustaw HALT dla wszystkich par.</a>
      </div>
    </div>

    <div class="lists">
      <div class="panel">
        <h2>Najwiecej READY</h2>
        <ul>$topReadyRows</ul>
      </div>
      <div class="panel">
        <h2>Najnizsza latencja</h2>
        <ul>$topLatencyRows</ul>
      </div>
      <div class="panel">
        <h2>Najwyzszy execution pressure</h2>
        <ul>$riskRows</ul>
      </div>
    </div>

    <div class="panel">
      <h2>Wyniki per para</h2>
      <table>
        <thead>
          <tr>
            <th>Para</th><th>Rodzina</th><th>Status</th><th>Wynik 24h</th><th>% kapitalu startowego dnia</th><th>Tryb</th><th>Srednia latencja ms</th><th>Maks. latencja ms</th><th>Decyzje 24h</th><th>READY 24h</th><th>Ostatni powod</th>
          </tr>
        </thead>
        <tbody>
          $tableRows
        </tbody>
      </table>
      <div class="foot">Raport oparty na stanie runtime, telemetryce wykonania, dziennikach decyzji i lekkiej polityce uczenia. Dane sa przeznaczone do oceny strojenia paper-mode oraz gotowosci do dalszego rozwoju rodzin instrumentow.</div>
    </div>

    <div class="panel" style="margin-top:20px;">
      <h2>Biezace sterowanie operatorskie</h2>
      <table>
        <thead>
          <tr>
            <th>Para</th><th>Rodzina</th><th>Zadany tryb</th><th>Powod</th>
          </tr>
        </thead>
        <tbody>
          $controlRowsHtml
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>
"@

$html | Set-Content -LiteralPath $htmlPath -Encoding UTF8
$html | Set-Content -LiteralPath $latestHtml -Encoding UTF8

$result = [ordered]@{
    schema_version = "2.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    common_files_root = $CommonFilesRoot
    daily_dir = $dailyDir
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
