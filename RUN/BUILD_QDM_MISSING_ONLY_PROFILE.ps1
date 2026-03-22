param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$OutputPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_missing_only_pack.csv",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [string]$BlockedSymbolsPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_missing_only_blocked.json",
    [long]$MinimumHistoryBytes = 10485760
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-QdmSpec {
    param([string]$Alias)

    if ([string]::IsNullOrWhiteSpace($Alias)) { return $null }

    switch ($Alias.Trim().ToUpperInvariant()) {
        "EURUSD" { return [pscustomobject]@{ supported = $true; symbol = "EURUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_EURUSD_DUKA"; notes = "registry_fx" } }
        "AUDUSD" { return [pscustomobject]@{ supported = $true; symbol = "AUDUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_AUDUSD_DUKA"; notes = "registry_fx" } }
        "GBPUSD" { return [pscustomobject]@{ supported = $true; symbol = "GBPUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_GBPUSD_DUKA"; notes = "registry_fx" } }
        "USDJPY" { return [pscustomobject]@{ supported = $true; symbol = "USDJPY"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_USDJPY_DUKA"; notes = "registry_fx" } }
        "USDCAD" { return [pscustomobject]@{ supported = $true; symbol = "USDCAD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_USDCAD_DUKA"; notes = "registry_fx" } }
        "USDCHF" { return [pscustomobject]@{ supported = $true; symbol = "USDCHF"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_USDCHF_DUKA"; notes = "registry_fx" } }
        "NZDUSD" { return [pscustomobject]@{ supported = $true; symbol = "NZDUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_NZDUSD_DUKA"; notes = "registry_fx" } }
        "EURJPY" { return [pscustomobject]@{ supported = $true; symbol = "EURJPY"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_EURJPY_DUKA"; notes = "registry_fx" } }
        "GBPJPY" { return [pscustomobject]@{ supported = $true; symbol = "GBPJPY"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_GBPJPY_DUKA"; notes = "registry_fx" } }
        "EURAUD" { return [pscustomobject]@{ supported = $true; symbol = "EURAUD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_EURAUD_DUKA"; notes = "registry_fx" } }
        "GBPAUD" { return [pscustomobject]@{ supported = $true; symbol = "GBPAUD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2016.01.01"; date_to = ""; mt5_export_name = "MB_GBPAUD_DUKA"; notes = "registry_fx" } }
        "GOLD" { return [pscustomobject]@{ supported = $true; symbol = "XAUUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2018.01.01"; date_to = ""; mt5_export_name = "MB_GOLD_DUKA"; notes = "registry_metals" } }
        "SILVER" { return [pscustomobject]@{ supported = $true; symbol = "XAGUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2018.01.01"; date_to = ""; mt5_export_name = "MB_SILVER_DUKA"; notes = "registry_metals" } }
        "DE30" { return [pscustomobject]@{ supported = $true; symbol = "DEUIDXEUR"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2018.01.01"; date_to = ""; mt5_export_name = "MB_DE30_DUKA"; notes = "registry_indices" } }
        "COPPER-US" { return [pscustomobject]@{ supported = $true; symbol = "COPPERCMDUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2018.01.01"; date_to = ""; mt5_export_name = "MB_COPPER_DUKA"; notes = "registry_metals_problem" } }
        "COPPERUS" { return [pscustomobject]@{ supported = $true; symbol = "COPPERCMDUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2018.01.01"; date_to = ""; mt5_export_name = "MB_COPPER_DUKA"; notes = "registry_metals_problem" } }
        "PLATIN" { return [pscustomobject]@{ supported = $false; reason = "no stable QDM datasource mapped for PLATIN in current flow; use MT5/runtime fallback on laptop" } }
        "US500" { return [pscustomobject]@{ supported = $true; symbol = "USA500IDXUSD"; datasource = "dukascopy"; datatype = "TICK"; date_from = "2018.01.01"; date_to = ""; mt5_export_name = "MB_US500_DUKA"; notes = "registry_indices" } }
        default { return [pscustomobject]@{ supported = $false; reason = "no QDM mapping defined for alias" } }
    }
}

function Normalize-QdmKey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return $Value.Trim().ToUpperInvariant()
}

function Get-OptionalStringProperty {
    param(
        [object]$InputObject,
        [string]$PropertyName
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $null }
    return [string]$property.Value
}

function Get-HistoryCandidates {
    param(
        [string]$HistoryRoot,
        [string]$Symbol,
        [string]$Datatype
    )

    $symbolDir = Join-Path $HistoryRoot $Symbol
    if (-not (Test-Path -LiteralPath $symbolDir)) { return @() }

    $baseName = "{0}_{1}.dat" -f $Symbol, $Datatype
    return @(
        Get-ChildItem -LiteralPath $symbolDir -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.PSIsContainer -and
                ($_.Name -eq $baseName -or $_.Name -eq ($baseName + ".copy"))
            } |
            Sort-Object LastWriteTime -Descending
    )
}

function Get-UsableHistoryCandidates {
    param(
        [object[]]$Candidates,
        [long]$MinimumBytes
    )

    return @(
        $Candidates |
            Where-Object { $_.Length -ge $MinimumBytes } |
            Sort-Object LastWriteTime -Descending
    )
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    throw "Registry not found: $RegistryPath"
}

$historyRoot = Join-Path $QdmRoot "user\data\History"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$blockedDefinitions = @()
if (Test-Path -LiteralPath $BlockedSymbolsPath) {
    try {
        $rawBlockedDefinitions = Get-Content -LiteralPath $BlockedSymbolsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($rawBlockedDefinitions -is [System.Array]) {
            $blockedDefinitions = @($rawBlockedDefinitions)
        }
        elseif ($null -ne $rawBlockedDefinitions) {
            $blockedDefinitions = @($rawBlockedDefinitions)
        }
    }
    catch {
        $blockedDefinitions = @()
    }
}

function Get-BlockedReason {
    param(
        [object[]]$Definitions,
        [string]$AliasKey,
        [string]$BrokerKey,
        [string]$QdmSymbolKey
    )

    foreach ($entry in $Definitions) {
        if ($null -eq $entry) { continue }

        $reason = Get-OptionalStringProperty -InputObject $entry -PropertyName "reason"
        if ([string]::IsNullOrWhiteSpace($reason)) { continue }

        $entryQdmSymbol = Normalize-QdmKey (Get-OptionalStringProperty -InputObject $entry -PropertyName "qdm_symbol")
        if (-not [string]::IsNullOrWhiteSpace($entryQdmSymbol)) {
            if ($entryQdmSymbol -eq $QdmSymbolKey) {
                return $reason
            }
            continue
        }

        $entryBrokerSymbol = Normalize-QdmKey (Get-OptionalStringProperty -InputObject $entry -PropertyName "broker_symbol")
        if (-not [string]::IsNullOrWhiteSpace($entryBrokerSymbol)) {
            if ($entryBrokerSymbol -eq $BrokerKey) {
                return $reason
            }
            continue
        }

        $entryAlias = Normalize-QdmKey (Get-OptionalStringProperty -InputObject $entry -PropertyName "symbol_alias")
        if (-not [string]::IsNullOrWhiteSpace($entryAlias) -and $entryAlias -eq $AliasKey) {
            return $reason
        }
    }

    return $null
}

$rows = New-Object System.Collections.Generic.List[object]
$present = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[object]
$unsupported = New-Object System.Collections.Generic.List[object]
$blocked = New-Object System.Collections.Generic.List[object]
$seenQdmSymbols = @{}

foreach ($item in @($registry.symbols)) {
    $alias = [string]$item.symbol
    $aliasKey = Normalize-QdmKey $alias
    $brokerSymbol = [string]$item.broker_symbol
    $brokerKey = Normalize-QdmKey $brokerSymbol
    $spec = Get-QdmSpec -Alias $alias
    $specSymbolKey = if ($null -ne $spec -and $spec.supported) { Normalize-QdmKey ([string]$spec.symbol) } else { $null }

    if ($null -eq $spec) { continue }

    if (-not $spec.supported) {
        $unsupported.Add([pscustomobject]@{
            symbol_alias = $alias
            broker_symbol = [string]$item.broker_symbol
            reason = [string]$spec.reason
        })
        continue
    }

    $blockedReason = Get-BlockedReason -Definitions $blockedDefinitions -AliasKey $aliasKey -BrokerKey $brokerKey -QdmSymbolKey $specSymbolKey

    if (-not [string]::IsNullOrWhiteSpace($blockedReason)) {
        $blocked.Add([pscustomobject]@{
            symbol_alias = $alias
            broker_symbol = $brokerSymbol
            qdm_symbol = if ($null -ne $spec -and $spec.supported) { [string]$spec.symbol } else { $null }
            reason = $blockedReason
        })
        continue
    }

    if ($seenQdmSymbols.ContainsKey($spec.symbol)) { continue }
    $seenQdmSymbols[$spec.symbol] = $true

    $historyCandidates = @(Get-HistoryCandidates -HistoryRoot $historyRoot -Symbol $spec.symbol -Datatype $spec.datatype)
    $usableHistory = @(Get-UsableHistoryCandidates -Candidates $historyCandidates -MinimumBytes $MinimumHistoryBytes)

    if ($usableHistory.Count -gt 0) {
        $best = $usableHistory[0]
        $present.Add([pscustomobject]@{
            symbol_alias = $alias
            qdm_symbol = $spec.symbol
            history_file = $best.Name
            size_mb = [math]::Round(($best.Length / 1MB), 1)
            last_write_local = $best.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        })
        continue
    }

    $row = [pscustomobject]@{
        enabled = "1"
        symbol = $spec.symbol
        datasource = $spec.datasource
        datatype = $spec.datatype
        date_from = $spec.date_from
        date_to = $spec.date_to
        mt5_export_name = $spec.mt5_export_name
        notes = $spec.notes
    }
    $rows.Add($row)
    $missing.Add([pscustomobject]@{
        symbol_alias = $alias
        broker_symbol = [string]$item.broker_symbol
        qdm_symbol = $spec.symbol
        datasource = $spec.datasource
        datatype = $spec.datatype
        mt5_export_name = $spec.mt5_export_name
        reason = if ($historyCandidates.Count -gt 0) { "history files exist but are too small or unusable" } else { "history files missing on disk" }
    })
}

$rows | Export-Csv -LiteralPath $OutputPath -Encoding UTF8 -NoTypeInformation

$presentArray = @($present.ToArray())
$missingArray = @($missing.ToArray())
$unsupportedArray = @($unsupported.ToArray())
$blockedArray = @($blocked.ToArray())

$report = @{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    output_profile_path = $OutputPath
    total_registry_symbols = @($registry.symbols).Count
    qdm_present_count = $present.Count
    qdm_missing_count = $missing.Count
    qdm_unsupported_count = $unsupported.Count
    qdm_blocked_count = $blocked.Count
    present = $presentArray
    missing = $missingArray
    unsupported = $unsupportedArray
    blocked = $blockedArray
}

$jsonLatest = Join-Path $EvidenceDir "qdm_missing_only_profile_latest.json"
$mdLatest = Join-Path $EvidenceDir "qdm_missing_only_profile_latest.md"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonStamped = Join-Path $EvidenceDir ("qdm_missing_only_profile_{0}.json" -f $timestamp)
$mdStamped = Join-Path $EvidenceDir ("qdm_missing_only_profile_{0}.md" -f $timestamp)

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# QDM Missing Only Profile Latest")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- output_profile_path: {0}" -f $report.output_profile_path))
$lines.Add(("- total_registry_symbols: {0}" -f $report.total_registry_symbols))
$lines.Add(("- qdm_present_count: {0}" -f $report.qdm_present_count))
$lines.Add(("- qdm_missing_count: {0}" -f $report.qdm_missing_count))
$lines.Add(("- qdm_unsupported_count: {0}" -f $report.qdm_unsupported_count))
$lines.Add(("- qdm_blocked_count: {0}" -f $report.qdm_blocked_count))
$lines.Add("")
$lines.Add("## Missing")
$lines.Add("")
if (@($report.missing).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in @($report.missing)) {
        $lines.Add(("- {0} -> {1} ({2}/{3}) export={4} reason={5}" -f
            $item.symbol_alias,
            $item.qdm_symbol,
            $item.datasource,
            $item.datatype,
            $item.mt5_export_name,
            $item.reason))
    }
}
$lines.Add("")
$lines.Add("## Unsupported")
$lines.Add("")
if (@($report.unsupported).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in @($report.unsupported)) {
        $lines.Add(("- {0}: {1}" -f $item.symbol_alias, $item.reason))
    }
}
$lines.Add("")
$lines.Add("## Blocked")
$lines.Add("")
if (@($report.blocked).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in @($report.blocked)) {
        $lines.Add(("- {0}: {1}" -f $item.symbol_alias, $item.reason))
    }
}
$lines.Add("")
$lines.Add("## Present")
$lines.Add("")
foreach ($item in @($report.present)) {
    $lines.Add(("- {0} -> {1}: {2} ({3} MB, {4})" -f
        $item.symbol_alias,
        $item.qdm_symbol,
        $item.history_file,
        $item.size_mb,
        $item.last_write_local))
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdStamped -Encoding UTF8

$report | ConvertTo-Json -Depth 8
