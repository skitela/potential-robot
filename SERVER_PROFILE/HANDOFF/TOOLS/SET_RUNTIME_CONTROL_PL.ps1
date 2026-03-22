param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [ValidateSet("system","rodzina","para")]
    [string]$Zakres = "system",
    [string]$WartoscZakresu = "",
    [ValidateSet("NORMALNY","CLOSE_ONLY","HALT")]
    [string]$Tryb = "NORMALNY",
    [string]$Powod = "STEROWANIE_OPERATORA"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json

switch ($Zakres) {
    "system" {
        $targets = @($registry.symbols)
    }
    "rodzina" {
        if ([string]::IsNullOrWhiteSpace($WartoscZakresu)) {
            throw "Dla zakresu 'rodzina' podaj WartoscZakresu."
        }
        $targets = @($registry.symbols | Where-Object { $_.session_profile -eq $WartoscZakresu })
    }
    "para" {
        if ([string]::IsNullOrWhiteSpace($WartoscZakresu)) {
            throw "Dla zakresu 'para' podaj WartoscZakresu."
        }
        $targets = @($registry.symbols | Where-Object { Test-RegistryAliasMatch -RegistryItem $_ -Alias $WartoscZakresu })
    }
}

if ($targets.Count -eq 0) {
    throw "Nie znaleziono symboli dla wskazanego zakresu."
}

$requestedMode = switch ($Tryb) {
    "NORMALNY" { "READY" }
    "CLOSE_ONLY" { "CLOSE_ONLY" }
    "HALT" { "HALT" }
}

$changed = @()
foreach ($item in $targets) {
    $canonicalSymbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $aliases = @(Get-RegistrySymbolCandidates -RegistryItem $item)
    $existingAliases = @($aliases | Where-Object {
        Test-Path -LiteralPath (Join-Path $CommonFilesRoot ("state\{0}" -f $_))
    } | Select-Object -Unique)

    $targetAliases = if ($existingAliases.Count -gt 0) {
        $existingAliases
    } else {
        @($aliases | Select-Object -First 2)
    }

    $controlPaths = @()
    foreach ($alias in $targetAliases) {
        if ([string]::IsNullOrWhiteSpace($alias)) { continue }
        $stateDir = Join-Path $CommonFilesRoot ("state\{0}" -f $alias)
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        $controlPath = Join-Path $stateDir "runtime_control.csv"
        @(
            "requested_mode`t$requestedMode"
            "reason_code`t$Powod"
        ) | Set-Content -LiteralPath $controlPath -Encoding ASCII
        $controlPaths += $controlPath
    }

    $changed += [pscustomobject]@{
        symbol = $canonicalSymbol
        broker_symbol = (Get-RegistryBrokerSymbol -RegistryItem $item)
        aliases = @($targetAliases)
        requested_mode = $requestedMode
        reason_code = $Powod
        control_paths = @($controlPaths)
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    zakres = $Zakres
    wartosc_zakresu = $WartoscZakresu
    tryb = $Tryb
    requested_mode = $requestedMode
    powod = $Powod
    changed = $changed
}

$evidenceDir = Join-Path $ProjectRoot "EVIDENCE"
$jsonPath = Join-Path $evidenceDir "runtime_control_set_report.json"
$txtPath = Join-Path $evidenceDir "runtime_control_set_report.txt"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
@(
    "RUNTIME CONTROL SET"
    ("ZAKRES={0}" -f $Zakres)
    ("WARTOSC_ZAKRESU={0}" -f $WartoscZakresu)
    ("TRYB={0}" -f $Tryb)
    ("REQUESTED_MODE={0}" -f $requestedMode)
    ("POWOD={0}" -f $Powod)
    ("LICZBA_SYMBOLI={0}" -f $changed.Count)
) | Set-Content -LiteralPath $txtPath -Encoding UTF8

$report | ConvertTo-Json -Depth 6
