param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [Parameter(Mandatory = $true)]
    [string]$SymbolAlias,
    [string]$Symbol = "",
    [string]$ExpertName = "",
    [string]$ExpertPath = "",
    [string]$SandboxTag = "",
    [string]$Period = "M5",
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$Model = 4,
    [double]$Deposit = 10000.0,
    [int]$Leverage = 100,
    [int]$TimeoutSec = 1800,
    [string]$WorkerName = "",
    [string]$EvidenceSubdir = "",
    [switch]$SkipKnowledgeExport,
    [switch]$RestoreMicrobotsProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToSandboxToken {
    param([string]$Value)
    $chars = $Value.ToCharArray() | ForEach-Object {
        if (($_ -ge 'A' -and $_ -le 'Z') -or ($_ -ge 'a' -and $_ -le 'z') -or ($_ -ge '0' -and $_ -le '9') -or $_ -eq '_' -or $_ -eq '-') {
            [string]$_
        } else {
            "_"
        }
    }
    $out = -join $chars
    if ([string]::IsNullOrWhiteSpace($out)) {
        return "DEFAULT"
    }
    return $out
}

function Resolve-EvidenceDir {
    param(
        [string]$ProjectRootPath,
        [string]$Subdir
    )
    $base = Join-Path $ProjectRootPath "EVIDENCE\STRATEGY_TESTER"
    if ([string]::IsNullOrWhiteSpace($Subdir)) {
        return $base
    }
    return (Join-Path $base $Subdir)
}

function Resolve-TesterSymbol {
    param(
        [string]$RegistrySymbol,
        [string]$ExplicitSymbol
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitSymbol)) {
        return $ExplicitSymbol
    }
    $symbol = [string]$RegistrySymbol
    if ([string]::IsNullOrWhiteSpace($symbol)) {
        return $symbol
    }
    if ($symbol -match '\.pro$') {
        return $symbol
    }
    if ($symbol -match '^[A-Z]{6}$') {
        return ($symbol + ".pro")
    }
    return $symbol
}

function Get-RegistryEntry {
    param(
        [string]$RegistryPath,
        [string]$Alias
    )
    $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $matches = @(
        $registry.symbols | Where-Object {
            $codeSymbol = if ($_.PSObject.Properties.Name -contains 'code_symbol') { [string]$_.code_symbol } else { "" }
            $_.symbol -eq $Alias -or
            $codeSymbol -eq $Alias -or
            $_.expert -eq $Alias
        }
    )
    return ($matches | Select-Object -First 1)
}

function Get-KeyValueCsvMap {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $map[$parts[0]] = $parts[1]
    }
    return $map
}

function Get-TesterRunOutcome {
    param(
        [string[]]$LogPaths,
        [string]$ExpertName,
        [string]$Symbol,
        [string]$Period,
        [string]$FromDate,
        [string]$ToDate
    )
    $outcome = [ordered]@{
        final_balance = $null
        test_duration = ""
        result_label  = ""
    }

    $escapedExpert = [regex]::Escape(("Experts\MicroBots\{0}.ex5" -f $ExpertName))
    $escapedSymbol = [regex]::Escape($Symbol)
    $escapedPeriod = [regex]::Escape($Period)
    $escapedFrom = [regex]::Escape(($FromDate + " 00:00"))
    $escapedTo = [regex]::Escape(($ToDate + " 00:00"))
    $startPattern = ("{0},{1}: testing of {2} from {3} to {4} started" -f $escapedSymbol, $escapedPeriod, $escapedExpert, $escapedFrom, $escapedTo)

    foreach ($logPath in $LogPaths) {
        if (-not (Test-Path -LiteralPath $logPath)) {
            continue
        }
        $lines = @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue)
        if ($lines.Count -eq 0) {
            continue
        }

        $startIndex = -1
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match $startPattern) {
                $startIndex = $i
                break
            }
        }
        if ($startIndex -lt 0) {
            continue
        }

        for ($i = $startIndex; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($null -eq $outcome.final_balance -and $line -match 'final balance ([0-9\.\-]+)') {
                $outcome.final_balance = [double]$matches[1]
            }
            if ([string]::IsNullOrWhiteSpace($outcome.result_label) -and $line -match 'Test passed in ([0-9:\.]+)') {
                $outcome.test_duration = $matches[1]
                $outcome.result_label = "successfully_finished"
            }
        }

        if ($null -ne $outcome.final_balance -or -not [string]::IsNullOrWhiteSpace($outcome.result_label)) {
            break
        }
    }

    return $outcome
}

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$entry = Get-RegistryEntry -RegistryPath $registryPath -Alias $SymbolAlias
if (-not $entry) {
    throw "SymbolAlias not found in registry: $SymbolAlias"
}

