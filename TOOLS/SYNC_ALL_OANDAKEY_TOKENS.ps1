param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$UsbRoot = "C:\GLOBALNY HANDEL VER1\OANDAKEY"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$registry = Get-Content -LiteralPath $registryPath -Encoding UTF8 | ConvertFrom-Json
$variantPath = Join-Path $ProjectRoot "CONFIG\strategy_variant_registry.json"
$variantRegistry = if (Test-Path -LiteralPath $variantPath) { Get-Content -LiteralPath $variantPath -Encoding UTF8 -Raw | ConvertFrom-Json } else { $null }
$tokenMap = @{}
if ($variantRegistry) {
    foreach ($variant in $variantRegistry.variants) {
        if ($variant.profile -and $variant.profile.kill_switch_token_name) {
            $tokenMap[[string]$variant.symbol] = [string]$variant.profile.kill_switch_token_name
        }
    }
}
$syncScript = Join-Path $ProjectRoot "TOOLS\SYNC_OANDAKEY_TOKEN.ps1"

$results = @()
foreach ($item in $registry.symbols) {
    $symbol = [string]$item.symbol
    $tokenName = if ($tokenMap.ContainsKey($symbol)) { $tokenMap[$symbol] } else { ("oandakey_{0}.token" -f $symbol.ToLowerInvariant()) }
    $json = & $syncScript -Symbol $symbol -TokenName $tokenName -UsbRoot $UsbRoot
    $results += ($json | ConvertFrom-Json)
}

$results | ConvertTo-Json -Depth 5
