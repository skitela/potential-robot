param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [string]$SymbolAlias = "EURUSD",
    [string]$ExpertCodeSymbol = "",
    [string]$PilotCsvPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\QDM_PILOT\MB_EURUSD_DUKA_M1_PILOT.csv",
    [string]$CommonRelativeCsvPath = "MAKRO_I_MIKRO_BOT\\qdm_import\\MB_EURUSD_DUKA_M1_PILOT.csv",
    [string]$CustomSymbol = "EURUSD_QDM_M1",
    [string]$BrokerTemplateSymbol = "EURUSD.pro",
    [string]$Period = "M1",
    [string]$FromDate = "2026.03.12",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 300,
    [string]$EvidenceSubdir = "qdm_custom_symbol_smoke",
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_smoke_latest.json",
    [switch]$ExportKnowledge
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
            }
        }
    }

    return $Value
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

function Read-JsonFileSafe {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

$importScript = Join-Path $ProjectRoot "RUN\IMPORT_QDM_PILOT_CUSTOM_SYMBOL.ps1"
$testerScript = Join-Path $ProjectRoot "TOOLS\RUN_MICROBOT_STRATEGY_TESTER.ps1"

foreach ($path in @($importScript, $testerScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$mt5Exe = Join-Path $TerminalRoot "terminal64.exe"
if (-not (Test-Path -LiteralPath $mt5Exe)) {
    throw "MT5 executable not found: $mt5Exe"
}

$importResult = Convert-ToolResultToObject (& $importScript `
    -ProjectRoot $ProjectRoot `
    -UseDedicatedPortableLabLane $true `
    -DedicatedLabTerminalRoot $TerminalRoot `
    -PilotCsvPath $PilotCsvPath `
    -CommonRelativeCsvPath $CommonRelativeCsvPath `
    -CustomSymbol $CustomSymbol `
    -BrokerTemplateSymbol $BrokerTemplateSymbol)

if ($null -eq $importResult) {
    throw "QDM custom symbol import returned no result."
}

if (-not [bool]$importResult.import_succeeded) {
    $result = [ordered]@{
        schema_version = "1.0"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        state = "import_failed"
        symbol_alias = $SymbolAlias
        custom_symbol = $CustomSymbol
        import_status = $importResult.run_status
        import_message = $importResult.import_message
        import_status_path = $importResult.PSObject.Properties['run_config_path'].Value
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 6
    exit 1
}

$resolvedExpertCodeSymbol = if ([string]::IsNullOrWhiteSpace($ExpertCodeSymbol)) { $SymbolAlias } else { $ExpertCodeSymbol }
$expertName = "MicroBot_{0}" -f $resolvedExpertCodeSymbol.ToUpperInvariant()
$testerResult = Convert-ToolResultToObject (& $testerScript `
    -ProjectRoot $ProjectRoot `
    -Mt5Exe $mt5Exe `
    -TerminalDataDir $TerminalRoot `
    -PortableTerminal `
    -SymbolAlias $SymbolAlias `
    -Symbol $CustomSymbol `
    -ExpertName $expertName `
    -Period $Period `
    -FromDate $FromDate `
    -ToDate $ToDate `
    -TimeoutSec $TimeoutSec `
    -EvidenceSubdir $EvidenceSubdir `
    -SkipKnowledgeExport:(!$ExportKnowledge) `
    -SkipResearchRefresh)

if ($null -eq $testerResult) {
    throw "QDM custom symbol smoke tester returned no result."
}

$testerRunId = [string]$testerResult.run_id
$smokeEvidenceDir = Get-OptionalPropertyValue -Object $testerResult -PropertyName "evidence_dir" -Default (Join-Path $ProjectRoot ("EVIDENCE\\STRATEGY_TESTER\\{0}" -f $EvidenceSubdir))
$smokeJsonPath = Get-OptionalPropertyValue -Object $testerResult -PropertyName "json_path" -Default $(if (-not [string]::IsNullOrWhiteSpace($testerRunId)) { Join-Path $smokeEvidenceDir ($testerRunId + ".json") } else { $null })
$smokeSummaryPath = Get-OptionalPropertyValue -Object $testerResult -PropertyName "summary_path" -Default $(if (-not [string]::IsNullOrWhiteSpace($testerRunId)) { Join-Path $smokeEvidenceDir ($testerRunId + "_summary.json") } else { $null })
$testerJson = Read-JsonFileSafe -Path $smokeJsonPath
$testerSummary = Read-JsonFileSafe -Path $smokeSummaryPath
$testerState = [string](Get-OptionalPropertyValue -Object $testerResult -PropertyName "state" -Default "completed")

function Get-TesterField {
    param(
        [string]$PropertyName,
        $Default = $null
    )

    $value = Get-OptionalPropertyValue -Object $testerResult -PropertyName $PropertyName -Default $null
    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
        return $value
    }

    $value = Get-OptionalPropertyValue -Object $testerSummary -PropertyName $PropertyName -Default $null
    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
        return $value
    }

    $value = Get-OptionalPropertyValue -Object $testerJson -PropertyName $PropertyName -Default $null
    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
        return $value
    }

    return $Default
}

$result = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    state = $testerState
    symbol_alias = $SymbolAlias
    expert_code_symbol = $resolvedExpertCodeSymbol
    expert_name = $expertName
    pilot_csv_path = $PilotCsvPath
    common_relative_csv_path = $CommonRelativeCsvPath
    custom_symbol = $CustomSymbol
    broker_template_symbol = $BrokerTemplateSymbol
    import_status = $importResult.run_status
    import_message = $importResult.import_message
    property_mirror_message = (Get-OptionalPropertyValue -Object $importResult -PropertyName "property_mirror_message")
    session_mirror_message = (Get-OptionalPropertyValue -Object $importResult -PropertyName "session_mirror_message")
    tester_run_id = $testerRunId
    requested_model = $testerResult.requested_model
    model = $testerResult.model
    model_normalized_for_qdm_custom_symbol = $testerResult.model_normalized_for_qdm_custom_symbol
    result_label = $testerResult.result_label
    final_balance = $testerResult.final_balance
    test_duration = $testerResult.test_duration
    evidence_dir = $smokeEvidenceDir
    summary_path = $smokeSummaryPath
    json_path = $smokeJsonPath
    knowledge_json_path = Get-TesterField -PropertyName "knowledge_json_path"
    knowledge_markdown_path = Get-TesterField -PropertyName "knowledge_markdown_path"
    trust_state = Get-TesterField -PropertyName "trust_state"
    trust_reason = Get-TesterField -PropertyName "trust_reason"
    learning_sample_count = Get-TesterField -PropertyName "learning_sample_count"
    candidate_signal_rows_total = Get-TesterField -PropertyName "candidate_signal_rows_total"
    onnx_observation_rows = Get-TesterField -PropertyName "onnx_observation_rows"
    learning_observation_rows = Get-TesterField -PropertyName "learning_observation_rows"
    paper_open_rows = Get-TesterField -PropertyName "paper_open_rows"
    paper_score_gate_rows = Get-TesterField -PropertyName "paper_score_gate_rows"
    accepted_evaluated_rows = Get-TesterField -PropertyName "accepted_evaluated_rows"
    observation_infra_ready = Get-TesterField -PropertyName "observation_infra_ready"
    observation_data_state = Get-TesterField -PropertyName "observation_data_state"
    observation_data_reason = Get-TesterField -PropertyName "observation_data_reason"
    paper_learning_state = Get-TesterField -PropertyName "paper_learning_state"
    compile_ok = Get-TesterField -PropertyName "compile_ok"
    compile_log = Get-TesterField -PropertyName "compile_log"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
$result | ConvertTo-Json -Depth 6
