param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$ReadinessReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_technical_readiness_latest.json",
    [string]$TerminalRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [string]$Period = "M1",
    [string]$FromDate = "2026.03.12",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 300,
    [switch]$ReuseLatestArtifacts,
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_first_wave_latest.json",
    [string]$LatestMarkdownPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_first_wave_latest.md",
    [string]$PilotRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_registry_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToolResultToObject {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }
        try {
            return ($text | ConvertFrom-Json -ErrorAction Stop)
        }
        catch {
            return [pscustomobject]@{ raw_output = $text }
        }
    }

    if ($Value -is [System.Array] -and $Value.Count -gt 0) {
        $joined = ($Value | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if (-not [string]::IsNullOrWhiteSpace($joined)) {
            try {
                return ($joined | ConvertFrom-Json -ErrorAction Stop)
            }
            catch {
                return [pscustomobject]@{ raw_output = $joined }
            }
        }
    }

    return $Value
}

function Get-FirstWaveSymbols {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Universe plan not found: $Path"
    }

    $plan = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $symbols = @($plan.paper_live_first_wave | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($symbols.Count -le 0) {
        throw "Universe plan has no paper_live_first_wave symbols."
    }

    return [pscustomobject]@{
        universe_version = [string]$plan.universe_version
        symbols = $symbols
    }
}

function Get-SymbolResolutionMap {
    param(
        [string]$RegistryPath,
        [string]$ReadinessReportPath
    )

    $registryMap = @{}
    if (Test-Path -LiteralPath $RegistryPath) {
        try {
            $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($item in @($registry.symbols)) {
                $alias = ([string]$item.symbol).ToUpperInvariant()
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                $registryMap[$alias] = $item
            }
        }
        catch {
        }
    }

    $readinessMap = @{}
    if (Test-Path -LiteralPath $ReadinessReportPath) {
        try {
            $report = Get-Content -LiteralPath $ReadinessReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($entry in @($report.entries)) {
                $alias = ([string]$entry.symbol_alias).ToUpperInvariant()
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                $readinessMap[$alias] = $entry
            }
        }
        catch {
        }
    }

    $resolutionMap = @{}
    foreach ($alias in @($registryMap.Keys + $readinessMap.Keys | Sort-Object -Unique)) {
        $registryEntry = if ($registryMap.ContainsKey($alias)) { $registryMap[$alias] } else { $null }
        $readinessEntry = if ($readinessMap.ContainsKey($alias)) { $readinessMap[$alias] } else { $null }
        $resolutionMap[$alias] = [pscustomobject]@{
            symbol_alias = $alias
            qdm_symbol = if ($null -ne $readinessEntry -and -not [string]::IsNullOrWhiteSpace([string]$readinessEntry.qdm_symbol)) { [string]$readinessEntry.qdm_symbol } else { $alias }
            broker_template_symbol = if ($null -ne $registryEntry -and -not [string]::IsNullOrWhiteSpace([string]$registryEntry.broker_symbol)) { [string]$registryEntry.broker_symbol } else { "{0}.pro" -f $alias }
            expert_code_symbol = if ($null -ne $registryEntry -and -not [string]::IsNullOrWhiteSpace([string]$registryEntry.code_symbol)) { [string]$registryEntry.code_symbol } else { $alias }
        }
    }

    return $resolutionMap
}

function Get-OptionalPropertyValue {
    param(
        [object]$Object,
        [string]$PropertyName,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        return $Object.$PropertyName
    }

    return $Default
}

