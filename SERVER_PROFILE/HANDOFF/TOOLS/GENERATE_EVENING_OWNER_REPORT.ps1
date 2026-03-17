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
$reportTs = $NowLocal.ToString("yyyyMMdd_HHmmss")
$dateLabel = $NowLocal.ToString("yyyy-MM-dd")
$timeLabel = $NowLocal.ToString("HH:mm:ss")

$pairs = @($daily.pary)
$bestPairs = @($pairs | Sort-Object wynik_24h_kwota -Descending | Select-Object -First 3)
$worstPairs = @($pairs | Sort-Object wynik_24h_kwota | Select-Object -First 3)
$attentionPairs = @($pairs | Sort-Object execution_pressure -Descending | Select-Object -First 3)

$summary = [ordered]@{
    data_raportu = $dateLabel
    godzina_raportu = $timeLabel
    wynik_sumaryczny_24h = [math]::Round([double]$daily.raport_dzienny.wynik_sumaryczny_kwota, 2)
    srednia_latencja_ms = [math]::Round([double]$daily.raport_dzienny.srednia_latencja_dobowa_ms, 4)
    maksymalna_latencja_ms = [math]::Round([double]$daily.raport_dzienny.maksymalna_latencja_dobowa_ms, 4)
    liczba_par_zysk = [int]$daily.raport_dzienny.liczba_par_zysk
    liczba_par_strata = [int]$daily.raport_dzienny.liczba_par_strata
    liczba_par_bez_zmian = [int]$daily.raport_dzienny.liczba_par_bez_zmian
    rekomendacja = if ([double]$daily.raport_dzienny.sredni_execution_pressure -gt 0.45) { "Jutro zaczac od kontroli execution pressure i spreadow." }
                   elseif ([double]$daily.raport_dzienny.sredni_learning_confidence -lt 0.30) { "Jutro kontynuowac paper-mode i zbieranie danych do uczenia." }
                   else { "Jutro mozna stroic rodziny par bez zmiany poziomu ryzyka live." }
}

$report = [ordered]@{
    schema_version = "1.0"
    wygenerowano_utc = (Get-Date).ToUniversalTime().ToString("o")
    raport_wieczorny = $summary
    najlepsze_pary = $bestPairs
    najslabsze_pary = $worstPairs
    pary_do_uwagi = $attentionPairs
}

$jsonPath = Join-Path $dailyDir ("raport_wieczorny_{0}.json" -f $reportTs)
$txtPath = Join-Path $dailyDir ("raport_wieczorny_{0}.txt" -f $reportTs)
$htmlPath = Join-Path $dailyDir ("dashboard_wieczorny_{0}.html" -f $reportTs)
$latestJson = Join-Path $dailyDir "raport_wieczorny_latest.json"
$latestTxt = Join-Path $dailyDir "raport_wieczorny_latest.txt"
$latestHtml = Join-Path $dailyDir "dashboard_wieczorny_latest.html"

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJson -Encoding UTF8

$lines = @()
$lines += "RAPORT WIECZORNY WLASCICIELA SYSTEMU"
$lines += "Data: $dateLabel"
$lines += "Godzina: $timeLabel"
$lines += ""
$lines += "OBRAZ DNIA"
$lines += ("Wynik sumaryczny 24h: {0}" -f (Format-PL -Value $summary.wynik_sumaryczny_24h))
$lines += ("Srednia latencja: {0} ms" -f (Format-PL -Value $summary.srednia_latencja_ms -Decimals 4))
$lines += ("Maksymalna latencja: {0} ms" -f (Format-PL -Value $summary.maksymalna_latencja_ms -Decimals 4))
$lines += ("Pary z zyskiem: {0}" -f $summary.liczba_par_zysk)
$lines += ("Pary ze strata: {0}" -f $summary.liczba_par_strata)
$lines += ("Pary bez zmian: {0}" -f $summary.liczba_par_bez_zmian)
$lines += ""
$lines += "NAJLEPSZE PARY"
foreach ($pair in $bestPairs) {
    $lines += ("- {0} | wynik={1} | READY={2} | srednia latencja={3} ms" -f
        $pair.para_walutowa,
        (Format-PL -Value $pair.wynik_24h_kwota),
        $pair.ready_24h,
        (Format-PL -Value $pair.srednia_latencja_ms -Decimals 4))
}
$lines += ""
$lines += "PARY DO KONTROLI"
foreach ($pair in $attentionPairs) {
    $lines += ("- {0} | execution pressure={1} | ostatni powod={2}" -f
        $pair.para_walutowa,
        (Format-PL -Value $pair.execution_pressure -Decimals 4),
        $pair.ostatni_powod)
}
$lines += ""
$lines += "REKOMENDACJA NA KOLEJNY CYKL"
$lines += $summary.rekomendacja
$lines | Set-Content -LiteralPath $txtPath -Encoding UTF8
$lines | Set-Content -LiteralPath $latestTxt -Encoding UTF8

