param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "",
    [ValidateSet("DEFAULT","LAPTOP_RESEARCH","PAPER_LIVE","BROKER_PARITY_FIRST_WAVE")]
    [string]$RuntimeProfile = "DEFAULT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Parse-WindowMinutes {
    param([string]$Text)
    $parts = $Text -split "-", 2
    if ($parts.Count -ne 2) { return $null }
    $start = [datetime]::ParseExact($parts[0], "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    $end = [datetime]::ParseExact($parts[1], "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    return [pscustomobject]@{
        start = ($start.Hour * 60 + $start.Minute)
        end = ($end.Hour * 60 + $end.Minute)
    }
}

function Get-OptionalPropertyValue {
    param(
        $Object,
        [string]$Name
    )
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Resolve-WindowText {
    param($Window, [bool]$IsDst)
    $pl = Get-OptionalPropertyValue -Object $Window -Name "pl"
    if ($null -ne $pl) { return [string]$pl }

    $summer = Get-OptionalPropertyValue -Object $Window -Name "summer_pl"
    $winter = Get-OptionalPropertyValue -Object $Window -Name "winter_pl"
    if ($IsDst -and $null -ne $summer) { return [string]$summer }
    if (-not $IsDst -and $null -ne $winter) { return [string]$winter }
    if ($null -ne $summer) { return [string]$summer }
    if ($null -ne $winter) { return [string]$winter }
    return ""
}

function Resolve-WindowState {
    param([string]$WindowId,[string]$Mode)
    if ($Mode -eq "TRADE") { return "LIVE" }
    if ($Mode -eq "OBSERVATION_ONLY") {
        if ($WindowId -like "*PREWARM*") { return "PREWARM" }
        return "PAPER_SHADOW"
    }
    if ($Mode -eq "FUTURE_RESEARCH") { return "RESERVE_RESEARCH" }
    return "SLEEP"
}

function Read-KeyValueStateFile {
    param([string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $map[[string]$parts[0]] = [string]$parts[1]
    }

    return $map
}

function Get-MapBool {
    param($Map,[string]$Key,[bool]$Default = $false)
    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) { return $Default }
    return ([int]$Map[$Key]) -ne 0
}

function Get-MapDouble {
    param($Map,[string]$Key,[double]$Default = 0.0)
    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) { return $Default }
    return [double]::Parse([string]$Map[$Key],[System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-MapString {
    param($Map,[string]$Key,[string]$Default = "")
    if ($null -eq $Map -or -not $Map.ContainsKey($Key)) { return $Default }
    return [string]$Map[$Key]
}

function Split-FamilyHint {
    param([string]$FamilyHint)
    if ([string]::IsNullOrWhiteSpace($FamilyHint)) { return @() }
    return @($FamilyHint.Split('+',[System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Resolve-TimeZoneInfo {
    param([string]$TimeZoneName)

    $candidates = switch ([string]$TimeZoneName) {
        "America/New_York" { @("Eastern Standard Time","America/New_York") ; break }
        "Europe/Warsaw" { @("Central European Standard Time","Europe/Warsaw") ; break }
        "UTC" { @("UTC") ; break }
        default { @($TimeZoneName) }
    }

    foreach ($candidate in $candidates) {
        try {
            return [TimeZoneInfo]::FindSystemTimeZoneById($candidate)
        }
        catch {
        }
    }

    throw "Cannot resolve timezone '$TimeZoneName' on this host."
}

function Parse-HHmm {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Missing HH:mm text."
    }

    return [datetime]::ParseExact($Text, "HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
}

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

function Merge-CoordinatorRules {
    param(
        $BaseRules,
        $OverrideRules
    )

    $merged = [ordered]@{}
    if ($null -ne $BaseRules) {
        foreach ($prop in $BaseRules.PSObject.Properties) {
            $merged[$prop.Name] = $prop.Value
        }
    }

    if ($null -ne $OverrideRules) {
        foreach ($prop in $OverrideRules.PSObject.Properties) {
            $merged[$prop.Name] = $prop.Value
        }
    }

    return [pscustomobject]$merged
}

function Get-NormalizedSymbolCode {
    param($RegistryItem)

    $codeSymbol = Get-OptionalPropertyValue -Object $RegistryItem -Name "code_symbol"
    if (-not [string]::IsNullOrWhiteSpace([string]$codeSymbol)) {
        return (([string]$codeSymbol).ToUpperInvariant() -replace '[^A-Z0-9]', '')
    }

    $symbol = [string](Get-OptionalPropertyValue -Object $RegistryItem -Name "symbol")
    if ([string]::IsNullOrWhiteSpace($symbol)) {
        return ""
    }

    $base = $symbol.Split('.',2)[0]
    return ($base.ToUpperInvariant() -replace '[^A-Z0-9]', '')
}

function Get-StateDirAliases {
    param(
        [string]$RegistrySymbol,
        [string]$BrokerSymbol,
        [string]$CodeSymbol
    )

    $aliases = New-Object System.Collections.Generic.List[string]

    function Add-Alias {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        if ($aliases -notcontains $Value) {
            $aliases.Add($Value) | Out-Null
        }
    }

    Add-Alias -Value $RegistrySymbol

    if (-not [string]::IsNullOrWhiteSpace($RegistrySymbol)) {
        $base = $RegistrySymbol.Split('.',2)[0]
        Add-Alias -Value $base
    }

    Add-Alias -Value $BrokerSymbol
    if (-not [string]::IsNullOrWhiteSpace($BrokerSymbol)) {
        $brokerBase = $BrokerSymbol.Split('.',2)[0]
        Add-Alias -Value $brokerBase
    }

    Add-Alias -Value $CodeSymbol

    return @($aliases)
}

function New-RolloverGuardState {
    param([string]$Code,[string]$RegistrySymbol,[string]$Domain,[string]$SessionProfile)
    return [ordered]@{
        code_symbol = $Code
        registry_symbol = $RegistrySymbol
        domain = $Domain
        session_profile = $SessionProfile
        block = $false
        force_flatten = $false
        reason_code = "NONE"
        source = "NONE"
        matched_events = @()
    }
}

function Test-TimeAnchorWindow {
    param(
        [datetime]$Now,
        [datetime]$Anchor,
        [int]$BeforeMinutes,
        [int]$AfterMinutes
    )

    $start = $Anchor.AddMinutes(-1 * [math]::Max(0,$BeforeMinutes))
    $end = $Anchor.AddMinutes([math]::Max(0,$AfterMinutes))
    return ($Now -ge $start -and $Now -le $end)
}

function Get-QuarterlyRolloverDate {
    param(
        [int]$Year,
        [int]$Month,
        [int]$OffsetDays = -2
    )

    $first = Get-Date -Year $Year -Month $Month -Day 1 -Hour 0 -Minute 0 -Second 0
    $daysToFriday = ((5 - [int]$first.DayOfWeek) + 7) % 7
    $thirdFriday = $first.AddDays($daysToFriday + 14)
    return $thirdFriday.Date.AddDays($OffsetDays)
}

function Get-QuarterlyAnchorNy {
    param(
        [datetime]$NowNy,
        $QuarterlyConfig
    )

    if (-not [bool]$QuarterlyConfig.enabled) { return $null }
    if (-not [bool]$QuarterlyConfig.auto_index_quarterly) { return $null }

    $months = @([int[]]$QuarterlyConfig.quarter_months)
    if ($months.Count -eq 0 -or -not ($months -contains [int]$NowNy.Month)) {
        return $null
    }

    $offset = [int]$QuarterlyConfig.quarter_roll_offset_days
    $expectedDate = Get-QuarterlyRolloverDate -Year $NowNy.Year -Month $NowNy.Month -OffsetDays $offset
    if ($NowNy.Date -ne $expectedDate.Date) {
        return $null
    }

    $anchorClock = Parse-HHmm -Text ([string]$QuarterlyConfig.anchor_time_new_york)
    return Get-Date -Year $NowNy.Year -Month $NowNy.Month -Day $NowNy.Day -Hour $anchorClock.Hour -Minute $anchorClock.Minute -Second 0
}

function Get-ManualEventAnchorNy {
    param(
        $Event,
        [System.TimeZoneInfo]$NyTimeZone
    )

    $eventTzName = [string](Get-OptionalPropertyValue -Object $Event -Name "timezone")
    if ([string]::IsNullOrWhiteSpace($eventTzName)) {
        $eventTzName = "America/New_York"
    }

    $eventTz = Resolve-TimeZoneInfo -TimeZoneName $eventTzName
    $eventDate = [datetime]::ParseExact([string]$Event.date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    $eventClock = Parse-HHmm -Text ([string]$Event.time)
    $localEvent = Get-Date -Year $eventDate.Year -Month $eventDate.Month -Day $eventDate.Day -Hour $eventClock.Hour -Minute $eventClock.Minute -Second 0
    $localEvent = [datetime]::SpecifyKind($localEvent,[System.DateTimeKind]::Unspecified)
    $eventOffset = $eventTz.GetUtcOffset($localEvent)
    $utcEvent = [datetimeoffset]::new($localEvent,$eventOffset).UtcDateTime
    return [TimeZoneInfo]::ConvertTimeFromUtc($utcEvent,$NyTimeZone)
}

function Test-EventMatchesSymbol {
    param(
        $Event,
        [string]$CodeSymbol
    )

    foreach ($rawSymbol in @($Event.symbols)) {
        if (([string]$rawSymbol).ToUpperInvariant() -replace '[^A-Z0-9]', '' -eq $CodeSymbol) {
            return $true
        }
    }
    return $false
}

function Set-RolloverGuardBlock {
    param(
        [hashtable]$Guard,
        [string]$ReasonCode,
        [string]$SourceLabel
    )

    if (-not $Guard.block) {
        $Guard.block = $true
        $Guard.reason_code = $ReasonCode
        $Guard.source = $SourceLabel
    }
    if ($Guard.matched_events -notcontains $SourceLabel) {
        $Guard.matched_events += $SourceLabel
    }
}

function Set-RolloverGuardForceFlatten {
    param(
        [hashtable]$Guard,
        [string]$ReasonCode,
        [string]$SourceLabel
    )

    $Guard.force_flatten = $true
    $Guard.block = $true
    $Guard.reason_code = $ReasonCode
    $Guard.source = $SourceLabel
    if ($Guard.matched_events -notcontains $SourceLabel) {
        $Guard.matched_events += $SourceLabel
    }
}

function Get-FamilyAssessment {
    param(
        [string]$CommonRoot,
        [string[]]$Families
    )

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($family in $Families) {
        $path = Join-Path $CommonRoot ("state\\_families\\{0}\\tuning_family_policy.csv" -f $family)
        $raw = Read-KeyValueStateFile -Path $path
        if ($raw.Count -eq 0) {
            $rows.Add([pscustomobject]@{
                family = $family
                present = $false
                trusted_data = $false
                paper_mode_active = $false
                family_daily_loss_pct = 0.0
                trust_reason = "MISSING"
            })
            continue
        }

        $rows.Add([pscustomobject]@{
            family = $family
            present = $true
            trusted_data = (Get-MapBool -Map $raw -Key "trusted_data")
            paper_mode_active = (Get-MapBool -Map $raw -Key "paper_mode_active")
            family_daily_loss_pct = (Get-MapDouble -Map $raw -Key "family_daily_loss_pct")
            trust_reason = (Get-MapString -Map $raw -Key "trust_reason" -Default "UNASSESSED")
        })
    }

    $presentCount = @($rows | Where-Object { $_.present }).Count
    $trustedCount = @($rows | Where-Object { $_.present -and $_.trusted_data }).Count
    $paperRuntimeActive = @($rows | Where-Object { $_.paper_mode_active }).Count -gt 0
    $paperLockRow = @($rows | Where-Object { $_.trust_reason -eq "FAMILY_DAILY_LOSS_HARD" } | Select-Object -First 1)
    $paperDefensiveRow = @($rows | Where-Object { $_.trust_reason -eq "FAMILY_DAILY_LOSS_DEFENSIVE" } | Select-Object -First 1)
    $maxLoss = 0.0
    foreach ($row in $rows) {
        if ([double]$row.family_daily_loss_pct -gt $maxLoss) {
            $maxLoss = [double]$row.family_daily_loss_pct
        }
    }

    $paperLockReason = "NONE"
    if ($paperLockRow.Count -gt 0) {
        $paperLockReason = "FAMILY_DAILY_LOSS_HARD"
    }

    $paperDefensiveReason = "NONE"
    if ($paperDefensiveRow.Count -gt 0) {
        $paperDefensiveReason = "FAMILY_DAILY_LOSS_DEFENSIVE"
    }

    return [pscustomobject]@{
        families = @($Families)
        present_count = $presentCount
        trusted_count = $trustedCount
        trusted = ($presentCount -gt 0 -and $trustedCount -eq $presentCount)
        paper_runtime_active = $paperRuntimeActive
        paper_lock = ($paperLockRow.Count -gt 0)
        paper_lock_reason = $paperLockReason
        paper_defensive = ($paperDefensiveRow.Count -gt 0)
        paper_defensive_reason = $paperDefensiveReason
        max_family_daily_loss_pct = $maxLoss
    }
}

function Get-FleetAssessment {
    param([string]$CommonRoot)

    $path = Join-Path $CommonRoot "state\\_coordinator\\tuning_coordinator_state.csv"
    $raw = Read-KeyValueStateFile -Path $path
    if ($raw.Count -eq 0) {
        return [pscustomobject]@{
            present = $false
            trusted_data = $false
            paper_runtime_active = $false
            paper_lock = $false
            paper_lock_reason = "MISSING"
            paper_defensive = $false
            paper_defensive_reason = "MISSING"
            fleet_daily_loss_pct = 0.0
            trust_reason = "MISSING"
        }
    }

    $paperModeActive = Get-MapBool -Map $raw -Key "paper_mode_active"
    $trustReason = Get-MapString -Map $raw -Key "trust_reason" -Default "UNASSESSED"
    $paperLockReason = "NONE"
    if ($trustReason -eq "FLEET_DAILY_LOSS_HARD") {
        $paperLockReason = "FLEET_DAILY_LOSS_HARD"
    }

    $paperDefensiveReason = "NONE"
    if ($trustReason -eq "FLEET_DAILY_LOSS_DEFENSIVE") {
        $paperDefensiveReason = "FLEET_DAILY_LOSS_DEFENSIVE"
    }

    return [pscustomobject]@{
        present = $true
        trusted_data = (Get-MapBool -Map $raw -Key "trusted_data")
        paper_runtime_active = $paperModeActive
        paper_lock = ($trustReason -eq "FLEET_DAILY_LOSS_HARD")
        paper_lock_reason = $paperLockReason
        paper_defensive = ($trustReason -eq "FLEET_DAILY_LOSS_DEFENSIVE")
        paper_defensive_reason = $paperDefensiveReason
        fleet_daily_loss_pct = (Get-MapDouble -Map $raw -Key "fleet_daily_loss_pct")
        trust_reason = $trustReason
    }
}

function Resolve-RequestedMode {
    param(
        $State,
        [bool]$ActiveRuntime,
        [string]$ManualOverride,
        $Rules,
        [double]$LiveDefensiveRiskCap,
        [double]$PaperDefensiveRiskCap,
        [double]$ReentryProbationRiskCap,
        [double]$ReserveTakeoverRiskCap
    )

    $override = ([string]$ManualOverride).ToUpperInvariant()
    if ($override -eq "HALT") {
        return [pscustomobject]@{ requested_mode = [string]$Rules.manual_halt_requested_mode; reason = "DOMAIN_MANUAL_HALT"; source = "MANUAL"; risk_cap = 1.0; state_override = "SLEEP"; force_flatten = $false }
    }
    if ($override -eq "PAPER_ONLY" -or $override -eq "PAPER_SHADOW") {
        return [pscustomobject]@{ requested_mode = [string]$Rules.manual_paper_requested_mode; reason = "DOMAIN_MANUAL_PAPER"; source = "MANUAL"; risk_cap = 1.0; state_override = "PAPER_ACTIVE"; force_flatten = $false }
    }
    if ($override -eq "CLOSE_ONLY") {
        return [pscustomobject]@{ requested_mode = [string]$Rules.manual_close_only_requested_mode; reason = "DOMAIN_MANUAL_CLOSE_ONLY"; source = "MANUAL"; risk_cap = 1.0; state_override = "SLEEP"; force_flatten = $false }
    }

    if ([bool]$State.rollover_block) {
        return [pscustomobject]@{
            requested_mode = [string]$Rules.manual_close_only_requested_mode
            reason = [string]$State.rollover_reason
            source = "ROLLOVER"
            risk_cap = 1.0
            state_override = "ROLLOVER_BLOCK"
            force_flatten = [bool]$State.rollover_force_flatten
        }
    }

    if (-not $ActiveRuntime) {
        return [pscustomobject]@{ requested_mode = [string]$Rules.observation_requested_mode; reason = "DOMAIN_NOT_DEPLOYED"; source = "RUNTIME"; risk_cap = 1.0; state_override = "SLEEP"; force_flatten = $false }
    }

    if ([string]$State.window_state -eq "SLEEP") {
        return [pscustomobject]@{ requested_mode = [string]$Rules.sleep_requested_mode; reason = "DOMAIN_SLEEP"; source = "WINDOW"; risk_cap = 1.0; state_override = "SLEEP"; force_flatten = $false }
    }

    if ($State.fleet_paper_lock) {
        return [pscustomobject]@{ requested_mode = [string]$Rules.paper_requested_mode; reason = $State.fleet_paper_lock_reason; source = "FLEET_LOCK"; risk_cap = 1.0; state_override = "PAPER_ACTIVE"; force_flatten = $false }
    }

    if ($State.fleet_paper_defensive) {
        $paperDefensiveMode = [string]$Rules.paper_defensive_requested_mode
        if ([string]::IsNullOrWhiteSpace($paperDefensiveMode)) {
            $paperDefensiveMode = [string]$Rules.trade_requested_mode
        }
        return [pscustomobject]@{
            requested_mode = $paperDefensiveMode
            reason = $State.fleet_paper_defensive_reason
            source = "FLEET_DEFENSIVE"
            risk_cap = [math]::Max(0.0,[math]::Min(1.0,$PaperDefensiveRiskCap))
            state_override = "PAPER_DEFENSIVE"
            force_flatten = $false
        }
    }

    if ($State.family_paper_lock) {
        if ([string]$State.window_state -eq "LIVE" -and $State.reentry_ready) {
            return [pscustomobject]@{
                requested_mode = [string]$Rules.trade_requested_mode
                reason = "DOMAIN_REENTRY_PROBATION"
                source = "REENTRY"
                risk_cap = [math]::Max(0.0,[math]::Min(1.0,$ReentryProbationRiskCap))
                state_override = "REENTRY_PROBATION"
                force_flatten = $false
            }
        }
        return [pscustomobject]@{ requested_mode = [string]$Rules.paper_requested_mode; reason = $State.family_paper_lock_reason; source = "FAMILY_LOCK"; risk_cap = 1.0; state_override = "PAPER_ACTIVE"; force_flatten = $false }
    }

    if ($State.family_paper_defensive) {
        $paperDefensiveMode = [string]$Rules.paper_defensive_requested_mode
        if ([string]::IsNullOrWhiteSpace($paperDefensiveMode)) {
            $paperDefensiveMode = [string]$Rules.trade_requested_mode
        }
        return [pscustomobject]@{
            requested_mode = $paperDefensiveMode
            reason = $State.family_paper_defensive_reason
            source = "FAMILY_DEFENSIVE"
            risk_cap = [math]::Max(0.0,[math]::Min(1.0,$PaperDefensiveRiskCap))
            state_override = "PAPER_DEFENSIVE"
            force_flatten = $false
        }
    }

    if ([string]$State.window_state -eq "RESERVE_RESEARCH" -and -not [string]::IsNullOrWhiteSpace([string]$State.reserve_requested_by)) {
        return [pscustomobject]@{
            requested_mode = [string]$Rules.trade_requested_mode
            reason = "DOMAIN_RESERVE_TAKEOVER"
            source = "RESERVE"
            risk_cap = [math]::Max(0.0,[math]::Min(1.0,$ReserveTakeoverRiskCap))
            state_override = "LIVE_DEFENSIVE"
            force_flatten = $false
        }
    }

    if ([string]$State.window_state -eq "LIVE" -and $State.defensive_mode) {
        return [pscustomobject]@{
            requested_mode = [string]$Rules.trade_requested_mode
            reason = "DOMAIN_LIVE_DEFENSIVE"
            source = "DEFENSIVE"
            risk_cap = [math]::Max(0.0,[math]::Min(1.0,$LiveDefensiveRiskCap))
            state_override = "LIVE_DEFENSIVE"
            force_flatten = $false
        }
    }

    switch ([string]$State.window_state) {
        "LIVE" { return [pscustomobject]@{ requested_mode = [string]$Rules.trade_requested_mode; reason = "DOMAIN_ACTIVE_WINDOW"; source = "WINDOW"; risk_cap = 1.0; state_override = "LIVE"; force_flatten = $false } }
        "PREWARM" { return [pscustomobject]@{ requested_mode = [string]$Rules.prewarm_requested_mode; reason = "DOMAIN_PREWARM"; source = "WINDOW"; risk_cap = 1.0; state_override = "PREWARM"; force_flatten = $false } }
        "PAPER_SHADOW" { return [pscustomobject]@{ requested_mode = [string]$Rules.observation_requested_mode; reason = "DOMAIN_OBSERVATION"; source = "WINDOW"; risk_cap = 1.0; state_override = "PAPER_SHADOW"; force_flatten = $false } }
        "RESERVE_RESEARCH" { return [pscustomobject]@{ requested_mode = [string]$Rules.observation_requested_mode; reason = "DOMAIN_RESEARCH"; source = "WINDOW"; risk_cap = 1.0; state_override = "RESERVE_RESEARCH"; force_flatten = $false } }
        default { return [pscustomobject]@{ requested_mode = [string]$Rules.sleep_requested_mode; reason = "DOMAIN_SLEEP"; source = "WINDOW"; risk_cap = 1.0; state_override = "SLEEP"; force_flatten = $false } }
    }
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($CommonFilesRoot)) {
    $CommonFilesRoot = Join-Path $env:APPDATA "MetaQuotes\\Terminal\\Common\\Files\\MAKRO_I_MIKRO_BOT"
}

$registryPath = Join-Path $projectPath "CONFIG\\microbots_registry.json"
$coordPath = Join-Path $projectPath "CONFIG\\session_capital_coordinator_v1.json"
$matrixPath = Join-Path $projectPath "CONFIG\\session_window_matrix_v1.json"
$capitalPath = Join-Path $projectPath "CONFIG\\capital_risk_contract_v1.json"
$rolloverPath = Join-Path $projectPath "CONFIG\\rollover_guard_v1.json"
foreach ($path in @($registryPath,$coordPath,$matrixPath,$capitalPath,$rolloverPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required file: $path" }
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$coord = Get-Content -LiteralPath $coordPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
$capital = Get-Content -LiteralPath $capitalPath -Raw -Encoding UTF8 | ConvertFrom-Json
$rollover = Get-Content -LiteralPath $rolloverPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeProfileConfig = $null
if ($coord.PSObject.Properties.Name -contains "runtime_profiles") {
    $runtimeProfileConfig = $coord.runtime_profiles.PSObject.Properties[$RuntimeProfile]
}
$effectiveRules = Merge-CoordinatorRules -BaseRules $coord.rules -OverrideRules $(if ($null -ne $runtimeProfileConfig) { $runtimeProfileConfig.Value.rules_override } else { $null })
$ignoreFamilyPaperLock = [bool](Get-OptionalPropertyValue -Object $(if ($null -ne $runtimeProfileConfig) { $runtimeProfileConfig.Value } else { $null }) -Name "ignore_family_paper_lock")
$ignoreFamilyPaperDefensive = [bool](Get-OptionalPropertyValue -Object $(if ($null -ne $runtimeProfileConfig) { $runtimeProfileConfig.Value } else { $null }) -Name "ignore_family_paper_defensive")
$ignoreFleetPaperLock = [bool](Get-OptionalPropertyValue -Object $(if ($null -ne $runtimeProfileConfig) { $runtimeProfileConfig.Value } else { $null }) -Name "ignore_fleet_paper_lock")
$ignoreFleetPaperDefensive = [bool](Get-OptionalPropertyValue -Object $(if ($null -ne $runtimeProfileConfig) { $runtimeProfileConfig.Value } else { $null }) -Name "ignore_fleet_paper_defensive")
$fleetAssessment = Get-FleetAssessment -CommonRoot $CommonFilesRoot

$reentryRecoverFraction = [double]$effectiveRules.reentry_recover_fraction
$defensiveFamilyLossFraction = [double]$effectiveRules.defensive_family_loss_fraction
$paperDefensiveRiskCap = if ($null -ne $effectiveRules.PSObject.Properties["paper_defensive_risk_cap"]) { [double]$effectiveRules.paper_defensive_risk_cap } else { [double]$effectiveRules.reentry_probation_risk_cap }
$reentryProbationRiskCap = [double]$effectiveRules.reentry_probation_risk_cap
$reserveTakeoverRiskCap = [double]$effectiveRules.reserve_takeover_risk_cap
$capitalThresholdProfileName = if ($RuntimeProfile -in @("PAPER_LIVE","LAPTOP_RESEARCH","BROKER_PARITY_FIRST_WAVE")) { "paper" } else { "live" }
$capitalThresholdProfile = if ($capitalThresholdProfileName -eq "paper") { $capital.paper } else { $capital.live }
$familyReentryThreshold = [double]$capitalThresholdProfile.family_hard_daily_loss_pct * $reentryRecoverFraction
$fleetReentryThreshold = [double]$capitalThresholdProfile.account_hard_daily_loss_pct * $reentryRecoverFraction
$familyDefensiveThreshold = [double]$capitalThresholdProfile.family_hard_daily_loss_pct * $defensiveFamilyLossFraction
$fleetSoftThreshold = [double]$capitalThresholdProfile.account_soft_daily_loss_pct
$liveDefensiveRiskCap = [double]$capital.live.soft_loss_risk_factor

$tzPl = Resolve-TimeZoneInfo -TimeZoneName "Europe/Warsaw"
$tzNy = Resolve-TimeZoneInfo -TimeZoneName "America/New_York"
$nowUtc = (Get-Date).ToUniversalTime()
$nowPl = [TimeZoneInfo]::ConvertTimeFromUtc($nowUtc,$tzPl)
$nowNy = [TimeZoneInfo]::ConvertTimeFromUtc($nowUtc,$tzNy)
$isDst = $tzPl.IsDaylightSavingTime($nowPl)
$nowMinutes = ($nowPl.Hour * 60 + $nowPl.Minute)

$symbolEntries = @()
foreach ($item in $registry.symbols) {
    $codeSymbol = Get-NormalizedSymbolCode -RegistryItem $item
    $registrySymbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $brokerSymbol = Get-RegistryBrokerSymbol -RegistryItem $item
    $sessionProfile = [string]$item.session_profile
    $symbolEntries += [pscustomobject]@{
        registry_symbol = $registrySymbol
        broker_symbol = $brokerSymbol
        code_symbol = $codeSymbol
        session_profile = $sessionProfile
        domain = (Resolve-DomainFromSessionProfile -SessionProfile $sessionProfile)
        state_dir_aliases = @(Get-StateDirAliases -RegistrySymbol $registrySymbol -BrokerSymbol $brokerSymbol -CodeSymbol $codeSymbol)
    }
}

$groupMatrixMap = @{}
foreach ($entry in $matrix.groups) { $groupMatrixMap[[string]$entry.group] = $entry }

$domainStates = @{}
foreach ($domain in $coord.domains) {
    $domainStates[[string]$domain.domain] = [ordered]@{
        domain = [string]$domain.domain
        window_state = "SLEEP"
        state = "SLEEP"
        active_group = ""
        active_window_id = ""
        family_hint = ""
        budget_share_of_day = 0.0
        reserve_domains = @()
        active_runtime = [bool]$domain.active_runtime
        manual_override = [string]$domain.manual_override
        requested_mode = [string]$effectiveRules.sleep_requested_mode
        reason_code = "DOMAIN_SLEEP"
        requested_mode_source = "WINDOW"
        family_paper_lock = $false
        family_paper_lock_reason = "NONE"
        family_paper_defensive = $false
        family_paper_defensive_reason = "NONE"
        family_trusted = $false
        family_max_daily_loss_pct = 0.0
        fleet_paper_lock = $false
        fleet_paper_lock_reason = "NONE"
        fleet_paper_defensive = $false
        fleet_paper_defensive_reason = "NONE"
        fleet_daily_loss_pct = 0.0
        reentry_ready = $false
        paper_lock = $false
        paper_lock_reason = "NONE"
        paper_defensive = $false
        paper_defensive_reason = "NONE"
        defensive_mode = $false
        requested_risk_cap = 1.0
        requested_force_flatten = $false
        reserve_candidate = ""
        reserve_requested_by = ""
        reserve_activated = $false
        rollover_block = $false
        rollover_force_flatten = $false
        rollover_reason = "NONE"
    }
}

$stateRank = @{
    "SLEEP" = 0
    "RESERVE_RESEARCH" = 1
    "PAPER_SHADOW" = 2
    "PAPER_DEFENSIVE" = 2
    "PREWARM" = 3
    "LIVE" = 4
}

$activeGroups = New-Object System.Collections.Generic.List[object]
foreach ($group in $coord.groups) {
    $groupName = [string]$group.group
    if (-not $groupMatrixMap.ContainsKey($groupName)) { continue }
    $matrixGroup = $groupMatrixMap[$groupName]
    foreach ($window in $matrixGroup.operator_windows_pl) {
        $windowText = Resolve-WindowText -Window $window -IsDst $isDst
        if ([string]::IsNullOrWhiteSpace($windowText) -or $windowText -eq "DST_DEPENDENT_US_OPEN" -or $windowText -eq "DST_DEPENDENT_US_CLOSE") { continue }
        $parsed = Parse-WindowMinutes -Text $windowText
        if ($null -eq $parsed) { continue }
        if ($nowMinutes -ge $parsed.start -and $nowMinutes -lt $parsed.end) {
            $windowState = Resolve-WindowState -WindowId ([string]$window.window_id) -Mode ([string]$window.mode)
            $activeGroups.Add([pscustomobject]@{
                group = $groupName
                domain = [string]$group.domain
                family_hint = [string]$group.family_hint
                budget_share_of_day = [double]$group.budget_share_of_day
                reserve_domains = @([string[]]$group.reserve_domains)
                window_id = [string]$window.window_id
                mode = [string]$window.mode
                window_state = $windowState
                pl = $windowText
            })
        }
    }
}

foreach ($active in $activeGroups) {
    $domain = [string]$active.domain
    if (-not $domainStates.ContainsKey($domain)) { continue }
    $current = $domainStates[$domain]
    if ($stateRank[$active.window_state] -gt $stateRank[[string]$current.state]) {
        $current.window_state = [string]$active.window_state
        $current.state = [string]$active.window_state
        $current.active_group = [string]$active.group
        $current.active_window_id = [string]$active.window_id
        $current.family_hint = [string]$active.family_hint
        $current.budget_share_of_day = [double]$active.budget_share_of_day
        $current.reserve_domains = @([string[]]$active.reserve_domains)
    }
}

$dailyRolloverBlock = $false
$dailyRolloverForceFlatten = $false
$dailyRolloverReason = "NONE"
if ([bool]$rollover.enabled -and [bool]$rollover.daily.enabled) {
    $dailyAnchorClock = Parse-HHmm -Text ([string]$rollover.daily.anchor_time_new_york)
    $dailyAnchorNy = Get-Date -Year $nowNy.Year -Month $nowNy.Month -Day $nowNy.Day -Hour $dailyAnchorClock.Hour -Minute $dailyAnchorClock.Minute -Second 0
    $dailyRolloverBlock = Test-TimeAnchorWindow -Now $nowNy -Anchor $dailyAnchorNy -BeforeMinutes ([int]$rollover.daily.block_before_min) -AfterMinutes ([int]$rollover.daily.block_after_min)
    $dailyRolloverForceFlatten = Test-TimeAnchorWindow -Now $nowNy -Anchor $dailyAnchorNy -BeforeMinutes ([int]$rollover.daily.force_flatten_before_min) -AfterMinutes 0
    if ($dailyRolloverForceFlatten) {
        $dailyRolloverReason = "ROLLOVER_DAILY_FORCE_FLATTEN"
    }
    elseif ($dailyRolloverBlock) {
        $dailyRolloverReason = "ROLLOVER_DAILY_BLOCK"
    }
}

if ($dailyRolloverBlock) {
    foreach ($affectedDomain in @($rollover.daily.affected_domains)) {
        $domainKey = [string]$affectedDomain
        if (-not $domainStates.ContainsKey($domainKey)) { continue }
        $domainStates[$domainKey].rollover_block = $true
        $domainStates[$domainKey].rollover_force_flatten = $dailyRolloverForceFlatten
        $domainStates[$domainKey].rollover_reason = $dailyRolloverReason
    }
}

$symbolRolloverStates = @{}
foreach ($entry in $symbolEntries) {
    $codeSymbol = [string]$entry.code_symbol
    if ([string]::IsNullOrWhiteSpace($codeSymbol)) { continue }
    $symbolRolloverStates[$codeSymbol] = (New-RolloverGuardState -Code $codeSymbol -RegistrySymbol ([string]$entry.registry_symbol) -Domain ([string]$entry.domain) -SessionProfile ([string]$entry.session_profile))
}

if ([bool]$rollover.enabled) {
    $quarterlyAnchorNy = Get-QuarterlyAnchorNy -NowNy $nowNy -QuarterlyConfig $rollover.quarterly
    $quarterlyAutoSymbols = @([string[]]$rollover.quarterly.auto_symbols | ForEach-Object { ([string]$_).ToUpperInvariant() -replace '[^A-Z0-9]', '' })

    foreach ($codeSymbol in @($symbolRolloverStates.Keys)) {
        $guard = $symbolRolloverStates[$codeSymbol]

        if ($null -ne $quarterlyAnchorNy -and $quarterlyAutoSymbols -contains $codeSymbol) {
            if (Test-TimeAnchorWindow -Now $nowNy -Anchor $quarterlyAnchorNy -BeforeMinutes ([int]$rollover.quarterly.block_before_min) -AfterMinutes ([int]$rollover.quarterly.block_after_min)) {
                Set-RolloverGuardBlock -Guard $guard -ReasonCode "ROLLOVER_QUARTERLY_BLOCK" -SourceLabel "AUTO_QUARTERLY"
            }
            if (Test-TimeAnchorWindow -Now $nowNy -Anchor $quarterlyAnchorNy -BeforeMinutes ([int]$rollover.quarterly.force_flatten_before_min) -AfterMinutes 0) {
                Set-RolloverGuardForceFlatten -Guard $guard -ReasonCode "ROLLOVER_QUARTERLY_FORCE_FLATTEN" -SourceLabel "AUTO_QUARTERLY"
            }
        }

        foreach ($event in @($rollover.manual_events)) {
            if (-not (Test-EventMatchesSymbol -Event $event -CodeSymbol $codeSymbol)) { continue }
            $anchorNy = Get-ManualEventAnchorNy -Event $event -NyTimeZone $tzNy
            $sourceLabel = "MANUAL_{0}_{1}" -f ([string]$event.date),$codeSymbol
            $blockBefore = [int](Get-OptionalPropertyValue -Object $event -Name "block_before_min")
            $blockAfter = [int](Get-OptionalPropertyValue -Object $event -Name "block_after_min")
            $forceBefore = [int](Get-OptionalPropertyValue -Object $event -Name "force_flatten_before_min")

            if (Test-TimeAnchorWindow -Now $nowNy -Anchor $anchorNy -BeforeMinutes $blockBefore -AfterMinutes $blockAfter) {
                Set-RolloverGuardBlock -Guard $guard -ReasonCode "ROLLOVER_MANUAL_BLOCK" -SourceLabel $sourceLabel
            }
            if (Test-TimeAnchorWindow -Now $nowNy -Anchor $anchorNy -BeforeMinutes $forceBefore -AfterMinutes 0) {
                Set-RolloverGuardForceFlatten -Guard $guard -ReasonCode "ROLLOVER_MANUAL_FORCE_FLATTEN" -SourceLabel $sourceLabel
            }
        }
    }
}

foreach ($domainName in @($domainStates.Keys)) {
    $state = $domainStates[$domainName]
    $families = Split-FamilyHint -FamilyHint ([string]$state.family_hint)
    $familyAssessment = Get-FamilyAssessment -CommonRoot $CommonFilesRoot -Families $families

    $state.family_paper_lock = [bool]$familyAssessment.paper_lock
    $state.family_paper_lock_reason = if ($ignoreFamilyPaperLock -and [bool]$familyAssessment.paper_lock) { "IGNORED_FOR_BROKER_PARITY_FIRST_WAVE" } else { [string]$familyAssessment.paper_lock_reason }
    $state.family_paper_defensive = if ($ignoreFamilyPaperDefensive) { $false } else { [bool]$familyAssessment.paper_defensive }
    $state.family_paper_defensive_reason = if ($ignoreFamilyPaperDefensive -and [bool]$familyAssessment.paper_defensive) { "IGNORED_FOR_BROKER_PARITY_FIRST_WAVE" } else { [string]$familyAssessment.paper_defensive_reason }
    $state.family_paper_lock_observed = [bool]$familyAssessment.paper_lock
    $state.family_paper_lock_reason_observed = [string]$familyAssessment.paper_lock_reason
    $state.family_paper_lock_ignored = $ignoreFamilyPaperLock -and [bool]$familyAssessment.paper_lock
    $state.family_paper_defensive_observed = [bool]$familyAssessment.paper_defensive
    $state.family_paper_defensive_reason_observed = [string]$familyAssessment.paper_defensive_reason
    $state.family_paper_defensive_ignored = $ignoreFamilyPaperDefensive -and [bool]$familyAssessment.paper_defensive
    if ($ignoreFamilyPaperLock) {
        $state.family_paper_lock = $false
    }
    $state.family_trusted = [bool]$familyAssessment.trusted
    $state.family_max_daily_loss_pct = [double]$familyAssessment.max_family_daily_loss_pct
    $state.fleet_paper_lock_observed = [bool]$fleetAssessment.paper_lock
    $state.fleet_paper_lock_reason_observed = [string]$fleetAssessment.paper_lock_reason
    $state.fleet_paper_defensive_observed = [bool]$fleetAssessment.paper_defensive
    $state.fleet_paper_defensive_reason_observed = [string]$fleetAssessment.paper_defensive_reason
    $state.fleet_paper_lock_ignored = $ignoreFleetPaperLock -and [bool]$fleetAssessment.paper_lock
    $state.fleet_paper_defensive_ignored = $ignoreFleetPaperDefensive -and [bool]$fleetAssessment.paper_defensive
    $state.fleet_paper_lock = if ($ignoreFleetPaperLock) { $false } else { [bool]$fleetAssessment.paper_lock }
    $state.fleet_paper_lock_reason = if ($ignoreFleetPaperLock -and [bool]$fleetAssessment.paper_lock) { "IGNORED_FOR_BROKER_PARITY_FIRST_WAVE" } else { [string]$fleetAssessment.paper_lock_reason }
    $state.fleet_paper_defensive = if ($ignoreFleetPaperDefensive) { $false } else { [bool]$fleetAssessment.paper_defensive }
    $state.fleet_paper_defensive_reason = if ($ignoreFleetPaperDefensive -and [bool]$fleetAssessment.paper_defensive) { "IGNORED_FOR_BROKER_PARITY_FIRST_WAVE" } else { [string]$fleetAssessment.paper_defensive_reason }
    $state.fleet_daily_loss_pct = [double]$fleetAssessment.fleet_daily_loss_pct

    if ($state.fleet_paper_lock) {
        $state.paper_lock = $true
        $state.paper_lock_reason = [string]$state.fleet_paper_lock_reason
    }
    elseif ($state.family_paper_lock) {
        $state.paper_lock = $true
        $state.paper_lock_reason = [string]$state.family_paper_lock_reason
    }
    else {
        $state.paper_lock = $false
        $state.paper_lock_reason = "NONE"
    }

    if ($state.fleet_paper_defensive) {
        $state.paper_defensive = $true
        $state.paper_defensive_reason = [string]$state.fleet_paper_defensive_reason
    }
    elseif ($state.family_paper_defensive) {
        $state.paper_defensive = $true
        $state.paper_defensive_reason = [string]$state.family_paper_defensive_reason
    }
    else {
        $state.paper_defensive = $false
        $state.paper_defensive_reason = "NONE"
    }

    $state.reentry_ready = (
        [string]$state.window_state -eq "LIVE" -and
        $state.family_paper_lock -and
        -not $state.fleet_paper_lock -and
        $state.family_trusted -and
        [bool]$fleetAssessment.trusted_data -and
        [double]$state.family_max_daily_loss_pct -le $familyReentryThreshold -and
        [double]$state.fleet_daily_loss_pct -le $fleetReentryThreshold
    )

    $state.defensive_mode = (
        [string]$state.window_state -eq "LIVE" -and
        -not $state.paper_lock -and
        -not $state.paper_defensive -and
        (
            [double]$state.family_max_daily_loss_pct -ge $familyDefensiveThreshold -or
            [double]$state.fleet_daily_loss_pct -ge $fleetSoftThreshold
        )
    )
}

foreach ($domainName in @($coord.domains | Sort-Object wake_priority | ForEach-Object { [string]$_.domain })) {
    $state = $domainStates[$domainName]
    if ([string]$state.window_state -ne "LIVE" -or -not [bool]$state.paper_lock) {
        if (@($state.reserve_domains).Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$state.reserve_candidate)) {
            $state.reserve_candidate = [string]$state.reserve_domains[0]
        }
        continue
    }
    foreach ($reserveDomain in @($state.reserve_domains)) {
        if (-not $domainStates.ContainsKey($reserveDomain)) { continue }
        $state.reserve_candidate = [string]$reserveDomain
        $reserveState = $domainStates[$reserveDomain]
        if (
            [bool]$reserveState.active_runtime -and
            -not [bool]$reserveState.paper_lock -and
            [string]::IsNullOrWhiteSpace([string]$reserveState.reserve_requested_by) -and
            (
                [string]$reserveState.window_state -eq "LIVE" -or
                [string]$reserveState.window_state -eq "PREWARM" -or
                [string]$reserveState.window_state -eq "RESERVE_RESEARCH"
            )
        ) {
            $reserveState.reserve_requested_by = [string]$state.domain
            $state.reserve_activated = (
                [string]$reserveState.window_state -eq "LIVE" -or
                [string]$reserveState.window_state -eq "RESERVE_RESEARCH"
            )
            break
        }
    }
}

foreach ($domainName in @($domainStates.Keys)) {
    $state = $domainStates[$domainName]
    $requested = Resolve-RequestedMode `
        -State $state `
        -ActiveRuntime ([bool]$state.active_runtime) `
        -ManualOverride ([string]$state.manual_override) `
        -Rules $effectiveRules `
        -LiveDefensiveRiskCap $liveDefensiveRiskCap `
        -PaperDefensiveRiskCap $paperDefensiveRiskCap `
        -ReentryProbationRiskCap $reentryProbationRiskCap `
        -ReserveTakeoverRiskCap $reserveTakeoverRiskCap
    $state.requested_mode = [string]$requested.requested_mode
    $state.reason_code = [string]$requested.reason
    $state.requested_mode_source = [string]$requested.source
    $state.requested_risk_cap = [double]$requested.risk_cap
    $state.requested_force_flatten = [bool]$requested.force_flatten
    if (-not [string]::IsNullOrWhiteSpace([string]$requested.state_override)) {
        $state.state = [string]$requested.state_override
    }
}

$stateRoot = Join-Path $CommonFilesRoot "state"
$globalDir = Join-Path $stateRoot "_global"
$domainsDir = Join-Path $stateRoot "_domains"
Ensure-Dir $stateRoot
Ensure-Dir $globalDir
Ensure-Dir $domainsDir

$globalPath = Join-Path $globalDir "session_capital_coordinator.csv"
$globalLines = @(
    "ts_utc`t$((Get-Date).ToUniversalTime().ToString('o'))"
    "runtime_profile`t$RuntimeProfile"
    "capital_threshold_profile`t$capitalThresholdProfileName"
    "operator_time_pl`t$($nowPl.ToString('yyyy-MM-dd HH:mm'))"
    "operator_time_ny`t$($nowNy.ToString('yyyy-MM-dd HH:mm'))"
    "is_dst`t$([int]$isDst)"
    "active_group_count`t$($activeGroups.Count)"
    "active_trade_groups`t$((@($activeGroups | Where-Object { $_.mode -eq 'TRADE' } | ForEach-Object { $_.group }) -join ','))"
    "active_observation_groups`t$((@($activeGroups | Where-Object { $_.mode -ne 'TRADE' } | ForEach-Object { $_.group }) -join ','))"
    "fleet_paper_lock`t$([int][bool]$(if ($ignoreFleetPaperLock) { $false } else { [bool]$fleetAssessment.paper_lock }))"
    "fleet_paper_lock_reason`t$(if ($ignoreFleetPaperLock -and [bool]$fleetAssessment.paper_lock) { 'IGNORED_FOR_BROKER_PARITY_FIRST_WAVE' } else { $fleetAssessment.paper_lock_reason })"
    "fleet_paper_lock_observed`t$([int][bool]$fleetAssessment.paper_lock)"
    "fleet_paper_lock_reason_observed`t$($fleetAssessment.paper_lock_reason)"
    "fleet_paper_lock_ignored`t$([int][bool]($ignoreFleetPaperLock -and [bool]$fleetAssessment.paper_lock))"
    "fleet_paper_defensive`t$([int][bool]$(if ($ignoreFleetPaperDefensive) { $false } else { [bool]$fleetAssessment.paper_defensive }))"
    "fleet_paper_defensive_reason`t$(if ($ignoreFleetPaperDefensive -and [bool]$fleetAssessment.paper_defensive) { 'IGNORED_FOR_BROKER_PARITY_FIRST_WAVE' } else { $fleetAssessment.paper_defensive_reason })"
    "fleet_paper_defensive_observed`t$([int][bool]$fleetAssessment.paper_defensive)"
    "fleet_paper_defensive_reason_observed`t$($fleetAssessment.paper_defensive_reason)"
    "fleet_paper_defensive_ignored`t$([int][bool]($ignoreFleetPaperDefensive -and [bool]$fleetAssessment.paper_defensive))"
    "fleet_daily_loss_pct`t$([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0:F4}',$fleetAssessment.fleet_daily_loss_pct))"
    "rollover_daily_block`t$([int][bool]$dailyRolloverBlock)"
    "rollover_daily_force_flatten`t$([int][bool]$dailyRolloverForceFlatten)"
    "rollover_daily_reason`t$($dailyRolloverReason)"
)
$globalLines | Set-Content -LiteralPath $globalPath -Encoding UTF8

$domainReports = @()
foreach ($domainName in @($domainStates.Keys | Sort-Object)) {
    $state = $domainStates[$domainName]
    $domainDir = Join-Path $domainsDir $domainName
    Ensure-Dir $domainDir

    $runtimePath = Join-Path $domainDir "runtime_control.csv"

    $statePath = Join-Path $domainDir "session_capital_state.csv"
    @(
        "domain`t$($state.domain)"
        "capital_threshold_profile`t$capitalThresholdProfileName"
        "state`t$($state.state)"
        "active_group`t$($state.active_group)"
        "active_window_id`t$($state.active_window_id)"
        "window_state`t$($state.window_state)"
        "family_hint`t$($state.family_hint)"
        "budget_share_of_day`t$([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0:F4}',$state.budget_share_of_day))"
        "reserve_domains`t$((@($state.reserve_domains) -join ','))"
        "active_runtime`t$([int][bool]$state.active_runtime)"
        "manual_override`t$($state.manual_override)"
        "requested_mode`t$($state.requested_mode)"
        "requested_risk_cap`t$([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0:F4}',$state.requested_risk_cap))"
        "requested_force_flatten`t$([int][bool]$state.requested_force_flatten)"
        "reason_code`t$($state.reason_code)"
        "requested_mode_source`t$($state.requested_mode_source)"
        "paper_lock`t$([int][bool]$state.paper_lock)"
        "paper_lock_reason`t$($state.paper_lock_reason)"
        "paper_defensive`t$([int][bool]$state.paper_defensive)"
        "paper_defensive_reason`t$($state.paper_defensive_reason)"
        "family_paper_lock`t$([int][bool]$state.family_paper_lock)"
        "family_paper_lock_reason`t$($state.family_paper_lock_reason)"
        "family_paper_lock_observed`t$([int][bool]$state.family_paper_lock_observed)"
        "family_paper_lock_reason_observed`t$($state.family_paper_lock_reason_observed)"
        "family_paper_lock_ignored`t$([int][bool]$state.family_paper_lock_ignored)"
        "family_paper_defensive`t$([int][bool]$state.family_paper_defensive)"
        "family_paper_defensive_reason`t$($state.family_paper_defensive_reason)"
        "family_paper_defensive_observed`t$([int][bool]$state.family_paper_defensive_observed)"
        "family_paper_defensive_reason_observed`t$($state.family_paper_defensive_reason_observed)"
        "family_paper_defensive_ignored`t$([int][bool]$state.family_paper_defensive_ignored)"
        "family_trusted`t$([int][bool]$state.family_trusted)"
        "family_max_daily_loss_pct`t$([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0:F4}',$state.family_max_daily_loss_pct))"
        "fleet_paper_lock`t$([int][bool]$state.fleet_paper_lock)"
        "fleet_paper_lock_reason`t$($state.fleet_paper_lock_reason)"
        "fleet_paper_lock_observed`t$([int][bool]$state.fleet_paper_lock_observed)"
        "fleet_paper_lock_reason_observed`t$($state.fleet_paper_lock_reason_observed)"
        "fleet_paper_lock_ignored`t$([int][bool]$state.fleet_paper_lock_ignored)"
        "fleet_paper_defensive`t$([int][bool]$state.fleet_paper_defensive)"
        "fleet_paper_defensive_reason`t$($state.fleet_paper_defensive_reason)"
        "fleet_paper_defensive_observed`t$([int][bool]$state.fleet_paper_defensive_observed)"
        "fleet_paper_defensive_reason_observed`t$($state.fleet_paper_defensive_reason_observed)"
        "fleet_paper_defensive_ignored`t$([int][bool]$state.fleet_paper_defensive_ignored)"
        "fleet_daily_loss_pct`t$([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0:F4}',$state.fleet_daily_loss_pct))"
        "defensive_mode`t$([int][bool]$state.defensive_mode)"
        "reentry_ready`t$([int][bool]$state.reentry_ready)"
        "rollover_block`t$([int][bool]$state.rollover_block)"
        "rollover_force_flatten`t$([int][bool]$state.rollover_force_flatten)"
        "rollover_reason`t$($state.rollover_reason)"
        "reserve_candidate`t$($state.reserve_candidate)"
        "reserve_requested_by`t$($state.reserve_requested_by)"
        "reserve_activated`t$([int][bool]$state.reserve_activated)"
    ) | Set-Content -LiteralPath $statePath -Encoding UTF8

    $runtimeRiskCap = [math]::Max(0.0,[math]::Min(1.0,[double]$state.requested_risk_cap))
    $domainReports += [pscustomobject]@{
        domain = $state.domain
        capital_threshold_profile = $capitalThresholdProfileName
        state = $state.state
        window_state = $state.window_state
        requested_mode = $state.requested_mode
        requested_risk_cap = $runtimeRiskCap
        requested_force_flatten = [bool]$state.requested_force_flatten
        reason_code = $state.reason_code
        requested_mode_source = $state.requested_mode_source
        paper_lock = [bool]$state.paper_lock
        paper_lock_reason = $state.paper_lock_reason
        paper_defensive = [bool]$state.paper_defensive
        paper_defensive_reason = $state.paper_defensive_reason
        fleet_paper_lock = [bool]$state.fleet_paper_lock
        fleet_paper_lock_observed = [bool]$state.fleet_paper_lock_observed
        fleet_paper_lock_ignored = [bool]$state.fleet_paper_lock_ignored
        fleet_paper_defensive = [bool]$state.fleet_paper_defensive
        fleet_paper_defensive_observed = [bool]$state.fleet_paper_defensive_observed
        fleet_paper_defensive_ignored = [bool]$state.fleet_paper_defensive_ignored
        defensive_mode = [bool]$state.defensive_mode
        reentry_ready = [bool]$state.reentry_ready
        rollover_block = [bool]$state.rollover_block
        rollover_force_flatten = [bool]$state.rollover_force_flatten
        rollover_reason = [string]$state.rollover_reason
        reserve_candidate = $state.reserve_candidate
        reserve_requested_by = $state.reserve_requested_by
        reserve_activated = [bool]$state.reserve_activated
        active_group = $state.active_group
        active_window_id = $state.active_window_id
        runtime_control_path = $runtimePath
        state_path = $statePath
    }

    @(
        "requested_mode`t$($state.requested_mode)"
        "reason_code`t$($state.reason_code)"
        "risk_cap`t$([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0:F4}',$runtimeRiskCap))"
        "force_flatten`t$([int][bool]$state.requested_force_flatten)"
    ) | Set-Content -LiteralPath $runtimePath -Encoding UTF8
}

$symbolReports = @()
foreach ($entry in $symbolEntries) {
    $codeSymbol = [string]$entry.code_symbol
    if ([string]::IsNullOrWhiteSpace($codeSymbol)) { continue }

    $aliasDirs = @([string[]]$entry.state_dir_aliases | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($aliasDirs.Count -eq 0) {
        $aliasDirs = @($codeSymbol)
    }

    $runtimeTargets = @()
    foreach ($aliasDir in $aliasDirs) {
        $symbolDir = Join-Path $stateRoot $aliasDir
        Ensure-Dir $symbolDir
        $runtimeTargets += [pscustomobject]@{
            alias = $aliasDir
            runtime_path = (Join-Path $symbolDir "runtime_control.csv")
            backup_runtime_path = (Join-Path $symbolDir "runtime_control_pre_rollover.csv")
        }
    }

    $primaryTarget = @($runtimeTargets | Where-Object { Test-Path -LiteralPath $_.runtime_path } | Select-Object -First 1)
    if ($primaryTarget.Count -eq 0) {
        $primaryTarget = @($runtimeTargets | Select-Object -First 1)
    }

    $guard = $symbolRolloverStates[$codeSymbol]
    $existing = Read-KeyValueStateFile -Path $primaryTarget[0].runtime_path
    $existingReason = Get-MapString -Map $existing -Key "reason_code" -Default ""
    $existingRequestedMode = Get-MapString -Map $existing -Key "requested_mode" -Default ""
    $existingForceFlatten = Get-MapBool -Map $existing -Key "force_flatten"

    $rolloverLines = @(
        "requested_mode`tCLOSE_ONLY"
        "reason_code`t$($guard.reason_code)"
        "risk_cap`t1.0000"
        "force_flatten`t$([int][bool]$guard.force_flatten)"
    )

    if ($guard.block) {
        foreach ($target in $runtimeTargets) {
            $existingTarget = Read-KeyValueStateFile -Path $target.runtime_path
            $existingTargetReason = Get-MapString -Map $existingTarget -Key "reason_code" -Default ""
            if (
                $existingTarget.Count -gt 0 -and
                -not $existingTargetReason.StartsWith("ROLLOVER_") -and
                -not (Test-Path -LiteralPath $target.backup_runtime_path)
            ) {
                Copy-Item -LiteralPath $target.runtime_path -Destination $target.backup_runtime_path -Force
            }
            $rolloverLines | Set-Content -LiteralPath $target.runtime_path -Encoding UTF8
        }
    }
    else {
        foreach ($target in $runtimeTargets) {
            $existingTarget = Read-KeyValueStateFile -Path $target.runtime_path
            $existingTargetReason = Get-MapString -Map $existingTarget -Key "reason_code" -Default ""
            if (Test-Path -LiteralPath $target.backup_runtime_path) {
                Copy-Item -LiteralPath $target.backup_runtime_path -Destination $target.runtime_path -Force
                Remove-Item -LiteralPath $target.backup_runtime_path -Force -ErrorAction SilentlyContinue
            }
            elseif ($existingTarget.Count -gt 0 -and $existingTargetReason.StartsWith("ROLLOVER_")) {
                Remove-Item -LiteralPath $target.runtime_path -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $symbolReports += [pscustomobject]@{
        code_symbol = $codeSymbol
        registry_symbol = [string]$entry.registry_symbol
        state_dir_aliases = @($aliasDirs)
        domain = [string]$entry.domain
        session_profile = [string]$entry.session_profile
        rollover_block = [bool]$guard.block
        rollover_force_flatten = [bool]$guard.force_flatten
        reason_code = [string]$guard.reason_code
        source = [string]$guard.source
        matched_events = @($guard.matched_events)
        runtime_control_path = $primaryTarget[0].runtime_path
        runtime_control_paths = @($runtimeTargets | ForEach-Object { $_.runtime_path })
        backup_runtime_control_path = $primaryTarget[0].backup_runtime_path
        backup_runtime_control_paths = @($runtimeTargets | ForEach-Object { $_.backup_runtime_path })
        previous_requested_mode = $existingRequestedMode
        previous_reason_code = $existingReason
        previous_force_flatten = [bool]$existingForceFlatten
    }
}

$reportDir = Join-Path $projectPath "EVIDENCE"
Ensure-Dir $reportDir
$reportPath = Join-Path $reportDir ("APPLY_SESSION_CAPITAL_COORDINATOR_{0}.json" -f ((Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")))
$result = [ordered]@{
    schema_version = "1.5"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    common_files_root = $CommonFilesRoot
    global_state_path = $globalPath
    rollover_config_path = $rolloverPath
    operator_time_ny = $nowNy.ToString("yyyy-MM-dd HH:mm")
    capital_threshold_profile = $capitalThresholdProfileName
    daily_rollover_block = [bool]$dailyRolloverBlock
    daily_rollover_force_flatten = [bool]$dailyRolloverForceFlatten
    daily_rollover_reason = $dailyRolloverReason
    reentry_recover_fraction = $reentryRecoverFraction
    defensive_family_loss_fraction = $defensiveFamilyLossFraction
    family_reentry_threshold_pct = [math]::Round($familyReentryThreshold,4)
    family_defensive_threshold_pct = [math]::Round($familyDefensiveThreshold,4)
    fleet_reentry_threshold_pct = [math]::Round($fleetReentryThreshold,4)
    fleet_soft_threshold_pct = [math]::Round($fleetSoftThreshold,4)
    live_defensive_risk_cap = [math]::Round($liveDefensiveRiskCap,4)
    paper_defensive_risk_cap = [math]::Round($paperDefensiveRiskCap,4)
    reentry_probation_risk_cap = [math]::Round($reentryProbationRiskCap,4)
    reserve_takeover_risk_cap = [math]::Round($reserveTakeoverRiskCap,4)
    domains = @($domainReports)
    symbols = @($symbolReports)
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$result | ConvertTo-Json -Depth 6
