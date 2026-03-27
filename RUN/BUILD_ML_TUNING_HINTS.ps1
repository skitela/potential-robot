param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$PriorityPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.json",
    [string]$MlMetricsPath = "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json",
    [string]$StateRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\STATE",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$TopCount = 17
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-SymbolForModel {
    param([string]$Alias)

    if ([string]::IsNullOrWhiteSpace($Alias)) {
        return ""
    }

    $trimmed = $Alias.Trim().ToUpperInvariant()
    $map = @{
        "COPPERUS" = "COPPER-US"
        "US500" = "US500"
        "GOLD" = "GOLD"
        "SILVER" = "SILVER"
    }

    if ($map.ContainsKey($trimmed)) {
        return $map[$trimmed]
    }

    return $trimmed
}

function Get-StateSummary {
    param(
        [string]$Root,
        [string]$Alias
    )

    $path = Join-Path (Join-Path $Root $Alias) "execution_summary.json"
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-StateValue {
    param(
        [object]$State,
        [string]$Name
    )

    if ($null -eq $State) {
        return $null
    }

    $property = $State.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Get-MetricValue {
    param(
        [object]$Metrics,
        [string[]]$Names,
        [double]$Default = 0.0
    )

    foreach ($name in @($Names)) {
        $value = Get-OptionalValue -Object $Metrics -Name $name -Default $null
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [double]$value
        }
    }

    return $Default
}

function Format-NumberOrNa {
    param(
        $Value,
        [string]$Format = "N4"
    )

    if ($null -eq $Value) {
        return "n/a"
    }

    return ([double]$Value).ToString($Format)
}

function Add-HintIfTriggered {
    param(
        [System.Collections.Generic.List[string]]$Hints,
        [double]$Coefficient,
        [string]$Message,
        [ref]$Score
    )

    if ($Coefficient -ne 0.0) {
        $Hints.Add($Message)
        $Score.Value += [math]::Abs($Coefficient)
    }
}

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

if (-not (Test-Path -LiteralPath $PriorityPath)) {
    throw "Priority report not found: $PriorityPath"
}
if (-not (Test-Path -LiteralPath $MlMetricsPath)) {
    throw "ML metrics not found: $MlMetricsPath"
}

$priority = Get-Content -LiteralPath $PriorityPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mlMetrics = Get-Content -LiteralPath $MlMetricsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$topFeaturesRoot = Get-OptionalValue -Object $mlMetrics -Name "top_features" -Default $null
$modelMetrics = [pscustomobject]@{
    accuracy = Get-MetricValue -Metrics (Get-OptionalValue -Object $mlMetrics -Name "metrics" -Default $mlMetrics) -Names @("accuracy") -Default 0.0
    balanced_accuracy = Get-MetricValue -Metrics (Get-OptionalValue -Object $mlMetrics -Name "metrics" -Default $mlMetrics) -Names @("balanced_accuracy", "balanced_accuracy_median") -Default 0.0
    roc_auc = Get-MetricValue -Metrics (Get-OptionalValue -Object $mlMetrics -Name "metrics" -Default $mlMetrics) -Names @("roc_auc", "roc_auc_median") -Default 0.0
}

$featureMap = @{}
foreach ($side in @("positive", "negative")) {
    $sideItems = if ($null -ne $topFeaturesRoot) { @(Get-OptionalValue -Object $topFeaturesRoot -Name $side -Default @()) } else { @() }
    foreach ($item in @($sideItems)) {
        $featureMap[[string]$item.feature] = [double]$item.coefficient
    }
}

$items = New-Object System.Collections.Generic.List[object]
foreach ($entry in @($priority.ranked_instruments | Select-Object -First $TopCount)) {
    $alias = [string]$entry.symbol_alias
    $state = Get-StateSummary -Root $StateRoot -Alias $alias
    $hints = New-Object 'System.Collections.Generic.List[string]'
    $mlRiskScore = 0.0

    $modelSymbol = Normalize-SymbolForModel -Alias $alias
    $symbolFeature = "cat__symbol_{0}" -f $modelSymbol
    if ($featureMap.ContainsKey($symbolFeature)) {
        $coef = [double]$featureMap[$symbolFeature]
        if ($coef -lt -0.25) {
            Add-HintIfTriggered -Hints $hints -Coefficient $coef -Message ("ML: symbol `{0}` has negative profile (`{1:N2}`)" -f $modelSymbol, $coef) -Score ([ref]$mlRiskScore)
        }
        elseif ($coef -gt 0.25) {
            $hints.Add(("ML: symbol `{0}` has positive profile (`{1:N2}`)" -f $modelSymbol, $coef))
        }
    }

    if ($null -ne $state) {
        $lastSetupType = [string](Get-StateValue -State $state -Name "last_setup_type")
        $setupFeature = "cat__setup_type_{0}" -f $lastSetupType
        if (-not [string]::IsNullOrWhiteSpace($lastSetupType) -and $featureMap.ContainsKey($setupFeature)) {
            $coef = [double]$featureMap[$setupFeature]
            if ($coef -lt -0.25) {
                Add-HintIfTriggered -Hints $hints -Coefficient $coef -Message ("ML: current setup `{0}` is negative (`{1:N2}`)" -f $lastSetupType, $coef) -Score ([ref]$mlRiskScore)
            }
            elseif ($coef -gt 0.25) {
                $hints.Add(("ML: current setup `{0}` is supported (`{1:N2}`)" -f $lastSetupType, $coef))
            }
        }

        foreach ($pair in @(
            @{ name = "candle_quality_grade"; value = [string](Get-StateValue -State $state -Name "candle_quality_grade") },
            @{ name = "renko_quality_grade"; value = [string](Get-StateValue -State $state -Name "renko_quality_grade") },
            @{ name = "market_regime"; value = [string](Get-StateValue -State $state -Name "market_regime") },
            @{ name = "spread_regime"; value = [string](Get-StateValue -State $state -Name "spread_regime") },
            @{ name = "confidence_bucket"; value = [string](Get-StateValue -State $state -Name "confidence_bucket") }
        )) {
            if ([string]::IsNullOrWhiteSpace($pair.value)) {
                continue
            }
            $feature = "cat__{0}_{1}" -f $pair.name, $pair.value
            if (-not $featureMap.ContainsKey($feature)) {
                continue
            }

            $coef = [double]$featureMap[$feature]
            if ($coef -lt -0.25) {
                Add-HintIfTriggered -Hints $hints -Coefficient $coef -Message ("ML: `{0}={1}` increases risk (`{2:N2}`)" -f $pair.name, $pair.value, $coef) -Score ([ref]$mlRiskScore)
            }
            elseif ($coef -gt 0.25) {
                $hints.Add(("ML: `{0}={1}` supports conversion (`{2:N2}`)" -f $pair.name, $pair.value, $coef))
            }
        }

        $candleScoreRaw = Get-StateValue -State $state -Name "candle_score"
        $renkoScoreRaw = Get-StateValue -State $state -Name "renko_score"

        if ($null -ne $candleScoreRaw -and [double]$candleScoreRaw -lt 0.25 -and $featureMap.ContainsKey("num_float__candle_score")) {
            $coef = [double]($featureMap["num_float__candle_score"])
            if ($coef -lt 0.0) {
                Add-HintIfTriggered -Hints $hints -Coefficient $coef -Message ("ML: low candle_score ({0:N2}) is unfavorable" -f ([double]$candleScoreRaw)) -Score ([ref]$mlRiskScore)
            }
        }
        if ($null -ne $renkoScoreRaw -and [double]$renkoScoreRaw -lt 0.30 -and $featureMap.ContainsKey("num_float__renko_score")) {
            $coef = [double]($featureMap["num_float__renko_score"])
            if ($coef -lt 0.0) {
                Add-HintIfTriggered -Hints $hints -Coefficient $coef -Message ("ML: low renko_score ({0:N2}) is unfavorable" -f ([double]$renkoScoreRaw)) -Score ([ref]$mlRiskScore)
            }
        }
    }

    if ($hints.Count -eq 0) {
        if ($featureMap.Count -eq 0) {
            $hints.Add("ML: brak jeszcze jawnych wag cech w nowych metrykach; obserwuj runtime, tester i wynik netto")
        }
        else {
            $hints.Add("ML: no strong signal for current state, keep watching tester and runtime")
        }
    }

    $items.Add([pscustomobject]@{
        rank = $entry.rank
        symbol_alias = $alias
        priority_score = $entry.priority_score
        ml_risk_score = [math]::Round($mlRiskScore, 3)
        hints = @($hints)
    })
}

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    model_metrics = $modelMetrics
    items = $items
}