function Get-LatestArtifactBackfillMap {
    param(
        [string]$PilotRegistryPath,
        [string]$ProjectRoot
    )

    $map = @{}

    if (Test-Path -LiteralPath $PilotRegistryPath) {
        try {
            $registry = Get-Content -LiteralPath $PilotRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($entry in @($registry.entries)) {
                $alias = ([string]$entry.symbol_alias).ToUpperInvariant()
                if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                $map[$alias] = $entry
            }
        }
        catch {
        }
    }

    $smokeDir = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER\qdm_custom_symbol_smoke"
    if (-not (Test-Path -LiteralPath $smokeDir)) {
        return $map
    }

    $summaryFiles = Get-ChildItem -LiteralPath $smokeDir -Filter "*_summary.json" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending
    foreach ($summaryFile in @($summaryFiles)) {
        try {
            $summary = Get-Content -LiteralPath $summaryFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $alias = ([string](Get-OptionalPropertyValue -Object $summary -PropertyName "symbol_alias" -Default "")).ToUpperInvariant()
            $runId = [string](Get-OptionalPropertyValue -Object $summary -PropertyName "run_id" -Default "")
            if ([string]::IsNullOrWhiteSpace($alias) -or [string]::IsNullOrWhiteSpace($runId)) {
                continue
            }

            $existing = if ($map.ContainsKey($alias)) { $map[$alias] } else { [pscustomobject]@{ symbol_alias = $alias } }
            $latestWriteUtc = if ($existing.PSObject.Properties.Name -contains "latest_summary_last_write_utc") {
                [datetime](Get-OptionalPropertyValue -Object $existing -PropertyName "latest_summary_last_write_utc" -Default ([datetime]::MinValue))
            } else {
                [datetime]::MinValue
            }

            if ($summaryFile.LastWriteTimeUtc -le $latestWriteUtc) {
                continue
            }

            $merged = [ordered]@{}
            foreach ($property in @($existing.PSObject.Properties)) {
                $merged[$property.Name] = $property.Value
            }
            $merged["symbol_alias"] = $alias
            $merged["last_run_id"] = $runId
            $merged["latest_summary_path"] = $summaryFile.FullName
            $merged["latest_summary_last_write_utc"] = $summaryFile.LastWriteTimeUtc.ToString("o")
            $map[$alias] = [pscustomobject]$merged
        }
        catch {
        }
    }

    return $map
}

