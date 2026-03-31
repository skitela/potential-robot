param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string[]]$Symbols = @(),
    [string]$OutputJsonPath = "",
    [string]$OutputTxtPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$planPath = Join-Path $ProjectRoot "CONFIG\scalping_universe_plan.json"

if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing microbots registry: $registryPath"
}
if (-not (Test-Path -LiteralPath $planPath)) {
    throw "Missing scalping universe plan: $planPath"
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($Symbols.Count -le 0) {
    throw "Symbols list is empty."
}

function Normalize-Alias {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    return $Value.Trim().ToUpperInvariant()
}

function Get-BucketForSymbol {
    param(
        [string]$Alias,
        [object]$UniversePlan
    )

    $normalized = Normalize-Alias -Value $Alias
    if ($normalized -in @($UniversePlan.paper_live_first_wave | ForEach-Object { Normalize-Alias -Value ([string]$_) })) {
        return "FIRST_WAVE"
    }
    if ($normalized -in @($UniversePlan.paper_live_second_wave | ForEach-Object { Normalize-Alias -Value ([string]$_) })) {
        return "SECOND_WAVE"
    }
    if ($normalized -in @($UniversePlan.paper_live_hold | ForEach-Object { Normalize-Alias -Value ([string]$_) })) {
        return "HOLD"
    }
    if ($normalized -in @($UniversePlan.global_teacher_only | ForEach-Object { Normalize-Alias -Value ([string]$_) })) {
        return "GLOBAL_TEACHER_ONLY"
    }
    return "UNKNOWN"
}

function Get-RuntimeScopeForBucket {
    param([string]$Bucket)

    if ($Bucket -eq "FIRST_WAVE") {
        return "PAPER_LIVE"
    }
    return "LAPTOP_ONLY"
}

$symbolSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($symbol in @($Symbols)) {
    $normalized = Normalize-Alias -Value ([string]$symbol)
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        [void]$symbolSet.Add($normalized)
    }
}

$rows = New-Object System.Collections.Generic.List[object]
$index = 1
foreach ($requestedSymbol in @($Symbols)) {
    $requestedAlias = Normalize-Alias -Value ([string]$requestedSymbol)
    if ([string]::IsNullOrWhiteSpace($requestedAlias)) {
        continue
    }

    $item = Find-RegistryEntryByAlias -Registry $registry -Alias $requestedAlias
    if ($null -eq $item) {
        throw "Missing registry entry for symbol: $requestedAlias"
    }

    $canonicalSymbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $bucket = Get-BucketForSymbol -Alias $canonicalSymbol -UniversePlan $plan
    $rows.Add([PSCustomObject]@{
        chart_no = $index
        symbol = $canonicalSymbol
        broker_symbol = Get-RegistryBrokerSymbol -RegistryItem $item
        expert = [string]$item.expert
        preset = [string]$item.preset
        magic = [string]$item.magic
        chart_tf = [string]$item.chart_tf
        session_profile = [string]$item.session_profile
        status = [string]$item.status
        paper_live_bucket = $bucket
        runtime_scope = (Get-RuntimeScopeForBucket -Bucket $bucket)
    }) | Out-Null
    $index++
}

if ([string]::IsNullOrWhiteSpace($OutputJsonPath)) {
    $OutputJsonPath = Join-Path $ProjectRoot "EVIDENCE\OPS\symbol_group_chart_plan_latest.json"
}
if ([string]::IsNullOrWhiteSpace($OutputTxtPath)) {
    $OutputTxtPath = Join-Path $ProjectRoot "EVIDENCE\OPS\symbol_group_chart_plan_latest.txt"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputJsonPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputTxtPath) | Out-Null

$rowsArray = @($rows.ToArray())
$rowsArray | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputJsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("MT5 SYMBOL GROUP CHART PLAN")
$lines.Add("")
foreach ($row in $rowsArray) {
    $lines.Add(("Chart {0}: {1} [{2}] -> {3} -> {4} -> Magic={5} -> TF={6} -> Session={7} -> Bucket={8} -> Scope={9}" -f
        $row.chart_no,
        $row.symbol,
        $row.broker_symbol,
        $row.expert,
        $row.preset,
        $row.magic,
        $row.chart_tf,
        $row.session_profile,
        $row.paper_live_bucket,
        $row.runtime_scope))
}
$lines | Set-Content -LiteralPath $OutputTxtPath -Encoding ASCII

$rowsArray | Format-Table -AutoSize
