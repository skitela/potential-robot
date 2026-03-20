param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$PriorityReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.json",
    [string]$OutputPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_weakest_pack.csv",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$DesiredCount = 17
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-QdmSpec {
    param([string]$Alias)

    if ([string]::IsNullOrWhiteSpace($Alias)) {
        return $null
    }

    $normalized = $Alias.Trim().ToUpperInvariant()
    switch ($normalized) {
        "EURUSD" {
            return [pscustomobject]@{
                supported = $true
                symbol = "EURUSD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_EURUSD_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "AUDUSD" {
            return [pscustomobject]@{
                supported = $true
                symbol = "AUDUSD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_AUDUSD_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "GBPUSD" {
            return [pscustomobject]@{
                supported = $true
                symbol = "GBPUSD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_GBPUSD_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "USDJPY" {
            return [pscustomobject]@{
                supported = $true
                symbol = "USDJPY"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_USDJPY_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "USDCAD" {
            return [pscustomobject]@{
                supported = $true
                symbol = "USDCAD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_USDCAD_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "USDCHF" {
            return [pscustomobject]@{
                supported = $true
                symbol = "USDCHF"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_USDCHF_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "NZDUSD" {
            return [pscustomobject]@{
                supported = $true
                symbol = "NZDUSD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_NZDUSD_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "EURJPY" {
            return [pscustomobject]@{
                supported = $true
                symbol = "EURJPY"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_EURJPY_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "GBPJPY" {
            return [pscustomobject]@{
                supported = $true
                symbol = "GBPJPY"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_GBPJPY_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "EURAUD" {
            return [pscustomobject]@{
                supported = $true
                symbol = "EURAUD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_EURAUD_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "GBPAUD" {
            return [pscustomobject]@{
                supported = $true
                symbol = "GBPAUD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2016.01.01"
                date_to = ""
                mt5_export_name = "MB_GBPAUD_DUKA"
                notes = "weakest_dynamic_fx"
            }
        }
        "GOLD" {
            return [pscustomobject]@{
                supported = $true
                symbol = "XAUUSD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2018.01.01"
                date_to = ""
                mt5_export_name = "MB_GOLD_DUKA"
                notes = "weakest_dynamic_live"
            }
        }
        "SILVER" {
            return [pscustomobject]@{
                supported = $true
                symbol = "XAGUSD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2018.01.01"
                date_to = ""
                mt5_export_name = "MB_SILVER_DUKA"
                notes = "weakest_dynamic_live"
            }
        }
        "DE30" {
            return [pscustomobject]@{
                supported = $true
                symbol = "DEU.IDX"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2018.01.01"
                date_to = ""
                mt5_export_name = "MB_DE30_DUKA"
                notes = "weakest_dynamic_live"
            }
        }
        "COPPER-US" {
            return [pscustomobject]@{
                supported = $true
                symbol = "COPPER.CMD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2018.01.01"
                date_to = ""
                mt5_export_name = "MB_COPPER_DUKA"
                notes = "weakest_dynamic_live"
            }
        }
        "COPPERUS" {
            return [pscustomobject]@{
                supported = $true
                symbol = "COPPER.CMD"
                datasource = "dukascopy"
                datatype = "TICK"
                date_from = "2018.01.01"
                date_to = ""
                mt5_export_name = "MB_COPPER_DUKA"
                notes = "weakest_dynamic_live"
            }
        }
        "PLATIN" {
            return [pscustomobject]@{
                supported = $false
                reason = "no stable QDM datasource mapped in our current flow; XPTUSD is present only on non-dukascopy sources"
            }
        }
        "US500" {
            return [pscustomobject]@{
                supported = $false
                reason = "USA500.IDX add failed earlier in QDM; keep out of weakest sync until datasource is stabilized"
            }
        }
        default {
            return [pscustomobject]@{
                supported = $false
                reason = "no QDM mapping defined yet for this alias"
            }
        }
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

if (-not (Test-Path -LiteralPath $PriorityReportPath)) {
    throw "Priority report not found: $PriorityReportPath"
}

$priority = Get-Content -LiteralPath $PriorityReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ranked = @($priority.ranked_instruments)

$rows = New-Object System.Collections.Generic.List[object]
$included = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[object]
$seenSymbols = @{}

foreach ($entry in $ranked) {
    if ($rows.Count -ge $DesiredCount) {
        break
    }

    $alias = [string]$entry.symbol_alias
    $spec = Get-QdmSpec -Alias $alias
    if ($null -eq $spec) {
        continue
    }

    if (-not $spec.supported) {
        $skipped.Add([pscustomobject]@{
            rank = $entry.rank
            symbol_alias = $alias
            reason = $spec.reason
        })
        continue
    }

    if ($seenSymbols.ContainsKey($spec.symbol)) {
        $skipped.Add([pscustomobject]@{
            rank = $entry.rank
            symbol_alias = $alias
            reason = "duplicate resolved QDM symbol"
        })
        continue
    }

    $seenSymbols[$spec.symbol] = $true

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
    $included.Add([pscustomobject]@{
        rank = $entry.rank
        symbol_alias = $alias
        qdm_symbol = $spec.symbol
        datasource = $spec.datasource
        mt5_export_name = $spec.mt5_export_name
    })
}

if ($rows.Count -eq 0) {
    throw "No supported QDM symbols were resolved from priority report."
}

$rows | Export-Csv -LiteralPath $OutputPath -Encoding UTF8 -NoTypeInformation

$includedArray = @($included | ForEach-Object { $_ })
$skippedArray = @($skipped | ForEach-Object { $_ })

$report = New-Object psobject
$report | Add-Member -NotePropertyName "generated_at_local" -NotePropertyValue ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
$report | Add-Member -NotePropertyName "generated_at_utc" -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o"))
$report | Add-Member -NotePropertyName "source_priority_path" -NotePropertyValue $PriorityReportPath
$report | Add-Member -NotePropertyName "output_profile_path" -NotePropertyValue $OutputPath
$report | Add-Member -NotePropertyName "desired_count" -NotePropertyValue $DesiredCount
$report | Add-Member -NotePropertyName "included" -NotePropertyValue $includedArray
$report | Add-Member -NotePropertyName "skipped" -NotePropertyValue $skippedArray

$jsonLatest = Join-Path $EvidenceDir "qdm_weakest_profile_latest.json"
$mdLatest = Join-Path $EvidenceDir "qdm_weakest_profile_latest.md"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonStamped = Join-Path $EvidenceDir ("qdm_weakest_profile_{0}.json" -f $timestamp)
$mdStamped = Join-Path $EvidenceDir ("qdm_weakest_profile_{0}.md" -f $timestamp)

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# QDM Weakest Profile Latest")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- output_profile_path: {0}" -f $report.output_profile_path))
$lines.Add("")
$lines.Add("## Included")
$lines.Add("")
foreach ($item in $included) {
    $lines.Add(("- #{0} {1} -> {2} ({3}) export={4}" -f
        $item.rank,
        $item.symbol_alias,
        $item.qdm_symbol,
        $item.datasource,
        $item.mt5_export_name))
}
$lines.Add("")
$lines.Add("## Skipped")
$lines.Add("")
if ($skipped.Count -gt 0) {
    foreach ($item in $skipped) {
        $lines.Add(("- #{0} {1}: {2}" -f $item.rank, $item.symbol_alias, $item.reason))
    }
}
else {
    $lines.Add("- none")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdStamped -Encoding UTF8

$report