$entryCodeSymbol = if ($entry.PSObject.Properties.Name -contains 'code_symbol') { [string]$entry.code_symbol } else { "" }
$resolvedAlias = Convert-ToSandboxToken $(if (-not [string]::IsNullOrWhiteSpace($entryCodeSymbol)) { $entryCodeSymbol } else { [string]$entry.symbol })
if ([string]::IsNullOrWhiteSpace($SandboxTag)) {
    $SandboxTag = "${resolvedAlias}_AGENT"
}
$sanitizedTag = Convert-ToSandboxToken $SandboxTag

$Symbol = Resolve-TesterSymbol -RegistrySymbol ([string]$entry.symbol) -ExplicitSymbol $Symbol
if ([string]::IsNullOrWhiteSpace($ExpertName)) {
    $ExpertName = [string]$entry.expert
}
if ([string]::IsNullOrWhiteSpace($ExpertPath)) {
    $ExpertPath = "MicroBots\$ExpertName.ex5"
}
if ($ExpertPath -match '^(?i)Experts\\') {
    $ExpertPath = $ExpertPath.Substring(8)
}

$runId = ("{0}_strategy_tester_{1}" -f $resolvedAlias.ToLowerInvariant(), (Get-Date -Format "yyyyMMdd_HHmmss"))
$runDir = Join-Path $ProjectRoot "RUN\strategy_tester"
$workerToken = Convert-ToSandboxToken $WorkerName
if ([string]::IsNullOrWhiteSpace($EvidenceSubdir) -and -not [string]::IsNullOrWhiteSpace($workerToken)) {
    $EvidenceSubdir = $workerToken.ToLowerInvariant()
}
$evidenceDir = Resolve-EvidenceDir -ProjectRootPath $ProjectRoot -Subdir $EvidenceSubdir
$mt5Root = Split-Path -Parent $Mt5Exe
$mt5ReportsDir = Join-Path $mt5Root "reports"
$terminalHash = Split-Path $TerminalDataDir -Leaf
$metaQuotesRoot = Split-Path (Split-Path $TerminalDataDir -Parent) -Parent
$testerAgentsRoot = Join-Path $metaQuotesRoot ("Tester\" + $terminalHash)
$configPath = Join-Path $runDir ($runId + ".ini")
$testerLogDir = Join-Path $TerminalDataDir "Tester\logs"
$terminalLogDir = Join-Path $TerminalDataDir "logs"
$reportBaseRel = "reports\" + $runId
$sandboxName = "MAKRO_I_MIKRO_BOT_TESTER_${resolvedAlias}_${sanitizedTag}"
$sandboxRoot = Join-Path (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files") $sandboxName

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
New-Item -ItemType Directory -Force -Path $mt5ReportsDir | Out-Null

& (Join-Path $ProjectRoot "TOOLS\RESET_MICROBOT_STRATEGY_TESTER_SANDBOX.ps1") -ProjectRoot $ProjectRoot -SymbolAlias $resolvedAlias -SandboxTag $sanitizedTag | Out-Null
& (Join-Path $ProjectRoot "TOOLS\COMPILE_MICROBOT.ps1") -ExpertName $ExpertName | Out-Null

$config = @"
[Tester]
Expert=$ExpertPath
Symbol=$Symbol
Period=$Period
Model=$Model
Optimization=0
FromDate=$FromDate
ToDate=$ToDate
ForwardMode=0
Deposit=$Deposit
Currency=USD
Leverage=$Leverage
UseLocal=1
UseRemote=0
ReplaceReport=1
Report=$reportBaseRel
ShutdownTerminal=1
"@

$config | Set-Content -LiteralPath $configPath -Encoding ASCII

$beforeTesterLogs = @()
if (Test-Path -LiteralPath $testerLogDir) {
    $beforeTesterLogs = @(Get-ChildItem -LiteralPath $testerLogDir -File | Select-Object -ExpandProperty FullName)
}
$beforeTerminalLogs = @()
if (Test-Path -LiteralPath $terminalLogDir) {
    $beforeTerminalLogs = @(Get-ChildItem -LiteralPath $terminalLogDir -File | Select-Object -ExpandProperty FullName)
}
$beforeAgentLogs = @()
if (Test-Path -LiteralPath $testerAgentsRoot) {
    $beforeAgentLogs = @(Get-ChildItem -LiteralPath $testerAgentsRoot -Recurse -File -Filter *.log | Select-Object -ExpandProperty FullName)
}

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$process = Start-Process -FilePath $Mt5Exe -ArgumentList @("/config:$configPath") -PassThru
$timedOut = $false
try {
    Wait-Process -Id $process.Id -Timeout $TimeoutSec -ErrorAction Stop
} catch {
    $timedOut = $true
    Get-Process -Id $process.Id -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

$reportCandidates = @(
    (Join-Path $mt5ReportsDir ($runId + ".htm")),
    (Join-Path $mt5ReportsDir ($runId + ".html")),
    (Join-Path $mt5ReportsDir ($runId + ".xml"))
) | Where-Object { Test-Path -LiteralPath $_ }

$copiedReports = @()
foreach ($reportPath in $reportCandidates) {
    $target = Join-Path $evidenceDir ($runId + "__report__" + [System.IO.Path]::GetFileName($reportPath))
    Copy-Item -LiteralPath $reportPath -Destination $target -Force
    $copiedReports += $target
}

$afterTesterLogs = @()
if (Test-Path -LiteralPath $testerLogDir) {
    $afterTesterLogs = @(Get-ChildItem -LiteralPath $testerLogDir -File | Select-Object -ExpandProperty FullName)
}
$newTesterLogs = @($afterTesterLogs | Where-Object { $_ -notin $beforeTesterLogs })
if ($newTesterLogs.Count -eq 0 -and (Test-Path -LiteralPath $testerLogDir)) {
    $latest = Get-ChildItem -LiteralPath $testerLogDir -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $newTesterLogs = @($latest.FullName) }
}

$copiedTesterLogs = @()
foreach ($logPath in $newTesterLogs) {
    $target = Join-Path $evidenceDir ($runId + "__tester__" + [System.IO.Path]::GetFileName($logPath))
    Copy-Item -LiteralPath $logPath -Destination $target -Force
    $copiedTesterLogs += $target
}

$afterTerminalLogs = @()
if (Test-Path -LiteralPath $terminalLogDir) {
    $afterTerminalLogs = @(Get-ChildItem -LiteralPath $terminalLogDir -File | Select-Object -ExpandProperty FullName)
}
$newTerminalLogs = @($afterTerminalLogs | Where-Object { $_ -notin $beforeTerminalLogs })
if ($newTerminalLogs.Count -eq 0 -and (Test-Path -LiteralPath $terminalLogDir)) {
    $latest = Get-ChildItem -LiteralPath $terminalLogDir -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $newTerminalLogs = @($latest.FullName) }
}

$copiedTerminalLogs = @()
foreach ($logPath in $newTerminalLogs) {
    $target = Join-Path $evidenceDir ($runId + "__terminal__" + [System.IO.Path]::GetFileName($logPath))
    Copy-Item -LiteralPath $logPath -Destination $target -Force
    $copiedTerminalLogs += $target
}

$afterAgentLogs = @()
if (Test-Path -LiteralPath $testerAgentsRoot) {
    $afterAgentLogs = @(Get-ChildItem -LiteralPath $testerAgentsRoot -Recurse -File -Filter *.log | Select-Object -ExpandProperty FullName)
}
$newAgentLogs = @($afterAgentLogs | Where-Object { $_ -notin $beforeAgentLogs })
if ($newAgentLogs.Count -eq 0 -and (Test-Path -LiteralPath $testerAgentsRoot)) {
    $latest = Get-ChildItem -LiteralPath $testerAgentsRoot -Recurse -File -Filter *.log | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $newAgentLogs = @($latest.FullName) }
}

