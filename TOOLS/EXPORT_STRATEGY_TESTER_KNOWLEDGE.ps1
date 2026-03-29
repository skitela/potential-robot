param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [Parameter(Mandatory = $true)]
    [string]$SymbolAlias,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDir,
    [Parameter(Mandatory = $true)]
    [string]$SandboxRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-TsvRows {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }
    return @(Import-Csv -LiteralPath $Path -Delimiter "`t")
}

function Get-TesterReadiness {
    param(
        [psobject]$Summary,
        [psobject]$DeckhandSnapshot
    )

    $sampleCount = 0
    if ($Summary -and $Summary.PSObject.Properties.Name -contains 'learning_sample_count') {
        $sampleCount = [int]$Summary.learning_sample_count
    }

    $trustState = ""
    if ($Summary -and $Summary.PSObject.Properties.Name -contains 'trust_state') {
        $trustState = [string]$Summary.trust_state
    }

    $trustReason = ""
    if ($Summary -and $Summary.PSObject.Properties.Name -contains 'trust_reason') {
        $trustReason = [string]$Summary.trust_reason
    }

    $costState = ""
    if ($Summary -and $Summary.PSObject.Properties.Name -contains 'cost_pressure_state') {
        $costState = [string]$Summary.cost_pressure_state
    }

    $executionState = ""
    if ($Summary -and $Summary.PSObject.Properties.Name -contains 'execution_quality_state') {
        $executionState = [string]$Summary.execution_quality_state
    }

    $observationDataState = ""
    if ($Summary -and $Summary.PSObject.Properties.Name -contains 'observation_data_state') {
        $observationDataState = [string]$Summary.observation_data_state
    }

    $paperLearningState = ""
    if ($Summary -and $Summary.PSObject.Properties.Name -contains 'paper_learning_state') {
        $paperLearningState = [string]$Summary.paper_learning_state
    }

    $dominantConstraint = "LOCAL_SIGNAL"
    $readinessState = "READY_FOR_DELTA"
    $recommendedFocus = "Strojenie lokalnej logiki setupow na czystym materiale."

    if ($executionState -ne "" -and $executionState -ne "GOOD") {
        $readinessState = "EXECUTION_LIMITED"
        $dominantConstraint = "EXECUTION"
        $recommendedFocus = "Najpierw warstwa wykonania i stabilnosc srodowiska testu, dopiero potem strategia."
    }
    elseif ($trustState -eq "OBSERVATIONS_MISSING" -and $paperLearningState -eq "WAITING_FOR_FIRST_PAPER_CLOSE") {
        $readinessState = "WAITING_PAPER_CLOSURE"
        $dominantConstraint = "PAPER_CLOSE"
        $recommendedFocus = "Nie stroic jeszcze deckhanda; doprowadzic do pierwszego zamkniecia paper albo wydluzyc okno testowe."
    }
    elseif ($trustState -eq "OBSERVATIONS_MISSING" -and $paperLearningState -eq "WAITING_FOR_FIRST_PAPER_OPEN") {
        $readinessState = "WAITING_PAPER_OPEN"
        $dominantConstraint = "PAPER_OPEN"
        $recommendedFocus = "Najpierw doprowadzic do pierwszych otwarc paper; dopiero potem oczekiwac learning_observations_v2."
    }
    elseif ($trustState -eq "OBSERVATIONS_MISSING" -and $observationDataState -eq "OBSERVATION_INFRA_NOT_MATERIALIZED") {
        $readinessState = "OBSERVATION_INFRA_MISSING"
        $dominantConstraint = "INFRA"
        $recommendedFocus = "Najpierw sprawdzic pipeline kandydat/onnx/tester, bo brak nawet materializacji wspierajacych artefaktow."
    }
    elseif ($sampleCount -lt 20 -or $trustState -eq "LOW_SAMPLE") {
        $readinessState = "INSUFFICIENT_SAMPLE"
        $dominantConstraint = "SAMPLE"
        $recommendedFocus = "Nie stroic logiki; najpierw zwiekszyc probe lub zmienic okno testowe."
    }
    elseif ($costState -eq "NON_REPRESENTATIVE") {
        $readinessState = "COST_SKEWED"
        $dominantConstraint = "COST"
        $recommendedFocus = "Najpierw reprezentatywnosc kosztu i spreadu, nie strategia."
    }
    elseif ($trustState -eq "PAPER_CONVERSION_BLOCKED") {
        $readinessState = "CONVERSION_LIMITED"
        $dominantConstraint = "CONVERSION"
        $recommendedFocus = "Najpierw konwersja kandydat -> lekcja paper, potem strojenie sygnalu."
    }
    elseif ($trustState -eq "FOREFIELD_DIRTY") {
        $readinessState = "DIRTY_FOREGROUND"
        $dominantConstraint = "DATA_TRUST"
        $recommendedFocus = "Najpierw doczyscic forefield i ksiegowosc deckhanda, potem strategia."
    }

    [pscustomobject]@{
        readiness_state    = $readinessState
        dominant_constraint = $dominantConstraint
        trust_state        = $trustState
        trust_reason       = $trustReason
        cost_state         = $costState
        execution_state    = $executionState
        observation_data_state = $observationDataState
        paper_learning_state = $paperLearningState
        sample_count       = $sampleCount
        recommended_focus  = $recommendedFocus
    }
}

