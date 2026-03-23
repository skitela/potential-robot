param(
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$OnnxRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string]$OnnxReviewPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_micro_review_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [double]$TesterCapitalUsd = 10000.0
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

function Get-OnnxStatus {
    param(
        [hashtable]$OnnxMap,
        [string]$Alias
    )

    if ($OnnxMap.ContainsKey($Alias)) {
        return [string]$OnnxMap[$Alias].status
    }

    return "BRAK"
}

function Get-OnnxQuality {
    param(
        [hashtable]$OnnxReviewMap,
        [string]$Alias
    )

    if ($OnnxReviewMap.ContainsKey($Alias)) {
        return [string]$OnnxReviewMap[$Alias].jakosc_onnx
    }

    return "BRAK"
}

function Get-RolloutVerdict {
    param(
        [string]$OnnxQuality,
        [bool]$QdmReady
    )

    if ($QdmReady -and $OnnxQuality -in @("MOCNY", "DOBRY")) {
        return "GOTOWY_DO_PILOTA_PAPER_LIVE"
    }

    if ($QdmReady -and $OnnxQuality -eq "OSTROZNIE") {
        return "NAJPIERW_OBSERWACJA_ONNX"
    }

    if ($QdmReady) {
        return "DOSZKOLIC_ONNX_I_POTEM_PAPER_LIVE"
    }

    return "UTRZYMAC_W_LABIE"
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    throw "Registry not found: $RegistryPath"
}
if (-not (Test-Path -LiteralPath $ProfitTrackingPath)) {
    throw "Profit tracking not found: $ProfitTrackingPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profitTracking = Get-Content -LiteralPath $ProfitTrackingPath -Raw -Encoding UTF8 | ConvertFrom-Json
$onnxRegistry = if (Test-Path -LiteralPath $OnnxRegistryPath) {
    Get-Content -LiteralPath $OnnxRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $null
}
$onnxReview = if (Test-Path -LiteralPath $OnnxReviewPath) {
    Get-Content -LiteralPath $OnnxReviewPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $null
}

$activeMap = @{}
foreach ($item in @($registry.symbols)) {
    $alias = Normalize-SymbolAlias ([string]$item.symbol)
    if (-not [string]::IsNullOrWhiteSpace($alias)) {
        $activeMap[$alias] = $item
    }
}

$onnxMap = @{}
if ($null -ne $onnxRegistry -and $onnxRegistry.PSObject.Properties.Name -contains "items") {
    foreach ($item in @($onnxRegistry.items)) {
        $alias = Normalize-SymbolAlias ([string]$item.symbol)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $onnxMap[$alias] = $item
        }
    }
}

$onnxReviewMap = @{}
if ($null -ne $onnxReview -and $onnxReview.PSObject.Properties.Name -contains "items") {
    foreach ($item in @($onnxReview.items)) {
        $alias = Normalize-SymbolAlias ([string]$item.symbol_alias)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $onnxReviewMap[$alias] = $item
        }
    }
}

$winners = @(
    @($profitTracking.tester_positive) |
        Where-Object {
            $alias = Normalize-SymbolAlias ([string]$_.symbol_alias)
            $activeMap.ContainsKey($alias)
        } |
        Sort-Object @{ Expression = { [double]$_.best_tester_pnl }; Descending = $true } |
        ForEach-Object {
            $alias = Normalize-SymbolAlias ([string]$_.symbol_alias)
            $onnxStatus = Get-OnnxStatus -OnnxMap $onnxMap -Alias $alias
            $onnxQuality = Get-OnnxQuality -OnnxReviewMap $onnxReviewMap -Alias $alias
            [pscustomobject]@{
                symbol_alias = $alias
                session_profile = [string]$activeMap[$alias].session_profile
                broker_symbol = [string]$activeMap[$alias].broker_symbol
                wynik_testera_usd = [math]::Round([double]$_.best_tester_pnl, 2)
                procent_kapitalu_testera = [math]::Round((100.0 * [double]$_.best_tester_pnl / $TesterCapitalUsd), 2)
                zwycieskie_wejscia = @($_.best_tester_optimization_inputs)
                qdm_custom_gotowy = [bool]$_.qdm_custom_pilot_ready
                qdm_custom_symbol = [string]$_.qdm_custom_symbol
                status_onnx = $onnxStatus
                jakosc_onnx = $onnxQuality
                werdykt_rolloutu = Get-RolloutVerdict -OnnxQuality $onnxQuality -QdmReady ([bool]$_.qdm_custom_pilot_ready)
                zalecenie = if ($onnxQuality -in @("MOCNY", "DOBRY")) {
                    "utrzymac zwycieskie wejscia i przygotowac pilot paper-live"
                }
                elseif ($onnxQuality -eq "OSTROZNIE") {
                    "utrzymac zwycieskie wejscia i najpierw zbierac obserwacje onnx"
                }
                else {
                    "utrzymac zwycieskie wejscia i doszkolic maly model onnx przed paper-live"
                }
            }
        }
)

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    tester_capital_usd = $TesterCapitalUsd
    winner_count = $winners.Count
    winners = $winners
}

$jsonPath = Join-Path $OutputRoot "winner_deployment_latest.json"
$mdPath = Join-Path $OutputRoot "winner_deployment_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Zwyciezcy I Gotowosc Rolloutu")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- liczba zwyciezcow: {0}" -f $report.winner_count))
$lines.Add("")
foreach ($item in @($winners)) {
    $inputs = if (@($item.zwycieskie_wejscia).Count -gt 0) {
        (@($item.zwycieskie_wejscia) -join "; ")
    }
    else {
        "brak"
    }
    $lines.Add(("## {0}" -f $item.symbol_alias))
    $lines.Add(("- profil: {0}" -f $item.session_profile))
    $lines.Add(("- broker_symbol: {0}" -f $item.broker_symbol))
    $lines.Add(("- wynik_testera_usd: {0}" -f $item.wynik_testera_usd))
    $lines.Add(("- procent_kapitalu_testera: {0}%" -f $item.procent_kapitalu_testera))
    $lines.Add(("- zwycieskie_wejscia: {0}" -f $inputs))
    $lines.Add(("- qdm_custom_gotowy: {0}" -f $item.qdm_custom_gotowy))
    $lines.Add(("- status_onnx: {0}" -f $item.status_onnx))
    $lines.Add(("- jakosc_onnx: {0}" -f $item.jakosc_onnx))
    $lines.Add(("- werdykt_rolloutu: {0}" -f $item.werdykt_rolloutu))
    $lines.Add(("- zalecenie: {0}" -f $item.zalecenie))
    $lines.Add("")
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