$copiedAgentLogs = @()
foreach ($logPath in $newAgentLogs) {
    $target = Join-Path $evidenceDir ($runId + "__agent__" + [System.IO.Path]::GetFileName($logPath))
    Copy-Item -LiteralPath $logPath -Destination $target -Force
    $copiedAgentLogs += $target
}

$runOutcome = Get-TesterRunOutcome -LogPaths $copiedTesterLogs -ExpertName $ExpertName -Symbol $Symbol -Period $Period -FromDate $FromDate -ToDate $ToDate
$finalBalance = $runOutcome.final_balance
$testDuration = $runOutcome.test_duration
$resultLabel = $runOutcome.result_label
if ($timedOut -and [string]::IsNullOrWhiteSpace($resultLabel)) {
    $resultLabel = "timed_out"
}

$executionSummaryPath = Join-Path $sandboxRoot ("state\{0}\execution_summary.json" -f $resolvedAlias)
$runtimeStatePath = Join-Path $sandboxRoot ("state\{0}\runtime_state.csv" -f $resolvedAlias)
$candidateSignalsPath = Join-Path $sandboxRoot ("logs\{0}\candidate_signals.csv" -f $resolvedAlias)
$bucketSummaryPath = Join-Path $sandboxRoot ("logs\{0}\learning_bucket_summary_v1.csv" -f $resolvedAlias)
$learningObservationsPath = Join-Path $sandboxRoot ("logs\{0}\learning_observations_v2.csv" -f $resolvedAlias)
$tuningDeckhandPath = Join-Path $sandboxRoot ("logs\{0}\tuning_deckhand.csv" -f $resolvedAlias)

