param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Resolve-DomainFromSessionProfile {
    param([string]$SessionProfile)
    switch ([string]$SessionProfile) {
        "FX_MAIN" { return "FX" }
        "FX_ASIA" { return "FX" }
        "FX_CROSS" { return "FX" }
        "METALS_SPOT_PM" { return "METALS" }
        "METALS_FUTURES" { return "METALS" }
        "INDEX_EU" { return "INDICES" }
        "INDEX_US" { return "INDICES" }
        default { return "" }
    }
}

function Read-RuntimeControlFile {
    param([string]$Path)

    $state = [ordered]@{
        requested_mode = ""
        reason_code = ""
        risk_cap = 1.0
        force_flatten = $false
        allowed_direction = "BOTH"
        halt = $false
        paper_only = $false
        close_only = $false
    }

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$state
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $parts = $line -split "`t", 2
        if ($parts.Count -lt 2) { continue }
        switch ($parts[0]) {
            "requested_mode" { $state.requested_mode = [string]$parts[1] }
            "reason_code" { $state.reason_code = [string]$parts[1] }
            "risk_cap" { $state.risk_cap = [double]$parts[1] }
            "force_flatten" { $state.force_flatten = ([int]$parts[1]) -ne 0 }
            "allowed_direction" { $state.allowed_direction = [string]$parts[1] }
        }
    }

    switch ($state.requested_mode.ToUpperInvariant()) {
        "HALT" { $state.halt = $true }
        "PAPER_ONLY" { $state.paper_only = $true }
        "CLOSE_ONLY" { $state.close_only = $true }
    }

    return [pscustomobject]$state
}

function Merge-RuntimeControlState {
    param(
        $SymbolControl,
        $DomainControl
    )

    $effective = [ordered]@{
        requested_mode = "RUN"
        reason_code = ""
        risk_cap = [math]::Min([double]$SymbolControl.risk_cap, [double]$DomainControl.risk_cap)
        force_flatten = ([bool]$SymbolControl.force_flatten -or [bool]$DomainControl.force_flatten)
        allowed_direction = [string]$(if (-not [string]::IsNullOrWhiteSpace([string]$SymbolControl.allowed_direction)) { $SymbolControl.allowed_direction } elseif (-not [string]::IsNullOrWhiteSpace([string]$DomainControl.allowed_direction)) { $DomainControl.allowed_direction } else { "BOTH" })
        source = "NONE"
    }

    if ([bool]$DomainControl.halt) {
        $effective.requested_mode = "HALT"
        $effective.reason_code = [string]$DomainControl.reason_code
        $effective.source = "DOMAIN"
        return [pscustomobject]$effective
    }
    if ([bool]$SymbolControl.halt) {
        $effective.requested_mode = "HALT"
        $effective.reason_code = [string]$SymbolControl.reason_code
        $effective.source = "SYMBOL"
        return [pscustomobject]$effective
    }
    if ([bool]$DomainControl.paper_only -and -not [bool]$SymbolControl.halt) {
        $effective.requested_mode = "PAPER_ONLY"
        $effective.reason_code = [string]$DomainControl.reason_code
        $effective.source = "DOMAIN"
        return [pscustomobject]$effective
    }
    if ([bool]$SymbolControl.paper_only) {
        $effective.requested_mode = "PAPER_ONLY"
        $effective.reason_code = [string]$SymbolControl.reason_code
        $effective.source = "SYMBOL"
        return [pscustomobject]$effective
    }
    if ([bool]$DomainControl.close_only -and -not [bool]$SymbolControl.halt -and -not [bool]$SymbolControl.paper_only) {
        $effective.requested_mode = "CLOSE_ONLY"
        $effective.reason_code = [string]$DomainControl.reason_code
        $effective.source = "DOMAIN"
        return [pscustomobject]$effective
    }
    if ([bool]$SymbolControl.close_only) {
        $effective.requested_mode = "CLOSE_ONLY"
        $effective.reason_code = [string]$SymbolControl.reason_code
        $effective.source = "SYMBOL"
        return [pscustomobject]$effective
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$SymbolControl.reason_code)) {
        $effective.reason_code = [string]$SymbolControl.reason_code
        $effective.source = "SYMBOL"
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$DomainControl.reason_code)) {
        $effective.reason_code = [string]$DomainControl.reason_code
        $effective.source = "DOMAIN"
    }

    return [pscustomobject]$effective
}

$registry = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot "CONFIG\microbots_registry.json") | ConvertFrom-Json
$rows = @()
foreach ($item in $registry.symbols) {
    $symbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $family = [string]$item.session_profile
    $domain = Resolve-DomainFromSessionProfile -SessionProfile $family
    $stateAlias = Resolve-RegistryStateAlias -RegistryItem $item -CommonFilesRoot $CommonFilesRoot
    $symbolControlPath = if ([string]::IsNullOrWhiteSpace($stateAlias)) {
        ""
    }
    else {
        Join-Path $CommonFilesRoot ("state\{0}\runtime_control.csv" -f $stateAlias)
    }
    $domainControlPath = if ([string]::IsNullOrWhiteSpace($domain)) {
        ""
    }
    else {
        Join-Path $CommonFilesRoot ("state\_domains\{0}\runtime_control.csv" -f $domain)
    }
    $symbolControl = Read-RuntimeControlFile -Path $symbolControlPath
    $domainControl = Read-RuntimeControlFile -Path $domainControlPath
    $effective = Merge-RuntimeControlState -SymbolControl $symbolControl -DomainControl $domainControl
    $rows += [pscustomobject]@{
        para_walutowa = $symbol
        state_alias = $stateAlias
        domena = $domain
        symbol_requested_mode = [string]$symbolControl.requested_mode
        domain_requested_mode = [string]$domainControl.requested_mode
        rodzina = $family
        requested_mode = [string]$effective.requested_mode
        reason_code = [string]$effective.reason_code
        allowed_direction = [string]$effective.allowed_direction
        force_flatten = [bool]$effective.force_flatten
        source = [string]$effective.source
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
    $txt += ("{0} | rodzina={1} | domena={2} | requested_mode={3} | allowed_direction={4} | force_flatten={5} | source={6} | reason={7}" -f $row.para_walutowa, $row.rodzina, $row.domena, $row.requested_mode, $row.allowed_direction, $row.force_flatten, $row.source, $row.reason_code)
}
$txt | Set-Content -LiteralPath $txtPath -Encoding UTF8

$summary | ConvertTo-Json -Depth 6
