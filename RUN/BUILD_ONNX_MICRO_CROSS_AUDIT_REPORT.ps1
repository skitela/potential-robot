param(
    [string]$CableStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_cable_status_latest.json",
    [string]$MicroReviewPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_micro_review_latest.json",
    [string]$FeedbackLoopPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_feedback_loop_latest.json",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonObject {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing JSON input: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SafePropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Get-FeedbackItemMap {
    param(
        [object[]]$Items
    )

    $map = @{}
    foreach ($item in @($Items)) {
        $map[[string]$item.symbol_alias] = $item
    }

    return $map
}

function Get-RuntimeBootstrapMap {
    param(
        [object[]]$Items
    )

    $map = @{}
    foreach ($item in @($Items)) {
        $map[[string]$item.symbol_alias] = $item
    }

    return $map
}

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$cableStatus = Read-JsonObject -Path $CableStatusPath
$microReview = Read-JsonObject -Path $MicroReviewPath
$feedbackLoop = Read-JsonObject -Path $FeedbackLoopPath

$reviewMap = @{}
foreach ($item in @($microReview.items)) {
    $reviewMap[[string]$item.symbol_alias] = $item
}

$feedbackMap = Get-FeedbackItemMap -Items @($feedbackLoop.items)
$runtimeBootstrapMap = Get-RuntimeBootstrapMap -Items @(Get-SafePropertyValue -Object $feedbackLoop -Name 'runtime_bootstrap' -Default @())
$feedbackSummary = Get-SafePropertyValue -Object $feedbackLoop -Name 'summary' -Default $null
$feedbackTotal = [int](Get-SafePropertyValue -Object $feedbackSummary -Name 'liczba_obserwacji_onnx' -Default 0)

$items = New-Object System.Collections.Generic.List[object]

foreach ($cableItem in @($cableStatus.items)) {
    $symbol = [string]$cableItem.symbol
    $reviewItem = $reviewMap[$symbol]
    $feedbackItem = $feedbackMap[$symbol]
    $runtimeBootstrapItem = $runtimeBootstrapMap[$symbol]

    $integracja = [string]$cableItem.status_polaczenia
    $jakosc = [string](Get-SafePropertyValue -Object $reviewItem -Name 'jakosc_onnx' -Default 'BRAK_OCENY')
    $statusModelu = [string]$cableItem.status_modelu
    $feedbackObservations = [int](Get-SafePropertyValue -Object $feedbackItem -Name 'obserwacje_onnx' -Default 0)
    $feedbackLive = [int](Get-SafePropertyValue -Object $feedbackItem -Name 'obserwacje_live' -Default 0)
    $feedbackPaper = [int](Get-SafePropertyValue -Object $feedbackItem -Name 'obserwacje_paper' -Default 0)
    $runtimeInitialized = [bool](Get-SafePropertyValue -Object $runtimeBootstrapItem -Name 'runtime_initialized' -Default $false)
    $runtimeRows = [int](Get-SafePropertyValue -Object $runtimeBootstrapItem -Name 'data_rows' -Default 0)
    $feedbackLayer = if ($feedbackObservations -gt 0) {
        "AKTYWNY"
    }
    elseif ($runtimeInitialized) {
        "ZAINICJALIZOWANY"
    }
    else {
        "BRAK_OBSERWACJI"
    }

    $werdykt = "OBSERWOWAC"
    $rekomendacja = "utrzymac spokojny monitoring"

    if ($statusModelu -eq "GLOBAL_FALLBACK") {
        $werdykt = "FALLBACK_GLOBALNY"
        $rekomendacja = "zbierac probke i zostac przy nauczycielu globalnym"
    }
    elseif ($integracja -ne "POLACZONY_GOTOWY") {
        $werdykt = "DOMKNAC_KABEL"
        $rekomendacja = "naprawic integracje kodu lub artefaktow runtime"
    }
    elseif ($jakosc -eq "SLABY") {
        $werdykt = "DOSZKOLIC_MALY_MODEL"
        $rekomendacja = "nie promowac dalej, najpierw przebudowac lub doszkolic model"
    }
    elseif ($feedbackObservations -le 0) {
        if ($runtimeInitialized) {
            $werdykt = "RUNTIME_ZYJE_CZEKA_NA_PIERWSZY_WIERSZ"
            $rekomendacja = "zostawic runtime w spokoju i czekac na pierwszy kwalifikowany sygnal lub kandydat"
        }
        else {
            $werdykt = "GOTOWY_DO_ZBIERANIA_OBSERWACJI"
            $rekomendacja = "przeladowac eksperta przy najblizszym kontrolowanym rolloutcie i zaczac zbierac obserwacje"
        }
    }
    elseif ($jakosc -in @("MOCNY", "DOBRY")) {
        $werdykt = "GOTOWY_DO_ANALIZY_RUNTIME"
        $rekomendacja = "porownywac maly model z nauczycielem i szykowac miekka bramke"
    }
    elseif ($jakosc -eq "OSTROZNIE") {
        $werdykt = "OBSERWAC_I_DOSZKOLIC"
        $rekomendacja = "zebrac obserwacje runtime i dopiero potem decydowac o dalszym rolloutcie"
    }

    $items.Add([pscustomobject]@{
            symbol = $symbol
            pietro_integracja = $integracja
            pietro_jakosc_modelu = $jakosc
            pietro_sprzezenie_zwrotne = $feedbackLayer
            status_modelu = $statusModelu
            obserwacje_onnx = $feedbackObservations
            obserwacje_live = $feedbackLive
            obserwacje_paper = $feedbackPaper
            runtime_initialized = $runtimeInitialized
            runtime_rows = $runtimeRows
            pole_pod_krzywa_roc = [double](Get-SafePropertyValue -Object $reviewItem -Name 'roc_auc' -Default 0.0)
            trafnosc_zbalansowana = [double](Get-SafePropertyValue -Object $reviewItem -Name 'trafnosc_zbalansowana' -Default 0.0)
            liczba_wierszy = [int](Get-SafePropertyValue -Object $reviewItem -Name 'liczba_wierszy' -Default 0)
            werdykt_koncowy = $werdykt
            rekomendacja = $rekomendacja
        })
}

