param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$registry = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot "CONFIG\microbots_registry.json") | ConvertFrom-Json
$rows = @()
foreach ($item in $registry.symbols) {
    $symbol = [string]$item.symbol
    $family = [string]$item.session_profile
    $controlPath = Join-Path $CommonFilesRoot ("state\{0}\runtime_control.csv" -f $symbol)
    $requestedMode = "BRAK"
    $reasonCode = ""
    if (Test-Path -LiteralPath $controlPath) {
        foreach ($line in Get-Content -LiteralPath $controlPath) {
            $parts = $line -split "`t", 2
            if ($parts.Count -lt 2) { continue }
            if ($parts[0] -eq "requested_mode") { $requestedMode = $parts[1] }
            elseif ($parts[0] -eq "reason_code") { $reasonCode = $parts[1] }
        }
    }
    $rows += [pscustomobject]@{
        para_walutowa = $symbol
        rodzina = $family
        requested_mode = $requestedMode
        reason_code = $reasonCode
    }
}

$summary = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    kontrola = $rows
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\runtime_control_summary.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\runtime_control_summary.txt"
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$txt = @("RUNTIME CONTROL SUMMARY")
foreach ($row in $rows) {
    $txt += ("{0} | rodzina={1} | requested_mode={2} | reason={3}" -f $row.para_walutowa, $row.rodzina, $row.requested_mode, $row.reason_code)
}
$txt | Set-Content -LiteralPath $txtPath -Encoding UTF8

$summary | ConvertTo-Json -Depth 6