function Build-BackfilledRunResult {
    param(
        [string]$ProjectRoot,
        [object]$RegistryEntry,
        [object]$Resolution
    )

    if ($null -eq $RegistryEntry) {
        return $null
    }

    $runId = [string]$RegistryEntry.last_run_id
    $smokeDir = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER\qdm_custom_symbol_smoke"
    $runPath = Join-Path $smokeDir ($runId + ".json")
    $summaryPath = Join-Path $smokeDir ($runId + "_summary.json")
    $run = $null
    $summary = $null

    if (Test-Path -LiteralPath $runPath) {
        try {
            $run = Get-Content -LiteralPath $runPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
        }
    }

    if (Test-Path -LiteralPath $summaryPath) {
        try {
            $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
        }
    }

    return [pscustomobject]@{
        schema_version = "1.0"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        symbol_alias = [string]$RegistryEntry.symbol_alias
        qdm_symbol = if ($null -ne $Resolution -and -not [string]::IsNullOrWhiteSpace([string]$Resolution.qdm_symbol)) { [string]$Resolution.qdm_symbol } else { [string]$RegistryEntry.qdm_symbol }
        export_name = [string]$RegistryEntry.export_name
        pilot_csv_path = [string]$RegistryEntry.pilot_csv_path
        custom_symbol = [string]$RegistryEntry.custom_symbol
        broker_template_symbol = if ($null -ne $Resolution) { [string]$Resolution.broker_template_symbol } else { $null }
        expert_code_symbol = if ($null -ne $Resolution) { [string]$Resolution.expert_code_symbol } else { [string]$RegistryEntry.symbol_alias }
        export = $null
        smoke = [pscustomobject]@{
            schema_version = "1.0"
            generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
            state = "backfilled"
            symbol_alias = [string]$RegistryEntry.symbol_alias
            expert_code_symbol = if ($null -ne $Resolution) { [string]$Resolution.expert_code_symbol } else { [string]$RegistryEntry.symbol_alias }
            expert_name = if ($null -ne $Resolution) { "MicroBot_{0}" -f ([string]$Resolution.expert_code_symbol).ToUpperInvariant() } else { "MicroBot_{0}" -f ([string]$RegistryEntry.symbol_alias).ToUpperInvariant() }
            pilot_csv_path = [string]$RegistryEntry.pilot_csv_path
            common_relative_csv_path = $null
            custom_symbol = [string]$RegistryEntry.custom_symbol
            broker_template_symbol = if ($null -ne $Resolution) { [string]$Resolution.broker_template_symbol } else { $null }
            import_status = "backfilled_from_registry"
            import_message = $(if ($null -ne $run) { Get-OptionalPropertyValue -Object $run -PropertyName "import_message" -Default (Get-OptionalPropertyValue -Object $RegistryEntry -PropertyName "import_message" -Default (Get-OptionalPropertyValue -Object $summary -PropertyName "import_message" -Default $null)) } else { Get-OptionalPropertyValue -Object $RegistryEntry -PropertyName "import_message" -Default (Get-OptionalPropertyValue -Object $summary -PropertyName "import_message" -Default $null) })
            property_mirror_message = $(if ($null -ne $run) { Get-OptionalPropertyValue -Object $run -PropertyName "property_mirror_message" -Default (Get-OptionalPropertyValue -Object $RegistryEntry -PropertyName "property_mirror_message" -Default (Get-OptionalPropertyValue -Object $summary -PropertyName "property_mirror_message" -Default $null)) } else { Get-OptionalPropertyValue -Object $RegistryEntry -PropertyName "property_mirror_message" -Default (Get-OptionalPropertyValue -Object $summary -PropertyName "property_mirror_message" -Default $null) })
            session_mirror_message = $(if ($null -ne $run) { Get-OptionalPropertyValue -Object $run -PropertyName "session_mirror_message" -Default (Get-OptionalPropertyValue -Object $RegistryEntry -PropertyName "session_mirror_message" -Default (Get-OptionalPropertyValue -Object $summary -PropertyName "session_mirror_message" -Default $null)) } else { Get-OptionalPropertyValue -Object $RegistryEntry -PropertyName "session_mirror_message" -Default (Get-OptionalPropertyValue -Object $summary -PropertyName "session_mirror_message" -Default $null) })
            tester_run_id = $runId
            requested_model = if ($null -ne $run) { Get-OptionalPropertyValue -Object $run -PropertyName "requested_model" -Default $RegistryEntry.requested_model } else { $RegistryEntry.requested_model }
            model = if ($null -ne $run) { Get-OptionalPropertyValue -Object $run -PropertyName "model" -Default $RegistryEntry.model } else { $RegistryEntry.model }
            model_normalized_for_qdm_custom_symbol = if ($null -ne $run) { Get-OptionalPropertyValue -Object $run -PropertyName "model_normalized_for_qdm_custom_symbol" -Default $RegistryEntry.model_normalized_for_qdm_custom_symbol } else { $RegistryEntry.model_normalized_for_qdm_custom_symbol }
            result_label = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "result_label" -Default $RegistryEntry.result_label } else { $RegistryEntry.result_label }
            final_balance = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "final_balance" -Default $RegistryEntry.final_balance } else { $RegistryEntry.final_balance }
            test_duration = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "test_duration" -Default $RegistryEntry.test_duration } else { $RegistryEntry.test_duration }
            evidence_dir = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "evidence_dir" -Default $null } else { $null }
            summary_path = if (Test-Path -LiteralPath $summaryPath) { $summaryPath } else { $null }
            trust_state = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "trust_state" -Default $null } else { $null }
            trust_reason = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "trust_reason" -Default $null } else { $null }
            observation_data_state = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "observation_data_state" -Default $null } else { $null }
            observation_data_reason = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "observation_data_reason" -Default $null } else { $null }
            paper_learning_state = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "paper_learning_state" -Default $null } else { $null }
            paper_open_rows = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "paper_open_rows" -Default $null } else { $null }
            paper_score_gate_rows = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "paper_score_gate_rows" -Default $null } else { $null }
            candidate_signal_rows_total = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "candidate_signal_rows_total" -Default $null } else { $null }
            onnx_observation_rows = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "onnx_observation_rows" -Default $null } else { $null }
            learning_observation_rows = if ($null -ne $summary) { Get-OptionalPropertyValue -Object $summary -PropertyName "learning_observation_rows" -Default $null } else { $null }
        }
        state = "completed"
    }
}

function New-ReportPayload {
    param(
        [string]$UniverseVersion,
        [string[]]$SelectedSymbols,
        [object[]]$Results,
        [string]$State,
        [string]$CurrentSymbol
    )

    $resultsArray = @($Results)
    $successful = @($resultsArray | Where-Object { $_.state -eq "completed" }).Count
    $failed = @($resultsArray | Where-Object { $_.state -ne "completed" }).Count

    return [pscustomobject]@{
        schema_version = "1.0"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        universe_version = $UniverseVersion
        symbol_scope = "paper_live_first_wave"
        selected_symbol_source = "paper_live_first_wave"
        selected_symbols = @($SelectedSymbols)
        current_symbol = $CurrentSymbol
        completed_symbols = @($resultsArray | ForEach-Object { $_.symbol_alias })
        successful_count = $successful
        failed_count = $failed
        state = $State
        results = $resultsArray
    }
}

