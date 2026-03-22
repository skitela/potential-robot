param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$SymbolAlias = "NZDUSD",
    [string]$QdmSymbol = "NZDUSD",
    [string]$BrokerTemplateSymbol = "NZDUSD.pro",
    [string]$Period = "M1",
    [string]$FromDate = "2026.03.12",
    [string]$ToDate = "2026.03.16",
    [string]$TerminalRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [int]$TimeoutSec = 300,
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_run_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-SafeObjectValue {
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

function Get-CsvRowCount {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    $lineCount = [int]((Get-Content -LiteralPath $Path -Encoding UTF8 | Measure-Object -Line).Lines)
    return [Math]::Max($lineCount - 1, 0)
}

function Update-QdmPilotRegistry {
    param(
        [string]$ProjectRoot,
        [object]$CurrentResult
    )

    $opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
    $registryJsonPath = Join-Path $opsRoot "qdm_custom_symbol_pilot_registry_latest.json"
    $registryMdPath = Join-Path $opsRoot "qdm_custom_symbol_pilot_registry_latest.md"
    $smokeDir = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER\qdm_custom_symbol_smoke"
    $entriesBySymbol = [ordered]@{}

    $existingRegistry = Read-JsonFile -Path $registryJsonPath
    if ($null -ne $existingRegistry -and $existingRegistry.PSObject.Properties.Name -contains "entries") {
        foreach ($entry in @($existingRegistry.entries)) {
            $symbolKey = [string](Get-SafeObjectValue -Object $entry -PropertyName "symbol_alias" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($symbolKey)) {
                $entriesBySymbol[$symbolKey.ToUpperInvariant()] = [ordered]@{
                    symbol_alias = $entry.symbol_alias
                    qdm_symbol = $entry.qdm_symbol
                    custom_symbol = $entry.custom_symbol
                    export_name = $entry.export_name
                    pilot_csv_path = $entry.pilot_csv_path
                    pilot_csv_present = $entry.pilot_csv_present
                    pilot_row_count = $entry.pilot_row_count
                    last_run_id = $entry.last_run_id
                    result_label = $entry.result_label
                    final_balance = $entry.final_balance
                    test_duration = $entry.test_duration
                    requested_model = $entry.requested_model
                    model = $entry.model
                    model_normalized_for_qdm_custom_symbol = $entry.model_normalized_for_qdm_custom_symbol
                    last_write_local = $entry.last_write_local
                    source = $entry.source
                }
            }
        }
    }

    if (Test-Path -LiteralPath $smokeDir) {
        $summaryFiles = Get-ChildItem -LiteralPath $smokeDir -File -Filter "*_summary.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc
        foreach ($summaryFile in $summaryFiles) {
            $summary = Read-JsonFile -Path $summaryFile.FullName
            if ($null -eq $summary) {
                continue
            }

            $runBaseName = [System.IO.Path]::GetFileNameWithoutExtension($summaryFile.Name) -replace "_summary$",""
            $runPath = Join-Path $smokeDir ($runBaseName + ".json")
            $run = Read-JsonFile -Path $runPath
            $customSymbol = [string](Get-SafeObjectValue -Object $summary -PropertyName "symbol" -Default "")
            $symbolAlias = if ($customSymbol -like "*_QDM_M1") { $customSymbol -replace "_QDM_M1$","" } else { [string](Get-SafeObjectValue -Object $summary -PropertyName "symbol_alias" -Default "") }
            if ([string]::IsNullOrWhiteSpace($symbolAlias)) {
                continue
            }

            $symbolKey = $symbolAlias.ToUpperInvariant()
            $exportName = "MB_{0}_DUKA_M1_PILOT" -f $symbolKey
            $pilotCsvPath = Join-Path $ProjectRoot ("EVIDENCE\QDM_PILOT\{0}.csv" -f $exportName)

            $entriesBySymbol[$symbolKey] = [ordered]@{
                symbol_alias = $symbolKey
                qdm_symbol = $symbolKey
                custom_symbol = $customSymbol
                export_name = $exportName
                pilot_csv_path = $pilotCsvPath
                pilot_csv_present = (Test-Path -LiteralPath $pilotCsvPath)
                pilot_row_count = (Get-CsvRowCount -Path $pilotCsvPath)
                last_run_id = (Get-SafeObjectValue -Object $summary -PropertyName "run_id" -Default $runBaseName)
                result_label = (Get-SafeObjectValue -Object $summary -PropertyName "result_label" -Default $null)
                final_balance = (Get-SafeObjectValue -Object $summary -PropertyName "final_balance" -Default $null)
                test_duration = (Get-SafeObjectValue -Object $summary -PropertyName "test_duration" -Default $null)
                requested_model = (Get-SafeObjectValue -Object $run -PropertyName "requested_model" -Default $null)
                model = (Get-SafeObjectValue -Object $run -PropertyName "model" -Default $null)
                model_normalized_for_qdm_custom_symbol = (Get-SafeObjectValue -Object $run -PropertyName "model_normalized_for_qdm_custom_symbol" -Default $false)
                last_write_local = $summaryFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                source = "smoke_backfill"
            }
        }
    }

    if ($null -ne $CurrentResult) {
        $symbolKey = ([string]$CurrentResult.symbol_alias).ToUpperInvariant()
        $entriesBySymbol[$symbolKey] = [ordered]@{
            symbol_alias = $symbolKey
            qdm_symbol = $CurrentResult.qdm_symbol
            custom_symbol = $CurrentResult.custom_symbol
            export_name = $CurrentResult.export_name
            pilot_csv_path = $CurrentResult.pilot_csv_path
            pilot_csv_present = (Test-Path -LiteralPath $CurrentResult.pilot_csv_path)
            pilot_row_count = [int](Get-SafeObjectValue -Object $CurrentResult.export -PropertyName "row_count" -Default (Get-CsvRowCount -Path $CurrentResult.pilot_csv_path))
            last_run_id = (Get-SafeObjectValue -Object $CurrentResult.smoke -PropertyName "tester_run_id" -Default $null)
            result_label = (Get-SafeObjectValue -Object $CurrentResult.smoke -PropertyName "result_label" -Default $null)
            final_balance = (Get-SafeObjectValue -Object $CurrentResult.smoke -PropertyName "final_balance" -Default $null)
            test_duration = (Get-SafeObjectValue -Object $CurrentResult.smoke -PropertyName "test_duration" -Default $null)
            requested_model = (Get-SafeObjectValue -Object $CurrentResult.smoke -PropertyName "requested_model" -Default $null)
            model = (Get-SafeObjectValue -Object $CurrentResult.smoke -PropertyName "model" -Default $null)
            model_normalized_for_qdm_custom_symbol = (Get-SafeObjectValue -Object $CurrentResult.smoke -PropertyName "model_normalized_for_qdm_custom_symbol" -Default $false)
            last_write_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            source = "current_run"
        }
    }

    $entries = @(
        $entriesBySymbol.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object { [pscustomobject]$_.Value }
    )

    $registry = [ordered]@{
        schema_version = "1.0"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        total_symbols = @($entries).Count
        successful_smokes = @($entries | Where-Object { [string]$_.result_label -eq "successfully_finished" }).Count
        normalized_models = @($entries | Where-Object { $_.model_normalized_for_qdm_custom_symbol -eq $true }).Count
        symbols = @($entries.symbol_alias)
        entries = $entries
    }

    New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null
    $registry | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registryJsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# QDM Custom Symbol Pilot Registry")
    $lines.Add("")
    $lines.Add(("- generated_at_utc: {0}" -f $registry.generated_at_utc))
    $lines.Add(("- total_symbols: {0}" -f $registry.total_symbols))
    $lines.Add(("- successful_smokes: {0}" -f $registry.successful_smokes))
    $lines.Add(("- normalized_models: {0}" -f $registry.normalized_models))
    $lines.Add("")
    foreach ($entry in $entries) {
        $lines.Add(("## {0}" -f $entry.symbol_alias))
        $lines.Add(("- custom_symbol: {0}" -f $entry.custom_symbol))
        $lines.Add(("- pilot_row_count: {0}" -f $entry.pilot_row_count))
        $lines.Add(("- result_label: {0}" -f $entry.result_label))
        $lines.Add(("- final_balance: {0}" -f $entry.final_balance))
        $lines.Add(("- test_duration: {0}" -f $entry.test_duration))
        $lines.Add(("- normalized_model: {0}" -f $entry.model_normalized_for_qdm_custom_symbol))
        $lines.Add(("- last_run_id: {0}" -f $entry.last_run_id))
        $lines.Add(("- source: {0}" -f $entry.source))
        $lines.Add("")
    }
    ($lines -join "`r`n") | Set-Content -LiteralPath $registryMdPath -Encoding UTF8
}

$normalizedAlias = $SymbolAlias.ToUpperInvariant()
$exportName = "MB_{0}_DUKA_M1_PILOT" -f $normalizedAlias
$pilotCsvPath = Join-Path $ProjectRoot ("EVIDENCE\QDM_PILOT\{0}.csv" -f $exportName)
$commonRelativeCsvPath = "MAKRO_I_MIKRO_BOT\\qdm_import\\{0}.csv" -f $exportName
$customSymbol = "{0}_QDM_M1" -f $normalizedAlias

$exportScript = Join-Path $ProjectRoot "RUN\EXPORT_QDM_PILOT_SYMBOL_TO_MT5.ps1"
$smokeScript = Join-Path $ProjectRoot "RUN\RUN_QDM_CUSTOM_SYMBOL_SMOKE.ps1"

foreach ($path in @($exportScript, $smokeScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$pwsh = (Get-Command powershell.exe -ErrorAction Stop).Source

$exportArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $exportScript,
    "-ProjectRoot", $ProjectRoot,
    "-QdmSymbol", $QdmSymbol,
    "-ExportName", $exportName,
    "-Timeframe", $Period,
    "-DateFrom", $FromDate,
    "-DateTo", $ToDate
)

$exportResult = & $pwsh @exportArgs
$exportExitCode = $LASTEXITCODE
if ($exportExitCode -ne 0) {
    throw "QDM pilot export failed for $QdmSymbol"
}

$smokeArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $smokeScript,
    "-ProjectRoot", $ProjectRoot,
    "-TerminalRoot", $TerminalRoot,
    "-SymbolAlias", $normalizedAlias,
    "-PilotCsvPath", $pilotCsvPath,
    "-CommonRelativeCsvPath", $commonRelativeCsvPath,
    "-CustomSymbol", $customSymbol,
    "-BrokerTemplateSymbol", $BrokerTemplateSymbol,
    "-Period", $Period,
    "-FromDate", $FromDate,
    "-ToDate", $ToDate,
    "-TimeoutSec", $TimeoutSec
)

$smokeResult = & $pwsh @smokeArgs
$smokeExitCode = $LASTEXITCODE
if ($smokeExitCode -ne 0) {
    throw "QDM custom symbol smoke failed for $customSymbol"
}

$exportObject = $null
$smokeObject = $null
try { $exportObject = $exportResult | ConvertFrom-Json -ErrorAction Stop } catch {}
try { $smokeObject = $smokeResult | ConvertFrom-Json -ErrorAction Stop } catch {}

$result = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    symbol_alias = $normalizedAlias
    qdm_symbol = $QdmSymbol
    export_name = $exportName
    pilot_csv_path = $pilotCsvPath
    custom_symbol = $customSymbol
    broker_template_symbol = $BrokerTemplateSymbol
    export = $exportObject
    smoke = $smokeObject
    state = "completed"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8

Update-QdmPilotRegistry -ProjectRoot $ProjectRoot -CurrentResult $result

$result | ConvertTo-Json -Depth 8
