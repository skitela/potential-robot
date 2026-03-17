param(
    [Parameter(Mandatory = $true)]
    [string]$Symbol,
    [string]$TokenName = "",
    [string]$UsbRoot = "C:\GLOBALNY HANDEL VER1\OANDAKEY",
    [string]$ProjectCommonRoot = "$env:APPDATA\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$symbolUpper = $Symbol.ToUpperInvariant()
$symbolLower = $Symbol.ToLowerInvariant()
$envPath = Join-Path $UsbRoot "TOKEN\BotKey.env"
if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Brak BotKey.env w OANDAKEY."
}

$keyRoot = Join-Path $ProjectCommonRoot ("key\{0}" -f $symbolUpper)
New-Item -ItemType Directory -Force -Path $keyRoot | Out-Null

$resolvedTokenName = if ([string]::IsNullOrWhiteSpace($TokenName)) { "oandakey_{0}.token" -f $symbolLower } else { $TokenName }
$tokenPath = Join-Path $keyRoot $resolvedTokenName
$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Set-Content -LiteralPath $tokenPath -Value ([string]$epoch) -Encoding ascii

[ordered]@{
    schema = "makro_i_mikro_bot.oandakey.sync.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    usb_root = $UsbRoot
    symbol = $symbolUpper
    token_name = $resolvedTokenName
    token_path = $tokenPath
    status = "OK"
} | ConvertTo-Json -Depth 4
