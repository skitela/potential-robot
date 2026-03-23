param(
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$OnnxRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-SymbolAlias {
    param([string]$Symbol)

    if ([string]::IsNullOrWhiteSpace($Symbol)) {
        return ""
    }

    return ($Symbol.Trim().ToUpperInvariant() -replace "\.PRO$", "")
}

function Resolve-OnnxQualityBand {
    param(
        [string]$Status,
        [double]$RocAuc,
        [double]$BalancedAccuracy
    )

    if ($Status -ne "MODEL_PER_SYMBOL_READY") {
        return "FALLBACK_GLOBALNY"
    }

    if ($RocAuc -ge 0.90 -and $BalancedAccuracy -ge 0.85) {
        return "MOCNY"
    }

    if ($RocAuc -ge 0.82 -and $BalancedAccuracy -ge 0.70) {
        return "DOBRY"
    }

    if ($RocAuc -ge 0.65 -and $BalancedAccuracy -ge 0.60) {
        return "OSTROZNIE"
    }

    return "SLABY"
}

function Resolve-OnnxRecommendation {
    param([string]$QualityBand)

    switch ($QualityBand) {
        "MOCNY" { return "mozna utrzymac jako silny kandydat do obserwacji runtime i dalszego rollout'u" }
        "DOBRY" { return "utrzymac obserwacje runtime i spokojnie przygotowywac kolejny etap" }
        "OSTROZNIE" { return "zostawic w obserwacji i doszkolic przed jakimkolwiek ruchem do paper-live" }
        "SLABY" { return "nie promowac dalej, najpierw doszkolic lub przebudowac maly model" }
        default { return "na razie korzystac z modelu globalnego i zbierac dalsza probke" }
    }
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    throw "Registry not found: $RegistryPath"
}
if (-not (Test-Path -LiteralPath $OnnxRegistryPath)) {
    throw "ONNX registry not found: $OnnxRegistryPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$onnxRegistry = Get-Content -LiteralPath $OnnxRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json

$activeMap = @{}
foreach ($item in @($registry.symbols)) {
    $alias = Normalize-SymbolAlias ([string]$item.symbol)
    if (-not [string]::IsNullOrWhiteSpace($alias)) {
        $activeMap[$alias] = $item
    }
}

$items = @(
    @($onnxRegistry.items) |
        Where-Object {
            $alias = Normalize-SymbolAlias ([string]$_.symbol)
            $activeMap.ContainsKey($alias)
        } |
        ForEach-Object {
            $alias = Normalize-SymbolAlias ([string]$_.symbol)
            $qualityBand = Resolve-OnnxQualityBand `
                -Status ([string]$_.status) `
                -RocAuc ([double]$_.roc_auc) `
                -BalancedAccuracy ([double]$_.balanced_accuracy)

            [pscustomobject]@{
                symbol_alias = $alias
                session_profile = [string]$activeMap[$alias].session_profile
                status_onnx = [string]$_.status
                jakosc_onnx = $qualityBand
                roc_auc = [math]::Round([double]$_.roc_auc, 4)
                trafnosc_zbalansowana = [math]::Round([double]$_.balanced_accuracy, 4)
                liczba_wierszy = [int]$_.rows_total
                dodatnie_wiersze = [int]$_.positive_rows
                ujemne_wiersze = [int]$_.negative_rows
                nauczyciel_globalny = [bool]$_.teacher_enabled
                zalecenie = Resolve-OnnxRecommendation -QualityBand $qualityBand
            }
        } |
        Sort-Object @{
            Expression = {
                switch ([string]$_.jakosc_onnx) {
                    "MOCNY" { 0 }
                    "DOBRY" { 1 }
                    "OSTROZNIE" { 2 }
                    "SLABY" { 3 }
                    default { 4 }
                }
            }
        }, @{
            Expression = { [double]$_.roc_auc }
            Descending = $true
        }, symbol_alias
)

$summary = [ordered]@{
    total_symbols = $items.Count
    mocny = @($items | Where-Object { $_.jakosc_onnx -eq "MOCNY" }).Count
    dobry = @($items | Where-Object { $_.jakosc_onnx -eq "DOBRY" }).Count
    ostroznie = @($items | Where-Object { $_.jakosc_onnx -eq "OSTROZNIE" }).Count
    slaby = @($items | Where-Object { $_.jakosc_onnx -eq "SLABY" }).Count
    fallback_globalny = @($items | Where-Object { $_.jakosc_onnx -eq "FALLBACK_GLOBALNY" }).Count
}

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    summary = $summary
    items = $items
}

$jsonPath = Join-Path $OutputRoot "onnx_micro_review_latest.json"
$mdPath = Join-Path $OutputRoot "onnx_micro_review_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Przeglad Malych ONNX")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- mocny: {0}" -f $summary.mocny))
$lines.Add(("- dobry: {0}" -f $summary.dobry))
$lines.Add(("- ostroznie: {0}" -f $summary.ostroznie))
$lines.Add(("- slaby: {0}" -f $summary.slaby))
$lines.Add(("- fallback_globalny: {0}" -f $summary.fallback_globalny))
$lines.Add("")
foreach ($item in @($items)) {
    $lines.Add(("## {0}" -f $item.symbol_alias))
    $lines.Add(("- profil: {0}" -f $item.session_profile))
    $lines.Add(("- status_onnx: {0}" -f $item.status_onnx))
    $lines.Add(("- jakosc_onnx: {0}" -f $item.jakosc_onnx))
    $lines.Add(("- roc_auc: {0}" -f $item.roc_auc))
    $lines.Add(("- trafnosc_zbalansowana: {0}" -f $item.trafnosc_zbalansowana))
    $lines.Add(("- liczba_wierszy: {0}" -f $item.liczba_wierszy))
    $lines.Add(("- nauczyciel_globalny: {0}" -f $item.nauczyciel_globalny))
    $lines.Add(("- zalecenie: {0}" -f $item.zalecenie))
    $lines.Add("")
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
