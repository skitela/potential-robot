param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [datetime]$NowLocal = (Get-Date)
)

$ErrorActionPreference = "Stop"

function Format-PL {
    param(
        [double]$Value,
        [int]$Decimals = 2
    )
    return $Value.ToString(("N{0}" -f $Decimals), [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL"))
}

$dailyDir = Join-Path $ProjectRoot "EVIDENCE\DAILY"
$latestDaily = Join-Path $dailyDir "raport_dzienny_latest.json"
if (-not (Test-Path -LiteralPath $latestDaily)) {
    throw "Brak raportu dziennego: $latestDaily"
}

$daily = Get-Content -Raw -LiteralPath $latestDaily | ConvertFrom-Json
$summary = $daily.raport_dzienny
$rows = @($daily.instrumenty)
$familyRows = @($daily.rodziny)
$reportTs = $NowLocal.ToString("yyyyMMdd_HHmmss")

$best = @($rows | Sort-Object netto_dzis -Descending | Select-Object -First 3)
$worst = @($rows | Sort-Object netto_dzis | Select-Object -First 3)
$stale = @($rows | Sort-Object swiezosc_s -Descending | Select-Object -First 5)
$activeFamilies = @($familyRows | Sort-Object netto_dzis -Descending | Select-Object -First 3)

$report = [ordered]@{
    schema_version = "2.0"
    wygenerowano_utc = (Get-Date).ToUniversalTime().ToString("o")
    raport_wieczorny = [ordered]@{
        data_raportu = $NowLocal.ToString("yyyy-MM-dd")
        godzina_raportu = $NowLocal.ToString("HH:mm:ss")
        stan_systemu = $summary.stan_systemu
        netto_dzis = [double]$summary.netto_dzis
        netto_wczoraj = [double]$summary.netto_wczoraj
        zmiana_do_wczoraj = [double]$summary.zmiana_netto_do_wczoraj
        wygrane_dzis = [int]$summary.wygrane_dzis
        przegrane_dzis = [int]$summary.przegrane_dzis
        otwarcia_dzis = [int]$summary.otwarcia_dzis
        czas_pracy_dzis = [string]$summary.laczny_czas_pracy_dzis_label
        sredni_ping_ms = [double]$summary.sredni_ping_ms
        srednia_latencja_bota_us = [double]$summary.srednia_latencja_bota_us
    }
    najlepsze = $best
    najslabsze = $worst
    najmniej_swieze = $stale
    najmocniejsze_rodziny = $activeFamilies
}

$jsonPath = Join-Path $dailyDir ("raport_wieczorny_{0}.json" -f $reportTs)
$txtPath = Join-Path $dailyDir ("raport_wieczorny_{0}.txt" -f $reportTs)
$htmlPath = Join-Path $dailyDir ("dashboard_wieczorny_{0}.html" -f $reportTs)
$latestJson = Join-Path $dailyDir "raport_wieczorny_latest.json"
$latestTxt = Join-Path $dailyDir "raport_wieczorny_latest.txt"
$latestHtml = Join-Path $dailyDir "dashboard_wieczorny_latest.html"

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJson -Encoding UTF8

$txt = @()
$txt += "RAPORT WIECZORNY"
$txt += "Data: $($report.raport_wieczorny.data_raportu)  Godzina: $($report.raport_wieczorny.godzina_raportu)"
$txt += ""
$txt += ("Stan systemu: {0}" -f $report.raport_wieczorny.stan_systemu)
$txt += ("Netto dzis: {0}" -f (Format-PL -Value $report.raport_wieczorny.netto_dzis))
$txt += ("Netto wczoraj: {0}" -f (Format-PL -Value $report.raport_wieczorny.netto_wczoraj))
$txt += ("Zmiana do wczoraj: {0}" -f (Format-PL -Value $report.raport_wieczorny.zmiana_do_wczoraj))
$txt += ("Wygrane / przegrane: {0} / {1}" -f $report.raport_wieczorny.wygrane_dzis, $report.raport_wieczorny.przegrane_dzis)
$txt += ("Otwarcia dzis: {0}" -f $report.raport_wieczorny.otwarcia_dzis)
$txt += ("Czas pracy dzis: {0}" -f $report.raport_wieczorny.czas_pracy_dzis)
$txt += ("Sredni ping: {0} ms | Srednia latencja bota: {1} us" -f
    (Format-PL -Value $report.raport_wieczorny.sredni_ping_ms -Decimals 2),
    (Format-PL -Value $report.raport_wieczorny.srednia_latencja_bota_us -Decimals 2))
$txt += ""
$txt += "Najlepsze instrumenty"
foreach ($row in $best) {
    $txt += ("- {0}: netto {1}, W/P {2}/{3}, otwarcia {4}" -f $row.instrument, (Format-PL -Value $row.netto_dzis), $row.wygrane_dzis, $row.przegrane_dzis, $row.otwarcia_dzis)
}
$txt += ""
$txt += "Najslabsze instrumenty"
foreach ($row in $worst) {
    $txt += ("- {0}: netto {1}, trust {2}, cost {3}" -f $row.instrument, (Format-PL -Value $row.netto_dzis), $row.trust_state, $row.cost_pressure)
}
$txt += ""
$txt += "Najmniej swieze instrumenty"
foreach ($row in $stale) {
    $txt += ("- {0}: status {1}, swiezosc {2}, ostatni heartbeat {3}" -f $row.instrument, $row.status_pracy, $row.swiezosc_label, $row.ostatni_heartbeat)
}
$txt | Set-Content -LiteralPath $txtPath -Encoding UTF8
$txt | Set-Content -LiteralPath $latestTxt -Encoding UTF8

$bestHtml = ($best | ForEach-Object { "<li><b>$($_.instrument)</b> - netto $(Format-PL -Value $_.netto_dzis), W/P $($_.wygrane_dzis)/$($_.przegrane_dzis), otwarcia $($_.otwarcia_dzis)</li>" }) -join "`n"
$worstHtml = ($worst | ForEach-Object { "<li><b>$($_.instrument)</b> - netto $(Format-PL -Value $_.netto_dzis), trust $($_.trust_state), cost $($_.cost_pressure)</li>" }) -join "`n"
$staleHtml = ($stale | ForEach-Object { "<li><b>$($_.instrument)</b> - $($_.status_pracy), swiezosc $($_.swiezosc_label)</li>" }) -join "`n"
$familyHtml = ($activeFamilies | ForEach-Object { "<li><b>$($_.rodzina_label)</b> - netto $(Format-PL -Value $_.netto_dzis), zmiana $(Format-PL -Value $_.zmiana_do_wczoraj)</li>" }) -join "`n"

$html = @"
<!doctype html>
<html lang="pl">
<head>
  <meta charset="utf-8">
  <title>Raport wieczorny</title>
  <style>
    body{font-family:Segoe UI,Tahoma,sans-serif;background:#f5efe7;color:#1d1915;margin:0}
    .wrap{max-width:1280px;margin:0 auto;padding:24px}
    .panel{background:#fffaf4;border:1px solid #ddcfbf;border-radius:18px;padding:18px;margin-bottom:18px;box-shadow:0 10px 28px rgba(29,25,21,.06)}
    .cards{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
    .card{background:#f8f1e6;border:1px solid #ddcfbf;border-radius:14px;padding:12px}
    .card span{display:block;font-size:12px;color:#6b6158;text-transform:uppercase}
    .card b{display:block;font-size:22px;margin-top:6px}
    .cols{display:grid;grid-template-columns:repeat(2,1fr);gap:18px}
    ul{margin:0;padding-left:18px}
    li{margin:6px 0}
    h1,h2{margin:0 0 10px 0}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="panel">
      <h1>Raport wieczorny</h1>
      <p>To jest lzejsza, prostsza wersja dziennego dashboardu. Ma odpowiedziec szybko: czy system trzymal sie przez dzien, jaki byl wynik paper, co bylo najmocniejsze, co bylo najslabsze i czy dane sa dalej swieze.</p>
    </div>
    <div class="panel">
      <div class="cards">
        <div class="card"><span>Stan systemu</span><b>$($report.raport_wieczorny.stan_systemu)</b></div>
        <div class="card"><span>Netto dzis</span><b>$(Format-PL -Value $report.raport_wieczorny.netto_dzis)</b></div>
        <div class="card"><span>Zmiana do wczoraj</span><b>$(Format-PL -Value $report.raport_wieczorny.zmiana_do_wczoraj)</b></div>
        <div class="card"><span>Wygrane / przegrane</span><b>$($report.raport_wieczorny.wygrane_dzis) / $($report.raport_wieczorny.przegrane_dzis)</b></div>
      </div>
    </div>
    <div class="cols">
      <div class="panel"><h2>Najlepsze instrumenty</h2><ul>$bestHtml</ul></div>
      <div class="panel"><h2>Najslabsze instrumenty</h2><ul>$worstHtml</ul></div>
      <div class="panel"><h2>Najmniej swieze</h2><ul>$staleHtml</ul></div>
      <div class="panel"><h2>Najmocniejsze rodziny</h2><ul>$familyHtml</ul></div>
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
    json_report = $jsonPath
    txt_report = $txtPath
    html_dashboard = $htmlPath
    latest_json = $latestJson
    latest_txt = $latestTxt
    latest_html = $latestHtml
}

$resultPath = Join-Path $ProjectRoot "EVIDENCE\evening_reports_generation_report.json"
$resultTxtPath = Join-Path $ProjectRoot "EVIDENCE\evening_reports_generation_report.txt"
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
@(
    "EVENING REPORTS GENERATION"
    ("JSON={0}" -f $jsonPath)
    ("TXT={0}" -f $txtPath)
    ("HTML={0}" -f $htmlPath)
    ("LATEST_HTML={0}" -f $latestHtml)
) | Set-Content -LiteralPath $resultTxtPath -Encoding UTF8

$result | ConvertTo-Json -Depth 6
