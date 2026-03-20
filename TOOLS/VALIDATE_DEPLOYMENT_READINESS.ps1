param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$TokenMaxAgeSec = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Get-InputMagicFromExpert {
    param([string]$ExpertPath)
    $match = Select-String -Path $ExpertPath -Pattern 'input ulong InpMagic = (\d+);' | Select-Object -First 1
    if (-not $match) { return $null }
    return [long]$match.Matches[0].Groups[1].Value
}

function Get-InputMagicFromPreset {
    param([string]$PresetPath)
    $line = Select-String -Path $PresetPath -Pattern '^InpMagic=(\d+)$' | Select-Object -First 1
    if (-not $line) { return $null }
    return [long]$line.Matches[0].Groups[1].Value
}

function Get-TokenStatus {
    param(
        [string]$TokenPath,
        [int]$MaxAgeSec
    )

    if (-not (Test-Path -LiteralPath $TokenPath)) {
        return [pscustomobject]@{
            present = $false
            valid = $false
            stale = $true
            age_sec = $null
            reason = "TOKEN_MISSING"
        }
    }

    $raw = (Get-Content -LiteralPath $TokenPath -Raw -ErrorAction Stop).Trim()
    $epoch = 0L
    if (-not [long]::TryParse($raw, [ref]$epoch) -or $epoch -le 0) {
        return [pscustomobject]@{
            present = $true
            valid = $false
            stale = $true
            age_sec = $null
            reason = "TOKEN_INVALID"
        }
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $age = [int]($now - $epoch)
    $stale = ($age -gt $MaxAgeSec)
    $reason = "OK"
    if ($stale) {
        $reason = "TOKEN_STALE"
    }
    return [pscustomobject]@{
        present = $true
        valid = $true
        stale = $stale
        age_sec = $age
        reason = $reason
    }
}

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$variantPath = Join-Path $ProjectRoot "CONFIG\strategy_variant_registry.json"
$registry = Get-Content -LiteralPath $registryPath -Encoding UTF8 | ConvertFrom-Json
$variantRegistry = if (Test-Path -LiteralPath $variantPath) { Get-Content -LiteralPath $variantPath -Encoding UTF8 -Raw | ConvertFrom-Json } else { $null }
$variantBySymbol = @{}
if ($variantRegistry) {
    foreach ($variant in $variantRegistry.variants) {
        $variantBySymbol[[string]$variant.symbol] = $variant
        $variantBySymbol[(([string]$variant.symbol) -replace '\.pro$','')] = $variant
    }
}
$commonRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\key"
$reportRows = @()
$issues = New-Object System.Collections.Generic.List[string]
$magicSet = New-Object System.Collections.Generic.HashSet[long]

foreach ($item in $registry.symbols) {
    $symbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $brokerSymbol = Get-RegistryBrokerSymbol -RegistryItem $item
    $expert = [string]$item.expert
    $preset = [string]$item.preset
    $registryMagic = [long]$item.magic
    $variant = if ($variantBySymbol.ContainsKey($symbol)) { $variantBySymbol[$symbol] } elseif ($variantBySymbol.ContainsKey($brokerSymbol)) { $variantBySymbol[$brokerSymbol] } else { $null }
    $tokenName = if ($variant -and $variant.profile -and $variant.profile.kill_switch_token_name) { [string]$variant.profile.kill_switch_token_name } else { ("oandakey_{0}.token" -f $symbol.ToLowerInvariant()) }

    $expertPath = Join-Path $ProjectRoot ("MQL5\Experts\MicroBots\{0}.mq5" -f $expert)
    $presetPath = Join-Path $ProjectRoot ("MQL5\Presets\{0}" -f $preset)
    $expertMagic = Get-InputMagicFromExpert -ExpertPath $expertPath
    $presetMagic = Get-InputMagicFromPreset -PresetPath $presetPath
    $tokenPath = Join-Path (Join-Path $commonRoot $symbol) $tokenName
    $token = Get-TokenStatus -TokenPath $tokenPath -MaxAgeSec $TokenMaxAgeSec

    $magicUnique = $magicSet.Add($registryMagic)
    if (-not $magicUnique) {
        $issues.Add(("DUPLICATE_MAGIC:{0}" -f $registryMagic))
    }
    if ($expertMagic -ne $registryMagic) {
        $issues.Add(("EXPERT_MAGIC_MISMATCH:{0}" -f $symbol))
    }
    if ($presetMagic -ne $registryMagic) {
        $issues.Add(("PRESET_MAGIC_MISMATCH:{0}" -f $symbol))
    }
    if (-not $token.present -or -not $token.valid -or $token.stale) {
        $issues.Add(("TOKEN_NOT_READY:{0}:{1}" -f $symbol,$token.reason))
    }

    $reportRows += [pscustomobject]@{
        symbol = $symbol
        broker_symbol = $brokerSymbol
        expert = $expert
        preset = $preset
        registry_magic = $registryMagic
        expert_magic = $expertMagic
        preset_magic = $presetMagic
        magic_match = (($expertMagic -eq $registryMagic) -and ($presetMagic -eq $registryMagic))
        token_present = $token.present
        token_valid = $token.valid
        token_stale = $token.stale
        token_age_sec = $token.age_sec
        token_reason = $token.reason
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    token_max_age_sec = $TokenMaxAgeSec
    ok = ($issues.Count -eq 0)
    issues = @($issues)
    symbols = $reportRows
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\deployment_readiness_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\deployment_readiness_report.txt"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$txtLines = @()
$txtLines += "DEPLOYMENT READINESS REPORT"
$txtLines += ("OK={0}" -f $report.ok)
$txtLines += ""
foreach ($row in $reportRows) {
    $txtLines += ("{0} | expert={1} | preset={2} | magic={3} | token={4} | age={5}" -f $row.symbol,$row.expert,$row.preset,$row.registry_magic,$row.token_reason,$row.token_age_sec)
}
if ($issues.Count -gt 0) {
    $txtLines += ""
    $txtLines += "ISSUES"
    $txtLines += $issues
}
$txtLines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$report | ConvertTo-Json -Depth 6

if ($issues.Count -gt 0) {
    exit 1
}