$executionSummary = $null
if (Test-Path -LiteralPath $executionSummaryPath) {
    $executionSummary = Get-Content -LiteralPath $executionSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$runtimeMap = Get-KeyValueCsvMap -Path $runtimeStatePath

$paperOpenRows = 0
$paperScoreGateRows = 0
$acceptedEvaluatedRows = 0
$scoreBelowTriggerRows = 0
$topCandidateReasons = @()
$paperCloseStats = @()
$paperOpenBySetupRegime = @()
$deckhandSnapshot = $null
if (Test-Path -LiteralPath $candidateSignalsPath) {
    $candidateRows = Import-Csv -LiteralPath $candidateSignalsPath -Delimiter "`t"
    $paperOpenRows = @($candidateRows | Where-Object { $_.stage -eq 'PAPER_OPEN' -and $_.reason_code -eq 'PAPER_POSITION_OPENED' }).Count
    $paperScoreGateRows = @($candidateRows | Where-Object { $_.stage -eq 'EVALUATED' -and $_.reason_code -eq 'PAPER_SCORE_GATE' }).Count
    $acceptedEvaluatedRows = @($candidateRows | Where-Object { $_.stage -eq 'EVALUATED' -and $_.accepted -eq '1' }).Count
    $scoreBelowTriggerRows = @($candidateRows | Where-Object { $_.stage -eq 'EVALUATED' -and $_.reason_code -eq 'SCORE_BELOW_TRIGGER' }).Count
    $topCandidateReasons = @(
        $candidateRows |
        Group-Object stage,reason_code |
        Sort-Object Count -Descending |
        Select-Object -First 12 @{ Name = 'count'; Expression = { $_.Count } }, @{ Name = 'name'; Expression = { $_.Name } }
    )
    $paperOpenBySetupRegime = @(
        $candidateRows |
        Where-Object { $_.stage -eq 'PAPER_OPEN' -and $_.reason_code -eq 'PAPER_POSITION_OPENED' } |
        Group-Object setup_type,market_regime |
        Sort-Object Count -Descending |
        Select-Object -First 12 @{ Name = 'count'; Expression = { $_.Count } }, @{ Name = 'name'; Expression = { $_.Name } }
    )
}

$worstBuckets = @()
if (Test-Path -LiteralPath $bucketSummaryPath) {
    $worstBuckets = @(
        Import-Csv -LiteralPath $bucketSummaryPath -Delimiter "`t" |
        Sort-Object { [double]$_.avg_pnl } |
        Select-Object -First 6 setup_type,market_regime,samples,wins,losses,avg_pnl
    )
}

if (Test-Path -LiteralPath $learningObservationsPath) {
    $paperCloseStats = @(
        Import-Csv -LiteralPath $learningObservationsPath -Delimiter "`t" |
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
}

if (Test-Path -LiteralPath $tuningDeckhandPath) {
    $deckhandRows = @(Import-Csv -LiteralPath $tuningDeckhandPath -Delimiter "`t")
    if ($deckhandRows.Count -gt 0) {
        $deckhandSnapshot = $deckhandRows[-1]
    }
}

$summaryTrustState = $executionSummary.trust_state
$summaryTrustReason = $executionSummary.trust_reason
$summaryExecutionQualityState = $executionSummary.execution_quality_state
$summaryCostPressureState = $executionSummary.cost_pressure_state

if ($null -ne $deckhandSnapshot) {
    if ($deckhandSnapshot.PSObject.Properties.Name -contains 'trust_state' -and -not [string]::IsNullOrWhiteSpace([string]$deckhandSnapshot.trust_state)) {
        $summaryTrustState = [string]$deckhandSnapshot.trust_state
    }
    if ($deckhandSnapshot.PSObject.Properties.Name -contains 'reason_code' -and -not [string]::IsNullOrWhiteSpace([string]$deckhandSnapshot.reason_code)) {
        $summaryTrustReason = [string]$deckhandSnapshot.reason_code
    }
    if ($deckhandSnapshot.PSObject.Properties.Name -contains 'execution_quality_state' -and -not [string]::IsNullOrWhiteSpace([string]$deckhandSnapshot.execution_quality_state)) {
        $summaryExecutionQualityState = [string]$deckhandSnapshot.execution_quality_state
    }
    if ($deckhandSnapshot.PSObject.Properties.Name -contains 'cost_pressure_state' -and -not [string]::IsNullOrWhiteSpace([string]$deckhandSnapshot.cost_pressure_state)) {
        $summaryCostPressureState = [string]$deckhandSnapshot.cost_pressure_state
    }
}

$conversionRatio = 0.0
if ($acceptedEvaluatedRows -gt 0) {
    $conversionRatio = [math]::Round(($paperOpenRows / [double]$acceptedEvaluatedRows), 4)
}

if ($RestoreMicrobotsProfile) {
    & (Join-Path $ProjectRoot "RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1") | Out-Null
}

$result = [ordered]@{
    run_id                = $runId
    generated_at_utc      = (Get-Date).ToUniversalTime().ToString("o")
    symbol_alias          = $resolvedAlias
    sandbox_name          = $sandboxName
    config_path           = $configPath
    mt5_exe               = $Mt5Exe
    terminal_data_dir     = $TerminalDataDir
    symbol                = $Symbol
    expert_name           = $ExpertName
    expert_path           = $ExpertPath
    from_date             = $FromDate
    to_date               = $ToDate
    model                 = $Model
    timed_out             = $timedOut
    reports_copied        = $copiedReports
    tester_logs_copied    = $copiedTesterLogs
    terminal_logs_copied  = $copiedTerminalLogs
    agent_logs_copied     = $copiedAgentLogs
    final_balance         = $finalBalance
    test_duration         = $testDuration
    result_label          = $resultLabel
    restore_profile       = [bool]$RestoreMicrobotsProfile
}

$summary = [ordered]@{
    run_id                    = $runId
    symbol_alias              = $resolvedAlias
    symbol                    = $Symbol
    expert_name               = $ExpertName
    from_date                 = $FromDate
    to_date                   = $ToDate
    final_balance             = $finalBalance
    test_duration             = $testDuration
    result_label              = $resultLabel
    worker_name               = $workerToken
    evidence_dir              = $evidenceDir
    trust_state               = $summaryTrustState
    trust_reason              = $summaryTrustReason
    execution_quality_state   = $summaryExecutionQualityState
    cost_pressure_state       = $summaryCostPressureState
    market_regime             = $executionSummary.market_regime
    last_setup_type           = $executionSummary.last_setup_type
    learning_bias             = $executionSummary.learning_bias
    learning_sample_count     = [int]$executionSummary.learning_sample_count
    learning_win_count        = [int]$executionSummary.learning_win_count
    learning_loss_count       = [int]$executionSummary.learning_loss_count
    paper_open_rows           = $paperOpenRows
    paper_score_gate_rows     = $paperScoreGateRows
    accepted_evaluated_rows   = $acceptedEvaluatedRows
    score_below_trigger_rows  = $scoreBelowTriggerRows
    paper_conversion_ratio    = $conversionRatio
    realized_pnl_lifetime     = ($runtimeMap['realized_pnl_lifetime'])
    execution_summary_trust_state = $executionSummary.trust_state
    execution_summary_trust_reason = $executionSummary.trust_reason
    execution_summary_cost_pressure_state = $executionSummary.cost_pressure_state
    execution_summary_execution_quality_state = $executionSummary.execution_quality_state
    top_candidate_reasons     = $topCandidateReasons
    paper_open_by_setup_regime = $paperOpenBySetupRegime
    paper_close_stats         = $paperCloseStats
    deckhand_snapshot         = $deckhandSnapshot
    worst_buckets             = $worstBuckets
}

$jsonPath = Join-Path $evidenceDir ($runId + ".json")
$txtPath = Join-Path $evidenceDir ($runId + ".txt")
$summaryPath = Join-Path $evidenceDir ($runId + "_summary.json")
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$result | Out-String | Set-Content -LiteralPath $txtPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

if (-not $SkipKnowledgeExport) {
    & (Join-Path $ProjectRoot "TOOLS\EXPORT_STRATEGY_TESTER_KNOWLEDGE.ps1") `
        -ProjectRoot $ProjectRoot `
        -RunId $runId `
        -SymbolAlias $resolvedAlias `
        -EvidenceDir $evidenceDir `
        -SandboxRoot $sandboxRoot | Out-Null
}

$result
