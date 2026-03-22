param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$SymbolAlias = "NZDUSD",
    [string]$QdmSymbol = "NZDUSD",
    [string]$BrokerTemplateSymbol = "NZDUSD.pro",
    [string]$Period = "M1",
    [string]$FromDate = "2026.03.12",
    [string]$ToDate = "2026.03.16",
    [string]$TerminalRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [int]$TimeoutSec = 300,
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_run_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$normalizedAlias = $SymbolAlias.ToUpperInvariant()
$exportName = "MB_{0}_DUKA_M1_PILOT" -f $normalizedAlias
$pilotCsvPath = Join-Path $ProjectRoot ("EVIDENCE\QDM_PILOT\{0}.csv" -f $exportName)
$commonRelativeCsvPath = "MAKRO_I_MIKRO_BOT\\qdm_import\\{0}.csv" -f $exportName
$customSymbol = "{0}_QDM_M1" -f $normalizedAlias

$exportScript = Join-Path $ProjectRoot "RUN\EXPORT_QDM_PILOT_SYMBOL_TO_MT5.ps1"
$smokeScript = Join-Path $ProjectRoot "RUN\RUN_QDM_CUSTOM_SYMBOL_SMOKE.ps1"

foreach ($path in @($exportScript, $smokeScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$pwsh = (Get-Command powershell.exe -ErrorAction Stop).Source

$exportArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $exportScript,
    "-ProjectRoot", $ProjectRoot,
    "-QdmSymbol", $QdmSymbol,
    "-ExportName", $exportName,
    "-Timeframe", $Period,
    "-DateFrom", $FromDate,
    "-DateTo", $ToDate
)

$exportResult = & $pwsh @exportArgs
$exportExitCode = $LASTEXITCODE
if ($exportExitCode -ne 0) {
    throw "QDM pilot export failed for $QdmSymbol"
}

$smokeArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $smokeScript,
    "-ProjectRoot", $ProjectRoot,
    "-TerminalRoot", $TerminalRoot,
    "-SymbolAlias", $normalizedAlias,
    "-PilotCsvPath", $pilotCsvPath,
    "-CommonRelativeCsvPath", $commonRelativeCsvPath,
    "-CustomSymbol", $customSymbol,
    "-BrokerTemplateSymbol", $BrokerTemplateSymbol,
    "-Period", $Period,
    "-FromDate", $FromDate,
    "-ToDate", $ToDate,
    "-TimeoutSec", $TimeoutSec
)

$smokeResult = & $pwsh @smokeArgs
$smokeExitCode = $LASTEXITCODE
if ($smokeExitCode -ne 0) {
    throw "QDM custom symbol smoke failed for $customSymbol"
}

$exportObject = $null
$smokeObject = $null
try { $exportObject = $exportResult | ConvertFrom-Json -ErrorAction Stop } catch {}
try { $smokeObject = $smokeResult | ConvertFrom-Json -ErrorAction Stop } catch {}

$result = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    symbol_alias = $normalizedAlias
    qdm_symbol = $QdmSymbol
    export_name = $exportName
    pilot_csv_path = $pilotCsvPath
    custom_symbol = $customSymbol
    broker_template_symbol = $BrokerTemplateSymbol
    export = $exportObject
    smoke = $smokeObject
    state = "completed"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
$result | ConvertTo-Json -Depth 8
