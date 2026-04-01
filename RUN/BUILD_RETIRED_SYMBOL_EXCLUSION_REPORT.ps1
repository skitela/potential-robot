param(
    [string[]]$RetiredSymbols = @("NZDUSD", "GBPJPY"),
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$HostingReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_hosting_daily_report_latest.json",
    [string]$QueuePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_retest_queue_latest.json",
    [string]$ResearchPlanPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_intensive_research_plan_latest.json",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$CommonStateRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state",
    [string]$CommonLogRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\logs",
    [string]$HandoffRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\HANDOFF",
    [string]$RemoteSimRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\REMOTE_SIM",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
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

function Test-JsonContainsSymbol {
    param(
        [object]$JsonObject,
        [string]$Symbol
    )

    if ($null -eq $JsonObject) {
        return $false
    }

    return (($JsonObject | ConvertTo-Json -Depth 16) -match ('"' + [regex]::Escape($Symbol) + '"'))
}

function Test-TreeContainsSymbol {
    param(
        [string]$RootPath,
        [string]$Symbol
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return $false
    }

    $pattern = [regex]::Escape($Symbol)
    $files = Get-ChildItem -LiteralPath $RootPath -File -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        if ($file.FullName -match $pattern) {
            return $true
        }
        try {
            if (Select-String -LiteralPath $file.FullName -Pattern $pattern -Quiet -Encoding UTF8) {
                return $true
            }
        }
        catch {
        }
    }

    return $false
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$registry = if (Test-Path -LiteralPath $RegistryPath) { Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$hosting = if (Test-Path -LiteralPath $HostingReportPath) { Get-Content -LiteralPath $HostingReportPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$queue = if (Test-Path -LiteralPath $QueuePath) { Get-Content -LiteralPath $QueuePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$researchPlan = if (Test-Path -LiteralPath $ResearchPlanPath) { Get-Content -LiteralPath $ResearchPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$profitTracking = if (Test-Path -LiteralPath $ProfitTrackingPath) { Get-Content -LiteralPath $ProfitTrackingPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

$registryAliases = @()
if ($null -ne $registry -and $registry.PSObject.Properties.Name -contains "symbols") {
    $registryAliases = @($registry.symbols | ForEach-Object { Normalize-SymbolAlias ([string]$_.symbol) })
}

$items = foreach ($symbol in @($RetiredSymbols | ForEach-Object { Normalize-SymbolAlias $_ })) {
    $hostingContains = Test-JsonContainsSymbol -JsonObject $hosting -Symbol $symbol
    $historicallyExcluded = $false
    if ($null -ne $hosting -and $hosting.PSObject.Properties.Name -contains "historical_roster_excluded_symbols") {
        $historicallyExcluded = @($hosting.historical_roster_excluded_symbols | ForEach-Object { Normalize-SymbolAlias ([string]$_) }) -contains $symbol
    }
    [pscustomobject]@{
        symbol_alias = $symbol
        obecny_w_rejestrze_aktywnym = ($registryAliases -contains $symbol)
        obecny_w_kolejce_testera = Test-JsonContainsSymbol -JsonObject $queue -Symbol $symbol
        obecny_w_planie_badawczym = Test-JsonContainsSymbol -JsonObject $researchPlan -Symbol $symbol
        obecny_w_profit_tracking = Test-JsonContainsSymbol -JsonObject $profitTracking -Symbol $symbol
        obecny_w_hostingu_aktywnym = ($hostingContains -and -not $historicallyExcluded)
        katalog_stanu_istnieje = (Test-Path -LiteralPath (Join-Path $CommonStateRoot $symbol))
        katalog_logow_istnieje = (Test-Path -LiteralPath (Join-Path $CommonLogRoot $symbol))
        obecny_w_handoff = Test-TreeContainsSymbol -RootPath $HandoffRoot -Symbol $symbol
        obecny_w_remote_sim = Test-TreeContainsSymbol -RootPath $RemoteSimRoot -Symbol $symbol
    }
}

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    retired_symbol_count = $items.Count
    all_clean = @($items | Where-Object {
        $_.obecny_w_rejestrze_aktywnym -or
        $_.obecny_w_kolejce_testera -or
        $_.obecny_w_planie_badawczym -or
        $_.obecny_w_profit_tracking -or
        $_.obecny_w_hostingu_aktywnym -or
        $_.katalog_stanu_istnieje -or
        $_.katalog_logow_istnieje -or
        $_.obecny_w_handoff -or
        $_.obecny_w_remote_sim
    }).Count -eq 0
    items = $items
}

$jsonPath = Join-Path $OutputRoot "retired_symbol_exclusion_latest.json"
$mdPath = Join-Path $OutputRoot "retired_symbol_exclusion_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Raport Wykluczenia Wycofanych Symboli")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- all_clean: {0}" -f $report.all_clean))
$lines.Add("")
foreach ($item in @($items)) {
    $lines.Add(("## {0}" -f $item.symbol_alias))
    $lines.Add(("- obecny_w_rejestrze_aktywnym: {0}" -f $item.obecny_w_rejestrze_aktywnym))
    $lines.Add(("- obecny_w_kolejce_testera: {0}" -f $item.obecny_w_kolejce_testera))
    $lines.Add(("- obecny_w_planie_badawczym: {0}" -f $item.obecny_w_planie_badawczym))
    $lines.Add(("- obecny_w_profit_tracking: {0}" -f $item.obecny_w_profit_tracking))
    $lines.Add(("- obecny_w_hostingu_aktywnym: {0}" -f $item.obecny_w_hostingu_aktywnym))
    $lines.Add(("- katalog_stanu_istnieje: {0}" -f $item.katalog_stanu_istnieje))
    $lines.Add(("- katalog_logow_istnieje: {0}" -f $item.katalog_logow_istnieje))
    $lines.Add(("- obecny_w_handoff: {0}" -f $item.obecny_w_handoff))
    $lines.Add(("- obecny_w_remote_sim: {0}" -f $item.obecny_w_remote_sim))
    $lines.Add("")
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
