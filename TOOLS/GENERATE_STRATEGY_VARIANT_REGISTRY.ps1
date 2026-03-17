param(
    [string]$Root = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Get-RegexValue {
    param(
        [string]$Content,
        [string]$Pattern
    )
    $m = [regex]::Match($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) {
        return $null
    }
    return $m.Groups[1].Value
}

function Get-RegexValues {
    param(
        [string]$Content,
        [string]$Pattern
    )
    $matches = [regex]::Matches($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $values = @()
    foreach ($m in $matches) {
        if ($m.Success) {
            $values += $m.Groups[1].Value
        }
    }
    return @($values | Sort-Object -Unique)
}

function Convert-ToNumberOrNull {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    $n = 0.0
    if ([double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, $InvariantCulture, [ref]$n)) {
        return $n
    }
    return $null
}

function First-NonEmpty {
    param([string[]]$Values)
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
    return $null
}

function Add-ValueToSet {
    param(
        [hashtable]$Map,
        [string]$Key,
        $Value
    )
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = New-Object System.Collections.Generic.HashSet[string]
    }
    $null = $Map[$Key].Add(([string]$Value))
}

$projectRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$profilesDir = Join-Path $projectRoot "MQL5\Include\Profiles"
$strategiesDir = Join-Path $projectRoot "MQL5\Include\Strategies"
$configDir = Join-Path $projectRoot "CONFIG"
$evidenceDir = Join-Path $projectRoot "EVIDENCE"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$profileFiles = Get-ChildItem -LiteralPath $profilesDir -Filter "Profile_*.mqh" -File | Sort-Object Name
$strategyFiles = Get-ChildItem -LiteralPath $strategiesDir -Filter "Strategy_*.mqh" -File | Sort-Object Name

$profileMap = @{}
foreach ($file in $profileFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $alias = $file.BaseName -replace '^Profile_', ''
    $symbol = Get-RegexValue -Content $content -Pattern 'out\.symbol\s*=\s*"([^"]+)"'
    if ([string]::IsNullOrWhiteSpace($symbol)) {
        continue
    }
    $profile = [ordered]@{
        alias_symbol = $alias
        symbol = $symbol
        trade_tf = Get-RegexValue -Content $content -Pattern 'out\.trade_tf\s*=\s*([A-Z0-9_]+)'
        session_profile = Get-RegexValue -Content $content -Pattern 'out\.session_profile\s*=\s*"([^"]+)"'
        trade_window_start_hour = Convert-ToNumberOrNull (Get-RegexValue -Content $content -Pattern 'out\.trade_window_start_hour\s*=\s*([0-9.]+)')
        trade_window_end_hour = Convert-ToNumberOrNull (Get-RegexValue -Content $content -Pattern 'out\.trade_window_end_hour\s*=\s*([0-9.]+)')
        max_spread_points = Convert-ToNumberOrNull (Get-RegexValue -Content $content -Pattern 'out\.max_spread_points\s*=\s*([0-9.]+)')
        caution_spread_points = Convert-ToNumberOrNull (Get-RegexValue -Content $content -Pattern 'out\.caution_spread_points\s*=\s*([0-9.]+)')
        hard_daily_loss_pct = Convert-ToNumberOrNull (Get-RegexValue -Content $content -Pattern 'out\.hard_daily_loss_pct\s*=\s*([0-9.]+)')
        hard_session_loss_pct = Convert-ToNumberOrNull (Get-RegexValue -Content $content -Pattern 'out\.hard_session_loss_pct\s*=\s*([0-9.]+)')
        min_seconds_between_entries = Convert-ToNumberOrNull (Get-RegexValue -Content $content -Pattern 'out\.min_seconds_between_entries\s*=\s*([0-9.]+)')
        kill_switch_token_name = Get-RegexValue -Content $content -Pattern 'out\.kill_switch_token_name\s*=\s*"([^"]+)"'
        profile_file = $file.FullName
    }
    $profileMap[$alias] = $profile
    $profileMap[$symbol] = $profile
}

$strategyVariants = @()
$commonTracker = @{}

foreach ($file in $strategyFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $aliasSymbol = $file.BaseName -replace '^Strategy_', ''
    $profile = $null
    if ($profileMap.ContainsKey($aliasSymbol)) {
        $profile = $profileMap[$aliasSymbol]
    }
    $symbol = if ($null -ne $profile) { [string]$profile.symbol } else { $aliasSymbol }

    $variant = [ordered]@{
        symbol = $symbol
        alias_symbol = $aliasSymbol
        strategy_file = $file.FullName
        profile = $profile
        indicators = [ordered]@{
            ema_fast = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.ema_fast_period\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'iMA\(profile\.symbol,profile\.trade_tf,([0-9]+),0,MODE_EMA,PRICE_CLOSE\)')
            ))
            ema_slow = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.ema_slow_period\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'iMA\(profile\.symbol,profile\.trade_tf,[0-9]+,0,MODE_EMA,PRICE_CLOSE\).*?iMA\(profile\.symbol,profile\.trade_tf,([0-9]+),0,MODE_EMA,PRICE_CLOSE\)')
            ))
            atr_period = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.atr_period\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'iATR\(profile\.symbol,profile\.trade_tf,([0-9]+)\)')
            ))
            rsi_period = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.rsi_period\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'iRSI\(profile\.symbol,profile\.trade_tf,([0-9]+),PRICE_CLOSE\)')
            ))
        }
        risk = [ordered]@{
            base_risk_pct = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.base_risk_pct\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'double risk_pct = [A-Za-z0-9_]+\(([0-9.]+)\s*\*\s*MathMax')
            ))
            execution_floor = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.execution_floor\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'MathMax\(([0-9.]+),1\.0 - \(state\.execution_pressure')
            ))
            execution_decay = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.execution_decay\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'state\.execution_pressure \* ([0-9.]+)\)\)')
            ))
            min_risk_pct = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.min_risk_pct\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern '\),([0-9.]+),([0-9.]+)\);')
            ))
            max_risk_pct = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.max_risk_pct\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern '\),[0-9.]+,([0-9.]+)\);')
            ))
            sl_atr_multiplier = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.sl_atr_multiplier\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'out\.sl_points = MathMax\(g_[a-z0-9_]+_last_atr_points \* ([0-9.]+),')
            ))
            sl_min_points = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.sl_min_points\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'out\.sl_points = MathMax\(g_[a-z0-9_]+_last_atr_points \* [0-9.]+,([0-9.]+)\)')
            ))
            tp_atr_multiplier = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.tp_atr_multiplier\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'out\.tp_points = MathMax\(g_[a-z0-9_]+_last_atr_points \* ([0-9.]+),')
            ))
            tp_min_points = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.tp_min_points\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'out\.tp_points = MathMax\(g_[a-z0-9_]+_last_atr_points \* [0-9.]+,([0-9.]+)\)')
            ))
            trail_atr_multiplier = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.trail_atr_multiplier\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'double trail = g_[a-z0-9_]+_last_atr_points \* ([0-9.]+) \* _Point')
            ))
        }
        decision = [ordered]@{
            caution_trigger_abs = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.caution_trigger_abs\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'double trigger_abs = \(state\.caution_mode \? ([0-9.]+) :')
            ))
            ready_trigger_abs = Convert-ToNumberOrNull (First-NonEmpty @(
                (Get-RegexValue -Content $content -Pattern 'out\.ready_trigger_abs\s*=\s*([0-9.]+)'),
                (Get-RegexValue -Content $content -Pattern 'double trigger_abs = \(state\.caution_mode \? [0-9.]+ : ([0-9.]+)\)')
            ))
            setup_labels = @(Get-RegexValues -Content $content -Pattern '"(SETUP_[A-Z_]+)"')
        }
        model = [ordered]@{
            has_rejection = ($content -match 'score_rejection')
            has_range = ($content -match 'score_range')
            has_reversal = ($content -match 'score_reversal')
            uses_new_bar_gate = ($content -match 'WAIT_NEW_BAR' -or $content -match 'MbStrategyResolveNewBar')
            has_live_manage_position = ($content -match 'PositionModify' -or $content -match 'MbFamilyStrategyManagePosition' -or $content -match 'MbStrategyManagePosition')
        }
    }

    Add-ValueToSet -Map $commonTracker -Key "trade_tf" -Value $variant.profile.trade_tf
    Add-ValueToSet -Map $commonTracker -Key "session_profile" -Value $variant.profile.session_profile
    Add-ValueToSet -Map $commonTracker -Key "trade_window_start_hour" -Value $variant.profile.trade_window_start_hour
    Add-ValueToSet -Map $commonTracker -Key "trade_window_end_hour" -Value $variant.profile.trade_window_end_hour
    Add-ValueToSet -Map $commonTracker -Key "max_spread_points" -Value $variant.profile.max_spread_points
    Add-ValueToSet -Map $commonTracker -Key "caution_spread_points" -Value $variant.profile.caution_spread_points
    Add-ValueToSet -Map $commonTracker -Key "atr_period" -Value $variant.indicators.atr_period
    Add-ValueToSet -Map $commonTracker -Key "rsi_period" -Value $variant.indicators.rsi_period
    Add-ValueToSet -Map $commonTracker -Key "ema_fast" -Value $variant.indicators.ema_fast
    Add-ValueToSet -Map $commonTracker -Key "ema_slow" -Value $variant.indicators.ema_slow
    Add-ValueToSet -Map $commonTracker -Key "base_risk_pct" -Value $variant.risk.base_risk_pct
    Add-ValueToSet -Map $commonTracker -Key "execution_floor" -Value $variant.risk.execution_floor
    Add-ValueToSet -Map $commonTracker -Key "execution_decay" -Value $variant.risk.execution_decay
    Add-ValueToSet -Map $commonTracker -Key "min_risk_pct" -Value $variant.risk.min_risk_pct
    Add-ValueToSet -Map $commonTracker -Key "max_risk_pct" -Value $variant.risk.max_risk_pct
    Add-ValueToSet -Map $commonTracker -Key "sl_atr_multiplier" -Value $variant.risk.sl_atr_multiplier
    Add-ValueToSet -Map $commonTracker -Key "sl_min_points" -Value $variant.risk.sl_min_points
    Add-ValueToSet -Map $commonTracker -Key "tp_atr_multiplier" -Value $variant.risk.tp_atr_multiplier
    Add-ValueToSet -Map $commonTracker -Key "tp_min_points" -Value $variant.risk.tp_min_points
    Add-ValueToSet -Map $commonTracker -Key "trail_atr_multiplier" -Value $variant.risk.trail_atr_multiplier
    Add-ValueToSet -Map $commonTracker -Key "caution_trigger_abs" -Value $variant.decision.caution_trigger_abs
    Add-ValueToSet -Map $commonTracker -Key "ready_trigger_abs" -Value $variant.decision.ready_trigger_abs
    Add-ValueToSet -Map $commonTracker -Key "setup_signature" -Value (($variant.decision.setup_labels -join "|"))
    Add-ValueToSet -Map $commonTracker -Key "uses_new_bar_gate" -Value $variant.model.uses_new_bar_gate
    Add-ValueToSet -Map $commonTracker -Key "has_live_manage_position" -Value $variant.model.has_live_manage_position
    Add-ValueToSet -Map $commonTracker -Key "has_rejection" -Value $variant.model.has_rejection
    Add-ValueToSet -Map $commonTracker -Key "has_range" -Value $variant.model.has_range
    Add-ValueToSet -Map $commonTracker -Key "has_reversal" -Value $variant.model.has_reversal

    $strategyVariants += $variant
}

$common = [ordered]@{}
$overrideFields = New-Object System.Collections.Generic.List[string]
foreach ($key in $commonTracker.Keys | Sort-Object) {
    $values = @($commonTracker[$key])
    if ($values.Count -eq 1) {
        $common[$key] = $values[0]
    } else {
        $overrideFields.Add($key)
    }
}

$report = [ordered]@{
    schema = "makro_i_mikro_bot.strategy.variant.audit.v1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $projectRoot
    common_contract = [ordered]@{
        common_fields = $common
        override_fields = @($overrideFields)
        design_intent = @(
            "Common strategy flow should stay in shared include files.",
            "Per-symbol overrides should stay in registry/profile/variant params.",
            "Propagation should update common flow without overwriting symbol-specific parameters."
        )
    }
    variants = $strategyVariants
}

$configPath = Join-Path $configDir "strategy_variant_registry.json"
$evidencePath = Join-Path $evidenceDir "strategy_variant_audit.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

Write-Output ("GENERATE_STRATEGY_VARIANT_REGISTRY_DONE config={0}" -f $configPath)
Write-Output ("AUDIT={0}" -f $evidencePath)
Write-Output ("VARIANTS={0}" -f $strategyVariants.Count)
exit 0