$jsonLatest = Join-Path $EvidenceDir "ml_tuning_hints_latest.json"
$mdLatest = Join-Path $EvidenceDir "ml_tuning_hints_latest.md"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonStamped = Join-Path $EvidenceDir ("ml_tuning_hints_{0}.json" -f $timestamp)
$mdStamped = Join-Path $EvidenceDir ("ml_tuning_hints_{0}.md" -f $timestamp)

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# ML Tuning Hints Latest")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- accuracy: {0}" -f (Format-NumberOrNa -Value ([double]$report.model_metrics.accuracy) -Format "N4")))
$lines.Add(("- balanced_accuracy: {0}" -f (Format-NumberOrNa -Value ([double]$report.model_metrics.balanced_accuracy) -Format "N4")))
$lines.Add(("- roc_auc: {0}" -f (Format-NumberOrNa -Value ([double]$report.model_metrics.roc_auc) -Format "N4")))
$lines.Add("")
foreach ($item in $items) {
    $lines.Add(("## #{0} {1}" -f $item.rank, $item.symbol_alias))
    $lines.Add("")
    $lines.Add(("- priority_score: {0}" -f $item.priority_score))
    $lines.Add(("- ml_risk_score: {0}" -f $item.ml_risk_score))
    foreach ($hint in $item.hints) {
        $lines.Add(("- {0}" -f $hint))
    }
    $lines.Add("")
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdStamped -Encoding UTF8

$report
