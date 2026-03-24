param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-FileAgeSecondsOrMax {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int]::MaxValue
    }

    return [int][math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds)
}

function Get-ExportProcessCount {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "python.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*EXPORT_MT5_RESEARCH_DATA.py*"
            }
    ).Count
}

function Get-OptionalValue {
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

function New-Finding {
    param(
        [string]$Severity,
        [string]$Component,
        [string]$Message,
        [hashtable]$Context = @{}
    )

    return [pscustomobject]@{
        severity = $Severity
        component = $Component
        message = $Message
        context = $Context
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$researchManifestPath = Join-Path $ResearchRoot "reports\research_export_manifest_latest.json"
$contractManifestPath = Join-Path $ResearchRoot "reports\research_contract_manifest_latest.json"
$paperRuntimePath = Join-Path $ProjectRoot "EVIDENCE\OPS\learning_paper_runtime_plan_latest.json"
$reportJsonPath = Join-Path $OutputRoot "learning_data_contract_audit_latest.json"
$reportMdPath = Join-Path $OutputRoot "learning_data_contract_audit_latest.md"

$researchManifest = Read-JsonFile -Path $researchManifestPath
$contractManifest = Read-JsonFile -Path $contractManifestPath
$paperRuntime = Read-JsonFile -Path $paperRuntimePath

$findings = New-Object System.Collections.Generic.List[object]
$items = New-Object System.Collections.Generic.List[object]

$contractFresh = (Get-FileAgeSecondsOrMax -Path $contractManifestPath) -le 1800
$researchFresh = (Get-FileAgeSecondsOrMax -Path $researchManifestPath) -le 1800
$researchManifestTime = if (Test-Path -LiteralPath $researchManifestPath) { (Get-Item -LiteralPath $researchManifestPath).LastWriteTime } else { Get-Date "1900-01-01" }
$manifestBehindSourceCount = 0

if ($null -eq $researchManifest) {
    $findings.Add((New-Finding -Severity "high" -Component "research_manifest" -Message "Brak manifestu eksportu research.")) | Out-Null
}
if ($null -eq $contractManifest) {
    $findings.Add((New-Finding -Severity "high" -Component "contract_manifest" -Message "Brak manifestu kontraktu danych uczenia.")) | Out-Null
}

$expected = @(
    @{
        raw = "onnx_observations"
        normalized = "onnx_observations_norm"
        required_columns = @("ts", "symbol_alias", "feedback_key", "runtime_channel", "available", "reason_code")
    },
    @{
        raw = "candidate_signals"
        normalized = "candidate_signals_norm"
        required_columns = @("ts", "symbol_alias", "feedback_key", "outcome_key", "accepted", "side")
    },
    @{
        raw = "learning_observations_v2"
        normalized = "learning_observations_v2_norm"
        required_columns = @("ts", "symbol_alias", "outcome_key", "pnl", "side", "close_reason")
    }
)

foreach ($entry in $expected) {
    $rawItem = Get-OptionalValue -Object (Get-OptionalValue -Object $researchManifest -Name "datasets" -Default $null) -Name $entry.raw -Default $null
    $contractItem = Get-OptionalValue -Object (Get-OptionalValue -Object $contractManifest -Name "items" -Default $null) -Name $entry.normalized -Default $null

    $manifestRows = [int](Get-OptionalValue -Object $rawItem -Name "rows" -Default 0)
    $rawRows = [int](Get-OptionalValue -Object $contractItem -Name "source_rows" -Default $manifestRows)
    $contractRows = [int](Get-OptionalValue -Object $contractItem -Name "rows" -Default 0)
    $contractPath = [string](Get-OptionalValue -Object $contractItem -Name "path" -Default "")
    $filteredOutRows = [int](Get-OptionalValue -Object $contractItem -Name "filtered_out_rows" -Default ([Math]::Max(0, $rawRows - $contractRows)))
    $sourceParquetPath = Join-Path $ResearchRoot ("datasets\{0}_latest.parquet" -f $entry.raw)
    $schema = @((Get-OptionalValue -Object $contractItem -Name "schema" -Default @()))
    $schemaNames = @($schema | ForEach-Object { [string]$_.name })
    $missingColumns = @($entry.required_columns | Where-Object { $schemaNames -notcontains $_ })
    $contractExists = (-not [string]::IsNullOrWhiteSpace($contractPath) -and (Test-Path -LiteralPath $contractPath))
    $manifestBehindSource = (
        ((Test-Path -LiteralPath $sourceParquetPath) -and ((Get-Item -LiteralPath $sourceParquetPath).LastWriteTime -gt $researchManifestTime)) -or
        ($manifestRows -gt 0 -and $rawRows -gt 0 -and $manifestRows -ne $rawRows)
    )

    $item = [pscustomobject]@{
        raw_table = $entry.raw
        normalized_table = $entry.normalized
        manifest_rows = $manifestRows
        raw_rows = $rawRows
        contract_rows = $contractRows
        filtered_out_rows = $filteredOutRows
        contract_exists = $contractExists
        source_parquet_path = $sourceParquetPath
        manifest_behind_source = $manifestBehindSource
        missing_columns = @($missingColumns)
        schema_column_count = $schemaNames.Count
        status = "OK"
    }

    if (-not $contractExists) {
        $item.status = "BRAK_PLIKU"
        $findings.Add((New-Finding -Severity "high" -Component $entry.normalized -Message "Brak pliku kanonicznego kontraktu danych." -Context @{
            normalized_table = $entry.normalized
            path = $contractPath
        })) | Out-Null
    }
    elseif ($rawRows -gt 0 -and $contractRows -le 0) {
        $item.status = "PUSTY_KONTRAKT"
        $findings.Add((New-Finding -Severity "high" -Component $entry.normalized -Message "Surowe dane istnieja, ale kontrakt kanoniczny jest pusty." -Context @{
            raw_rows = $rawRows
            contract_rows = $contractRows
        })) | Out-Null
    }
    elseif ($missingColumns.Count -gt 0) {
        $item.status = "BRAK_KOLUMN"
        $findings.Add((New-Finding -Severity "high" -Component $entry.normalized -Message "Kontrakt danych nie ma wszystkich wymaganych kolumn." -Context @{
            missing_columns = $missingColumns
        })) | Out-Null
    }
    elseif ($contractRows -gt $rawRows -and $rawRows -gt 0) {
        $item.status = "NADMIAR_WIERSZY"
        $findings.Add((New-Finding -Severity "medium" -Component $entry.normalized -Message "Kontrakt ma wiecej wierszy niz surowe dane i wymaga inspekcji." -Context @{
            raw_rows = $rawRows
            contract_rows = $contractRows
        })) | Out-Null
    }
    elseif ($filteredOutRows -gt 0) {
        $item.status = "OK_PRZEFILTROWANE"
    }

    if ($manifestBehindSource) {
        $manifestBehindSourceCount++
    }

    $items.Add($item) | Out-Null
}

$runtimeActive = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $paperRuntime -Name "summary" -Default $null) -Name "symbols_runtime_active" -Default 0)
if ($runtimeActive -gt 0 -and -not $contractFresh) {
    $findings.Add((New-Finding -Severity "medium" -Component "contract_freshness" -Message "Runtime ONNX jest aktywny, ale kontrakt danych nie jest swiezy." -Context @{
        runtime_active_symbols = $runtimeActive
        contract_age_seconds = Get-FileAgeSecondsOrMax -Path $contractManifestPath
    })) | Out-Null
}

if (-not $researchFresh) {
    $findings.Add((New-Finding -Severity "medium" -Component "research_freshness" -Message "Manifest eksportu research nie jest swiezy." -Context @{
        age_seconds = Get-FileAgeSecondsOrMax -Path $researchManifestPath
    })) | Out-Null
}
if ($manifestBehindSourceCount -gt 0) {
    $exportActive = (Get-ExportProcessCount) -gt 0
    $findings.Add((New-Finding -Severity $(if ($exportActive) { "low" } else { "medium" }) -Component "research_manifest_alignment" -Message $(if ($exportActive) {
        "Parquety sa nowsze niz manifest research, ale eksport jest aktywny i powinien domknac opis zrodla."
    } else {
        "Czesc parquetow jest nowsza niz manifest research; najpierw trzeba odswiezyc opis zrodla."
    }) -Context @{
        manifest_behind_source_count = $manifestBehindSourceCount
        export_active = $exportActive
    })) | Out-Null
}

$highCount = @($findings | Where-Object { $_.severity -eq "high" }).Count
$mediumCount = @($findings | Where-Object { $_.severity -eq "medium" }).Count
$verdict = if ($highCount -gt 0) { "NAPRAW_W_CYKLU" } elseif ($mediumCount -gt 0) { "UWAZAJ" } else { "OK" }
$tablesReady = 0
foreach ($item in $items) {
    if ([string]$item.status -in @("OK", "OK_PRZEFILTROWANE")) {
        $tablesReady++
    }
}

$itemsArray = [object[]]$items.ToArray()
$findingsArray = [object[]]$findings.ToArray()

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    research_manifest_path = $researchManifestPath
    contract_manifest_path = $contractManifestPath
    verdict = $verdict
    summary = [ordered]@{
        findings_total = $findings.Count
        high = $highCount
        medium = $mediumCount
        contract_fresh = $contractFresh
        research_fresh = $researchFresh
        runtime_active_symbols = $runtimeActive
        tables_checked = $items.Count
        tables_ready = $tablesReady
        contract_version = [string](Get-OptionalValue -Object $contractManifest -Name "contract_version" -Default "")
    }
    items = $itemsArray
    findings = $findingsArray
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportJsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Audyt Kontraktu Danych Uczenia") | Out-Null
$lines.Add("") | Out-Null
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local)) | Out-Null
$lines.Add(("- werdykt: {0}" -f $report.verdict)) | Out-Null
$lines.Add(("- contract_fresh: {0}" -f $report.summary.contract_fresh)) | Out-Null
$lines.Add(("- research_fresh: {0}" -f $report.summary.research_fresh)) | Out-Null
$lines.Add(("- runtime_active_symbols: {0}" -f $report.summary.runtime_active_symbols)) | Out-Null
$lines.Add(("- tables_ready: {0}/{1}" -f $report.summary.tables_ready, $report.summary.tables_checked)) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Tabele") | Out-Null
$lines.Add("") | Out-Null
foreach ($item in $itemsArray) {
    $lines.Add(("### {0}" -f $item.normalized_table)) | Out-Null
    $lines.Add(("- status: {0}" -f $item.status)) | Out-Null
    $lines.Add(("- raw_rows: {0}" -f $item.raw_rows)) | Out-Null
    $lines.Add(("- contract_rows: {0}" -f $item.contract_rows)) | Out-Null
    $lines.Add(("- contract_exists: {0}" -f $item.contract_exists)) | Out-Null
    if (@($item.missing_columns).Count -gt 0) {
        $lines.Add(("- missing_columns: {0}" -f ((@($item.missing_columns)) -join ", "))) | Out-Null
    }
    $lines.Add("") | Out-Null
}

if ($findingsArray.Count -gt 0) {
    $lines.Add("## Znaleziska") | Out-Null
    $lines.Add("") | Out-Null
    foreach ($finding in $findingsArray) {
        $lines.Add(("- [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message)) | Out-Null
    }
}

$lines | Set-Content -LiteralPath $reportMdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
