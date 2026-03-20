param(
    [Parameter(Mandatory = $true)]
    [string]$Symbol,
    [string]$TokenName = "",
    [string]$UsbRoot = "C:\GLOBALNY HANDEL VER1\OANDAKEY",
    [string]$ProjectCommonRoot = "$env:APPDATA\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
if (Test-Path -LiteralPath $helperPath) {
    . $helperPath
}

$envPath = Join-Path $UsbRoot "TOKEN\BotKey.env"
if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Brak BotKey.env w OANDAKEY."
}

$canonicalSymbol = ($Symbol -replace '\.pro$','').Trim()
$brokerSymbol = if ($canonicalSymbol.EndsWith(".pro", [System.StringComparison]::OrdinalIgnoreCase)) { $canonicalSymbol } else { "$canonicalSymbol.pro" }
$codeSymbol = (($canonicalSymbol -replace '[^A-Za-z0-9]','').ToUpperInvariant())

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
if ((Test-Path -LiteralPath $registryPath) -and (Get-Command Find-RegistryEntryByAlias -ErrorAction SilentlyContinue)) {
    $registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry = Find-RegistryEntryByAlias -Registry $registry -Alias $Symbol
    if ($null -ne $entry) {
        $canonicalSymbol = Get-RegistryCanonicalSymbol -RegistryItem $entry
        $brokerSymbol = Get-RegistryBrokerSymbol -RegistryItem $entry
        $codeSymbol = Get-RegistryCodeSymbol -RegistryItem $entry
    }
}

$symbolLower = $canonicalSymbol.ToLowerInvariant()
$tokenDirs = New-Object System.Collections.Generic.List[string]
foreach ($dirName in @($canonicalSymbol, $brokerSymbol, $codeSymbol) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
    [void]$tokenDirs.Add((Join-Path $ProjectCommonRoot ("key\{0}" -f $dirName)))
}

$resolvedTokenName = if ([string]::IsNullOrWhiteSpace($TokenName)) { "oandakey_{0}.token" -f $symbolLower } else { $TokenName }
$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$tokenPaths = New-Object System.Collections.Generic.List[string]
foreach ($keyRoot in @($tokenDirs)) {
    New-Item -ItemType Directory -Force -Path $keyRoot | Out-Null
    $tokenPath = Join-Path $keyRoot $resolvedTokenName
    Set-Content -LiteralPath $tokenPath -Value ([string]$epoch) -Encoding ascii
    [void]$tokenPaths.Add($tokenPath)
}

[ordered]@{
    schema = "makro_i_mikro_bot.oandakey.sync.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    usb_root = $UsbRoot
    symbol = $canonicalSymbol
    broker_symbol = $brokerSymbol
    code_symbol = $codeSymbol
    token_name = $resolvedTokenName
    token_path = [string]($tokenPaths | Select-Object -First 1)
    token_paths = @($tokenPaths)
    status = "OK"
} | ConvertTo-Json -Depth 4