$bestRows = ($bestPairs | ForEach-Object {
    "<li><b>$($_.para_walutowa)</b> - wynik $(Format-PL -Value $_.wynik_24h_kwota), READY $($_.ready_24h), latencja $(Format-PL -Value $_.srednia_latencja_ms -Decimals 4) ms</li>"
}) -join "`n"
$worstRows = ($worstPairs | ForEach-Object {
    "<li><b>$($_.para_walutowa)</b> - wynik $(Format-PL -Value $_.wynik_24h_kwota), ostatni powod $($_.ostatni_powod)</li>"
}) -join "`n"
$attentionRows = ($attentionPairs | ForEach-Object {
    "<li><b>$($_.para_walutowa)</b> - execution pressure $(Format-PL -Value $_.execution_pressure -Decimals 4), tryb $($_.tryb_runtime)</li>"
}) -join "`n"

$html = @"
<!doctype html>
<html lang="pl">
<head>
  <meta charset="utf-8">
  <title>Raport wieczorny Makro i Mikro Bot</title>
  <style>
    :root { --bg:#f4efe7; --panel:#fffaf3; --ink:#1d1916; --muted:#6c635b; --line:#ded2c3; --accent:#163b61; }
    body { margin:0; font-family:"Segoe UI",Tahoma,sans-serif; background:linear-gradient(180deg,#f8f4ee,#ece2d5); color:var(--ink); }
    .wrap { max-width:1200px; margin:0 auto; padding:28px; }
    .panel { background:var(--panel); border:1px solid var(--line); border-radius:20px; padding:22px; box-shadow:0 12px 32px rgba(29,25,22,.08); margin-bottom:18px; }
    h1,h2 { margin:0 0 10px 0; }
    .meta { color:var(--muted); font-size:14px; margin-bottom:8px; }
    .stats { display:grid; grid-template-columns:repeat(3,1fr); gap:12px; }
    .stat { background:#f8f1e6; border:1px solid var(--line); border-radius:14px; padding:14px; }
    .stat span { display:block; color:var(--muted); font-size:12px; text-transform:uppercase; }
    .stat b { display:block; margin-top:6px; font-size:22px; }
    .cols { display:grid; grid-template-columns:repeat(3,1fr); gap:18px; }
    ul { margin:0; padding-left:18px; }
    li { margin:6px 0; line-height:1.45; }
    .rec { font-size:18px; color:var(--accent); }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="panel">
      <h1>Raport wieczorny wlasciciela systemu</h1>
      <div class="meta">Data: $dateLabel | Godzina: $timeLabel</div>
      <p>To jest prostszy raport biznesowy: wynik dnia, stan par, najwazniejsze miejsca do uwagi i rekomendacja na kolejny cykl strojenia.</p>
    </div>
    <div class="panel">
      <h2>Obraz dnia</h2>
      <div class="stats">
        <div class="stat"><span>Wynik 24h</span><b>$(Format-PL -Value $summary.wynik_sumaryczny_24h)</b></div>
        <div class="stat"><span>Srednia latencja</span><b>$(Format-PL -Value $summary.srednia_latencja_ms -Decimals 4) ms</b></div>
        <div class="stat"><span>Maks. latencja</span><b>$(Format-PL -Value $summary.maksymalna_latencja_ms -Decimals 4) ms</b></div>
        <div class="stat"><span>Pary z zyskiem</span><b>$($summary.liczba_par_zysk)</b></div>
        <div class="stat"><span>Pary ze strata</span><b>$($summary.liczba_par_strata)</b></div>
        <div class="stat"><span>Pary bez zmian</span><b>$($summary.liczba_par_bez_zmian)</b></div>
      </div>
    </div>
    <div class="cols">
      <div class="panel">
        <h2>Najlepsze pary</h2>
        <ul>$bestRows</ul>
      </div>
      <div class="panel">
        <h2>Najsłabsze pary</h2>
        <ul>$worstRows</ul>
      </div>
      <div class="panel">
        <h2>Pary do uwagi</h2>
        <ul>$attentionRows</ul>
      </div>
    </div>
    <div class="panel">
      <h2>Rekomendacja</h2>
      <div class="rec">$($summary.rekomendacja)</div>
    </div>
  </div>
</body>
</html>
"@

$html | Set-Content -LiteralPath $htmlPath -Encoding UTF8
$html | Set-Content -LiteralPath $latestHtml -Encoding UTF8

$result = [ordered]@{
    schema_version = "1.0"
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