$items = @($items | Sort-Object symbol)
$summary = [ordered]@{
    total_symbols = @($items).Count
    polaczony_gotowy = @($items | Where-Object { $_.pietro_integracja -eq 'POLACZONY_GOTOWY' }).Count
    fallback_globalny = @($items | Where-Object { $_.status_modelu -eq 'GLOBAL_FALLBACK' }).Count
    mocny_lub_dobry = @($items | Where-Object { $_.pietro_jakosc_modelu -in @('MOCNY', 'DOBRY') }).Count
    brak_obserwacji_runtime = @($items | Where-Object {
        $_.pietro_integracja -eq 'POLACZONY_GOTOWY' -and $_.pietro_sprzezenie_zwrotne -eq 'BRAK_OBSERWACJI'
    }).Count
    runtime_zainicjalizowany = @($items | Where-Object {
        $_.pietro_integracja -eq 'POLACZONY_GOTOWY' -and $_.pietro_sprzezenie_zwrotne -eq 'ZAINICJALIZOWANY'
    }).Count
    obserwacje_onnx_lacznie = $feedbackTotal
    gotowy_do_zbierania_obserwacji = @($items | Where-Object { $_.werdykt_koncowy -eq 'GOTOWY_DO_ZBIERANIA_OBSERWACJI' }).Count
    runtime_zyje_czeka_na_pierwszy_wiersz = @($items | Where-Object { $_.werdykt_koncowy -eq 'RUNTIME_ZYJE_CZEKA_NA_PIERWSZY_WIERSZ' }).Count
    doszkolic_maly_model = @($items | Where-Object { $_.werdykt_koncowy -eq 'DOSZKOLIC_MALY_MODEL' }).Count
}

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    summary = $summary
    items = $items
}

$jsonPath = Join-Path $EvidenceDir "onnx_micro_cross_audit_latest.json"
$mdPath = Join-Path $EvidenceDir "onnx_micro_cross_audit_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Trzypietrowy Audyt Malych ONNX")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- polaczony_gotowy: {0}" -f $summary.polaczony_gotowy))
$lines.Add(("- fallback_globalny: {0}" -f $summary.fallback_globalny))
$lines.Add(("- mocny_lub_dobry: {0}" -f $summary.mocny_lub_dobry))
$lines.Add(("- brak_obserwacji_runtime: {0}" -f $summary.brak_obserwacji_runtime))
$lines.Add(("- runtime_zainicjalizowany: {0}" -f $summary.runtime_zainicjalizowany))
$lines.Add(("- obserwacje_onnx_lacznie: {0}" -f $summary.obserwacje_onnx_lacznie))
$lines.Add("")
$lines.Add("## Symbole")
$lines.Add("")

foreach ($item in $items) {
    $lines.Add(("### {0}" -f $item.symbol))
    $lines.Add(("- pietro_integracja: {0}" -f $item.pietro_integracja))
    $lines.Add(("- pietro_jakosc_modelu: {0}" -f $item.pietro_jakosc_modelu))
    $lines.Add(("- pietro_sprzezenie_zwrotne: {0}" -f $item.pietro_sprzezenie_zwrotne))
    $lines.Add(("- werdykt_koncowy: {0}" -f $item.werdykt_koncowy))
    $lines.Add(("- obserwacje_live: {0}" -f $item.obserwacje_live))
    $lines.Add(("- obserwacje_paper: {0}" -f $item.obserwacje_paper))
    $lines.Add(("- rekomendacja: {0}" -f $item.rekomendacja))
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report