function Write-MarkdownReport {
    param(
        [string]$Path,
        [object]$Payload
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# QDM Custom Symbol First Wave")
    $lines.Add("")
    $lines.Add(("- generated_at_utc: {0}" -f $Payload.generated_at_utc))
    $lines.Add(("- universe_version: {0}" -f $Payload.universe_version))
    $lines.Add(("- symbol_scope: {0}" -f $Payload.symbol_scope))
    $lines.Add(("- state: {0}" -f $Payload.state))
    $lines.Add(("- current_symbol: {0}" -f $Payload.current_symbol))
    $lines.Add(("- successful_count: {0}" -f $Payload.successful_count))
    $lines.Add(("- failed_count: {0}" -f $Payload.failed_count))
    $lines.Add("")
    $lines.Add("## Symbols")
    $lines.Add("")
    foreach ($entry in @($Payload.results)) {
        $lines.Add(("### {0}" -f $entry.symbol_alias))
        $lines.Add(("- state: {0}" -f $entry.state))
        $lines.Add(("- broker_template_symbol: {0}" -f $entry.broker_template_symbol))
        $lines.Add(("- qdm_symbol: {0}" -f $entry.qdm_symbol))
        if ($null -ne $entry.result) {
            $customSymbol = $entry.result.custom_symbol
            if (-not [string]::IsNullOrWhiteSpace([string]$customSymbol)) {
                $lines.Add(("- custom_symbol: {0}" -f $customSymbol))
            }
            $importMessage = $entry.result.smoke.import_message
            if (-not [string]::IsNullOrWhiteSpace([string]$importMessage)) {
                $lines.Add(("- import_message: {0}" -f $importMessage))
            }
            $propertyMirrorMessage = $entry.result.smoke.property_mirror_message
            if (-not [string]::IsNullOrWhiteSpace([string]$propertyMirrorMessage)) {
                $lines.Add(("- property_mirror_message: {0}" -f $propertyMirrorMessage))
            }
            $sessionMirrorMessage = $entry.result.smoke.session_mirror_message
            if (-not [string]::IsNullOrWhiteSpace([string]$sessionMirrorMessage)) {
                $lines.Add(("- session_mirror_message: {0}" -f $sessionMirrorMessage))
            }
            $resultLabel = $entry.result.smoke.result_label
            if (-not [string]::IsNullOrWhiteSpace([string]$resultLabel)) {
                $lines.Add(("- smoke_result: {0}" -f $resultLabel))
            }
            $trustState = $entry.result.smoke.trust_state
            if (-not [string]::IsNullOrWhiteSpace([string]$trustState)) {
                $lines.Add(("- trust: {0} / {1}" -f $trustState, $entry.result.smoke.trust_reason))
            }
            $observationState = $entry.result.smoke.observation_data_state
            if (-not [string]::IsNullOrWhiteSpace([string]$observationState)) {
                $lines.Add(("- observation_data_state: {0}" -f $observationState))
            }
            $paperLearningState = $entry.result.smoke.paper_learning_state
            if (-not [string]::IsNullOrWhiteSpace([string]$paperLearningState)) {
                $lines.Add(("- paper_learning_state: {0}" -f $paperLearningState))
            }
            if ($null -ne $entry.result.smoke.paper_open_rows) {
                $lines.Add(("- paper_open_rows: {0}" -f $entry.result.smoke.paper_open_rows))
            }
            if ($null -ne $entry.result.smoke.paper_score_gate_rows) {
                $lines.Add(("- paper_score_gate_rows: {0}" -f $entry.result.smoke.paper_score_gate_rows))
            }
            if ($null -ne $entry.result.smoke.candidate_signal_rows_total -or $null -ne $entry.result.smoke.onnx_observation_rows -or $null -ne $entry.result.smoke.learning_observation_rows) {
                $lines.Add(("- observation_rows candidate/onnx/learning: {0}/{1}/{2}" -f $entry.result.smoke.candidate_signal_rows_total, $entry.result.smoke.onnx_observation_rows, $entry.result.smoke.learning_observation_rows))
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.error)) {
            $lines.Add(("- error: {0}" -f $entry.error))
        }
        $lines.Add("")
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    ($lines -join "`r`n") | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Save-Report {
    param(
        [string]$JsonPath,
        [string]$MarkdownPath,
        [object]$Payload
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $JsonPath) | Out-Null
    $Payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $JsonPath -Encoding UTF8
    Write-MarkdownReport -Path $MarkdownPath -Payload $Payload
}

$pilotScript = Join-Path $ProjectRoot "RUN\RUN_QDM_CUSTOM_SYMBOL_PILOT.ps1"
if (-not (Test-Path -LiteralPath $pilotScript)) {
    throw "Required pilot script not found: $pilotScript"
}

$pwsh = (Get-Command powershell.exe -ErrorAction Stop).Source
$firstWave = Get-FirstWaveSymbols -Path $UniversePlanPath
$resolutionMap = Get-SymbolResolutionMap -RegistryPath $RegistryPath -ReadinessReportPath $ReadinessReportPath
$artifactBackfillMap = Get-LatestArtifactBackfillMap -PilotRegistryPath $PilotRegistryPath -ProjectRoot $ProjectRoot
$results = New-Object System.Collections.Generic.List[object]

$initialPayload = New-ReportPayload -UniverseVersion $firstWave.universe_version -SelectedSymbols $firstWave.symbols -Results @() -State "running" -CurrentSymbol ""
Save-Report -JsonPath $LatestStatusPath -MarkdownPath $LatestMarkdownPath -Payload $initialPayload

foreach ($symbolAlias in @($firstWave.symbols)) {
    $resolution = if ($resolutionMap.ContainsKey($symbolAlias)) { $resolutionMap[$symbolAlias] } else { $null }
    $resolvedQdmSymbol = if ($null -ne $resolution) { [string]$resolution.qdm_symbol } else { $symbolAlias }
    $resolvedBrokerTemplateSymbol = if ($null -ne $resolution) { [string]$resolution.broker_template_symbol } else { "{0}.pro" -f $symbolAlias }
    $resolvedExpertCodeSymbol = if ($null -ne $resolution) { [string]$resolution.expert_code_symbol } else { $symbolAlias }

    $runResult = $null
    $state = "completed"
    $errorMessage = $null

    if ($ReuseLatestArtifacts) {
        $registryEntry = if ($artifactBackfillMap.ContainsKey($symbolAlias)) { $artifactBackfillMap[$symbolAlias] } else { $null }
        $runResult = Build-BackfilledRunResult -ProjectRoot $ProjectRoot -RegistryEntry $registryEntry -Resolution $resolution
        if ($null -eq $runResult) {
            $state = "failed"
            $errorMessage = "no_existing_artifact_for_symbol"
        }
    }
    else {
        try {
            $raw = & $pwsh `
                -ExecutionPolicy Bypass `
                -File $pilotScript `
                -ProjectRoot $ProjectRoot `
                -SymbolAlias $symbolAlias `
                -QdmSymbol $resolvedQdmSymbol `
                -BrokerTemplateSymbol $resolvedBrokerTemplateSymbol `
                -ExpertCodeSymbol $resolvedExpertCodeSymbol `
                -Period $Period `
                -FromDate $FromDate `
                -ToDate $ToDate `
                -TerminalRoot $TerminalRoot `
                -TimeoutSec $TimeoutSec
            $exitCode = $LASTEXITCODE
            $runResult = Convert-ToolResultToObject -Value $raw
            if ($exitCode -ne 0) {
                $state = "failed"
                $errorMessage = "pilot_exit_code=$exitCode"
            }
        }
        catch {
            $state = "failed"
            $errorMessage = $_.Exception.Message
        }
    }

    $results.Add([pscustomobject]@{
        symbol_alias = $symbolAlias
        qdm_symbol = $resolvedQdmSymbol
        broker_template_symbol = $resolvedBrokerTemplateSymbol
        expert_code_symbol = $resolvedExpertCodeSymbol
        state = $state
        error = $errorMessage
        result = $runResult
    }) | Out-Null

    $progressPayload = New-ReportPayload -UniverseVersion $firstWave.universe_version -SelectedSymbols $firstWave.symbols -Results $results.ToArray() -State "running" -CurrentSymbol $symbolAlias
    Save-Report -JsonPath $LatestStatusPath -MarkdownPath $LatestMarkdownPath -Payload $progressPayload
}

$finalState = if (@($results.ToArray() | Where-Object { $_.state -ne "completed" }).Count -gt 0) {
    "completed_with_failures"
}
else {
    "completed"
}
$finalPayload = New-ReportPayload -UniverseVersion $firstWave.universe_version -SelectedSymbols $firstWave.symbols -Results $results.ToArray() -State $finalState -CurrentSymbol ""
Save-Report -JsonPath $LatestStatusPath -MarkdownPath $LatestMarkdownPath -Payload $finalPayload

$finalPayload | ConvertTo-Json -Depth 12