$symbolDir = Join-Path $SandboxRoot ("logs\{0}" -f $SymbolAlias)
$candidatePath = Join-Path $symbolDir "candidate_signals.csv"
$bucketPath = Join-Path $symbolDir "learning_bucket_summary_v1.csv"
$observationsPath = Join-Path $symbolDir "learning_observations_v2.csv"
$deckhandPath = Join-Path $symbolDir "tuning_deckhand.csv"
$optimizationPassesPath = Join-Path $SandboxRoot ("run\{0}\tester_optimization_passes.jsonl" -f $SymbolAlias)
$summaryPath = Join-Path $EvidenceDir ($RunId + "_summary.json")

$candidateRows = @(Read-TsvRows -Path $candidatePath)
$bucketRows = @(Read-TsvRows -Path $bucketPath)
$observationRows = @(Read-TsvRows -Path $observationsPath)
$deckhandRows = @(Read-TsvRows -Path $deckhandPath)
$summary = $null
if (Test-Path -LiteralPath $summaryPath) {
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$candidateReasons = @(
    $candidateRows |
    Group-Object stage,reason_code |
    Sort-Object Count -Descending |
    Select-Object -First 20 @{ Name = 'count'; Expression = { $_.Count } }, @{ Name = 'name'; Expression = { $_.Name } }
)

$opensBySetupRegime = @(
    $candidateRows |
    Where-Object { $_.stage -eq 'PAPER_OPEN' -and $_.reason_code -eq 'PAPER_POSITION_OPENED' } |
    Group-Object setup_type,market_regime |
    Sort-Object Count -Descending |
    Select-Object -First 20 @{ Name = 'count'; Expression = { $_.Count } }, @{ Name = 'name'; Expression = { $_.Name } }
)

$closeStats = @(
    $observationRows |
    Group-Object close_reason |
    Sort-Object Count -Descending |
    ForEach-Object {
        [pscustomobject]@{
            close_reason = $_.Name
            count        = $_.Count
            avg_pnl      = [math]::Round((($_.Group | Measure-Object -Property pnl -Average).Average), 4)
        }
    }
)

$weakPatterns = @(
    $observationRows |
    Where-Object { $_.setup_type -and $_.market_regime } |
    Group-Object setup_type,market_regime,candle_quality_grade,renko_quality_grade,spread_regime |
    ForEach-Object {
        [pscustomobject]@{
            pattern = $_.Name
            count   = $_.Count
            avg_pnl = [math]::Round((($_.Group | Measure-Object -Property pnl -Average).Average), 4)
        }
    } |
    Sort-Object avg_pnl, @{ Expression = 'count'; Descending = $true } |
    Select-Object -First 15
)

$deckhandSnapshot = $null
if (@($deckhandRows).Count -gt 0) {
    $deckhandSnapshot = $deckhandRows[-1]
}

$optimizationPassCount = 0
if (Test-Path -LiteralPath $optimizationPassesPath) {
    $optimizationPassCount = @(Get-Content -LiteralPath $optimizationPassesPath -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
}

$testerReadiness = Get-TesterReadiness -Summary $summary -DeckhandSnapshot $deckhandSnapshot

$knowledge = [ordered]@{
    generated_at_utc         = (Get-Date).ToUniversalTime().ToString("o")
    run_id                   = $RunId
    symbol_alias             = $SymbolAlias
    summary                  = $summary
    tester_readiness         = $testerReadiness
    candidate_reason_stats   = $candidateReasons
    paper_open_by_setup_regime = $opensBySetupRegime
    paper_close_stats        = $closeStats
    weakest_observation_patterns = $weakPatterns
    deckhand_snapshot        = $deckhandSnapshot
    tester_optimization_passes_path = $(if (Test-Path -LiteralPath $optimizationPassesPath) { $optimizationPassesPath } else { $null })
    tester_optimization_pass_count = $optimizationPassCount
}

$jsonPath = Join-Path $EvidenceDir ($RunId + "_knowledge.json")
$mdPath = Join-Path $EvidenceDir ($RunId + "_knowledge.md")
$knowledge | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$mdLines = @(
    "# Strategy Tester Knowledge $SymbolAlias",
    "",
    ("- run_id: {0}" -f $RunId),
    ("- trust: {0} / {1}" -f $summary.trust_state, $summary.trust_reason),
    ("- cost: {0}" -f $summary.cost_pressure_state),
    ("- tester_custom_score: {0}" -f $summary.tester_custom_score),
    ("- tester_optimization_pass_count: {0}" -f $optimizationPassCount),
    ("- samples: {0}" -f $summary.learning_sample_count),
    ("- observation_data_state: {0}" -f $summary.observation_data_state),
    ("- paper_learning_state: {0}" -f $summary.paper_learning_state),
    ("- observation_rows candidate/onnx/learning: {0}/{1}/{2}" -f $summary.candidate_signal_rows_total, $summary.onnx_observation_rows, $summary.learning_observation_rows),
    ("- wins/losses: {0}/{1}" -f $summary.learning_win_count, $summary.learning_loss_count),
    ("- paper_open_rows: {0}" -f $summary.paper_open_rows),
    ("- paper_score_gate_rows: {0}" -f $summary.paper_score_gate_rows),
    ("- realized_pnl_lifetime: {0}" -f $summary.realized_pnl_lifetime),
    ("- tester_penalties trust/cost/exec/latency: {0}/{1}/{2}/{3}" -f $summary.tester_trust_penalty, $summary.tester_cost_penalty, $summary.tester_execution_penalty, $summary.tester_latency_penalty),
    ("- readiness: {0} / {1}" -f $testerReadiness.readiness_state, $testerReadiness.dominant_constraint),
    ("- next_focus: {0}" -f $testerReadiness.recommended_focus),
    "",
    "## Top candidate reasons",
    ""
)

foreach ($item in $candidateReasons) {
    $mdLines += ("- {0}: {1}" -f $item.name, $item.count)
}

$mdLines += ""
$mdLines += "## Paper open by setup/regime"
$mdLines += ""
foreach ($item in $opensBySetupRegime) {
    $mdLines += ("- {0}: {1}" -f $item.name, $item.count)
}

$mdLines += ""
$mdLines += "## Close reasons"
$mdLines += ""
foreach ($item in $closeStats) {
    $mdLines += ("- {0}: count={1}, avg_pnl={2}" -f $item.close_reason, $item.count, $item.avg_pnl)
}

$mdLines += ""
$mdLines += "## Weakest observation patterns"
$mdLines += ""
foreach ($item in $weakPatterns) {
    $mdLines += ("- {0}: count={1}, avg_pnl={2}" -f $item.pattern, $item.count, $item.avg_pnl)
}

($mdLines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$knowledge
