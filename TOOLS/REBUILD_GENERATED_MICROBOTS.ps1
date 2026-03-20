param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [switch]$IncludeReference,
    [switch]$ExpertOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registryPath = Join-Path $ProjectRoot "CONFIG\\microbots_registry.json"
$registry = Get-Content -LiteralPath $registryPath -Encoding UTF8 | ConvertFrom-Json
$scaffoldScript = Join-Path $ProjectRoot "TOOLS\\NEW_MICROBOT_SCAFFOLD.ps1"

$rebuilt = @()
foreach ($item in $registry.symbols) {
    $symbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $codeSymbol = Get-RegistryCodeSymbol -RegistryItem $item
    $status = [string]$item.status
    $magic = [UInt64]$item.magic
    if (-not $IncludeReference -and $status -eq "compiled_verified" -and $symbol -eq "EURUSD") {
        continue
    }
    if (-not $IncludeReference -and $symbol -eq "EURUSD") {
        continue
    }

    $expertPath = Join-Path $ProjectRoot ("MQL5\\Experts\\MicroBots\\MicroBot_{0}.mq5" -f $codeSymbol)
    $profilePath = Join-Path $ProjectRoot ("MQL5\\Include\\Profiles\\Profile_{0}.mqh" -f $codeSymbol)
    $strategyPath = Join-Path $ProjectRoot ("MQL5\\Include\\Strategies\\Strategy_{0}.mqh" -f $codeSymbol)
    $presetPath = Join-Path $ProjectRoot ("MQL5\\Presets\\MicroBot_{0}_Live.set" -f $codeSymbol)

    $pathsToReset = @($expertPath)
    if (-not $ExpertOnly) {
        $pathsToReset += @($profilePath,$strategyPath,$presetPath)
    }

    foreach ($path in $pathsToReset) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $scaffoldScript,
        "-Symbol", $codeSymbol,
        "-ProjectRoot", $ProjectRoot,
        "-MagicNumber", $magic
    )
    if ($ExpertOnly) {
        $args += "-ExpertOnly"
    }
    powershell @args | Out-Null
    $rebuilt += $symbol
}

$reportPath = Join-Path $ProjectRoot "EVIDENCE\\rebuild_generated_microbots_report.json"
$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    include_reference = [bool]$IncludeReference
    expert_only = [bool]$ExpertOnly
    rebuilt_symbols = @($rebuilt)
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 5
