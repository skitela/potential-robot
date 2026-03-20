param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$registry = Get-Content -LiteralPath $registryPath -Encoding UTF8 | ConvertFrom-Json

$updated = @()
foreach ($item in $registry.symbols) {
    $symbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $codeSymbol = Get-RegistryCodeSymbol -RegistryItem $item
    $magic = [string]([UInt64]$item.magic)

    $expertPath = Join-Path $ProjectRoot ("MQL5\Experts\MicroBots\MicroBot_{0}.mq5" -f $codeSymbol)
    $presetPath = Join-Path $ProjectRoot ("MQL5\Presets\MicroBot_{0}_Live.set" -f $codeSymbol)
    $activePresetPath = Join-Path $ProjectRoot ("SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive\MicroBot_{0}_Live_ACTIVE.set" -f $codeSymbol)

    if (Test-Path -LiteralPath $expertPath) {
        $expertText = Get-Content -LiteralPath $expertPath -Raw -Encoding UTF8
        $expertText = [regex]::Replace($expertText,'input ulong InpMagic = \d+;',"input ulong InpMagic = $magic;")
        Set-Content -LiteralPath $expertPath -Value $expertText -Encoding ASCII
    }

    foreach ($preset in @($presetPath,$activePresetPath)) {
        if (Test-Path -LiteralPath $preset) {
            $presetText = Get-Content -LiteralPath $preset -Raw -Encoding UTF8
            if ($presetText -match '(?m)^InpMagic=') {
                $presetText = [regex]::Replace($presetText,'(?m)^InpMagic=.*$',"InpMagic=$magic")
            } else {
                $presetText = "InpMagic=$magic`r`n$presetText"
            }
            Set-Content -LiteralPath $preset -Value $presetText -Encoding ASCII
        }
    }

    $updated += [pscustomobject]@{
        symbol = $symbol
        magic = [UInt64]$item.magic
        expert = $expertPath
        preset = $presetPath
        active_preset = $activePresetPath
    }
}

$report = [pscustomobject]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    updated = $updated
}

$reportPath = Join-Path $ProjectRoot "EVIDENCE\sync_microbot_magics_report.json"
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 5
