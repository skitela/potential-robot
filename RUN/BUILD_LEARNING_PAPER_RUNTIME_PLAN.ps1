param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LearningHealthPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\learning_health_registry_latest.json",
    [string]$OnnxFeedbackPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_feedback_loop_latest.json",
    [string]$PaperLiveFeedbackPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.json",
    [string]$OnnxSymbolRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string]$AuditSupervisorPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\audit_supervisor_latest.json",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Normalize-Symbol {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return $Value.Trim().ToUpperInvariant()
}

function New-MapByKeys {
    param(
        [object[]]$Items,
        [string[]]$Keys
    )

    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        foreach ($keyName in $Keys) {
            if (-not ($item.PSObject.Properties.Name -contains $keyName)) {
                continue
            }

            $key = Normalize-Symbol -Value ([string]$item.$keyName)
            if ([string]::IsNullOrWhiteSpace($key)) {
                continue
            }

            if (-not $map.ContainsKey($key)) {
                $map[$key] = $item
            }
        }
    }

    return $map
}

function Get-OptionalString {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Default = ""
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    return [string]$Object.$Name
}

function Get-OptionalNumber {
    param(
        [object]$Object,
        [string]$Name,
        [double]$Default = 0
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    $value = $Object.$Name
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $Default
    }

    return [double]$value
}

function Get-OptionalBool {
    param(
        [object]$Object,
        [string]$Name,
        [bool]$Default = $false
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    $value = $Object.$Name
    if ($null -eq $value) {
        return $Default
    }

    if ($value -is [bool]) {
        return [bool]$value
    }

    $text = ([string]$value).Trim().ToLowerInvariant()
    switch ($text) {
        "true" { return $true }
        "1" { return $true }
        "yes" { return $true }
        "tak" { return $true }
        "false" { return $false }
        "0" { return $false }
        "no" { return $false }
        "nie" { return $false }
        default { return $Default }
    }
}

function Get-DeployedRuntimeState {
    param([string]$SymbolAlias)

    $keyDir = Join-Path $CommonFilesRoot ("key\" + $SymbolAlias)
    $onnxPath = Join-Path $keyDir "paper_gate_acceptor_runtime_latest.onnx"
    $manifestPath = Join-Path $keyDir "paper_gate_acceptor_runtime_manifest_latest.json"
    $contractPath = Join-Path $keyDir "paper_gate_acceptor_runtime_contract_latest.csv"

    return [pscustomobject]@{
        key_dir = $keyDir
        runtime_model_exists = (Test-Path -LiteralPath $onnxPath)
        runtime_manifest_exists = (Test-Path -LiteralPath $manifestPath)
        runtime_contract_exists = (Test-Path -LiteralPath $contractPath)
        runtime_model_path = $onnxPath
        runtime_manifest_path = $manifestPath
        runtime_contract_path = $contractPath
    }
}

function Get-PaperLearningRole {
    param(
        [string]$OnnxStatus,
        [bool]$RuntimeInitialized,
        [double]$RuntimeRows
    )

    if ($OnnxStatus -eq "GLOBAL_FALLBACK") {
        return "PAPER_DLA_PROBKI"
    }

    if ($RuntimeInitialized -and $RuntimeRows -gt 0) {
        return "PAPER_ZWROT_ONNX_AKTYWNY"
    }

    if ($RuntimeInitialized) {
        return "PAPER_CIEN_ONNX_BRAK_WIERSZY"
    }

    return "PAPER_WYMAGA_WGRANIA_RUNTIME"
}

function Get-MigrationAction {
    param(
        [bool]$PaperFresh,
        [string]$OnnxStatus,
        [bool]$RuntimeInitialized,
        [double]$RuntimeRows,
        [bool]$DeployedRuntimeModelExists,
        [string]$LearningHealthState,
        [string]$WorkMode
    )

    if (-not $PaperFresh) {
        return "ODSWIEZ_PAPER_RUNTIME"
    }

    if ($OnnxStatus -eq "MODEL_PER_SYMBOL_READY" -and (-not $DeployedRuntimeModelExists -or -not $RuntimeInitialized)) {
        return "ODSWIEZ_PAPER_RUNTIME"
    }

    if ($PaperFresh -and $OnnxStatus -eq "MODEL_PER_SYMBOL_READY" -and $RuntimeInitialized -and $RuntimeRows -le 0) {
        return "NAPRAW_CIEN_ONNX_NA_PAPER"
    }

    if ($OnnxStatus -eq "GLOBAL_FALLBACK") {
        return "UTRZYMAJ_PAPER_I_BUDUJ_PROBKE"
    }

    if ($LearningHealthState -in @("WYMAGA_DOSZKOLENIA", "WYMAGA_REGENERACJI", "MALA_PROBKA")) {
        return "UTRZYMAJ_PAPER_I_ZBIERAJ_DO_REGENERACJI"
    }

    if ($WorkMode -in @("OBSERWUJ", "DOCISKAJ", "EKSPLOATUJ")) {
        return "UTRZYMAJ_PAPER_I_ZBIERAJ"
    }

    return "UTRZYMAJ_PAPER_I_ZBIERAJ"
}

function Get-Recommendation {
    param(
        [string]$MigrationAction,
        [string]$PaperLearningRole,
        [double]$RuntimeRows,
        [double]$OnnxRecentRows180m,
        [double]$PaperNet,
        [bool]$PaperFresh
    )

    $parts = New-Object System.Collections.Generic.List[string]

    switch ($MigrationAction) {
        "ODSWIEZ_PAPER_RUNTIME" { [void]$parts.Add("odswiezyc paper-live, bo to jest aktywne zrodlo nauki dla laptopa") }
        "NAPRAW_CIEN_ONNX_NA_PAPER" { [void]$parts.Add("naprawic cien obserwacji ONNX na paper-live, bo runtime jest gotowy, ale nie oddaje nawet lekkich wierszy NO_SETUP") }
        "UTRZYMAJ_PAPER_I_BUDUJ_PROBKE" { [void]$parts.Add("utrzymac paper-live i zbierac probe dla symbolu fallbackowego") }
        "UTRZYMAJ_PAPER_I_ZBIERAJ_DO_REGENERACJI" { [void]$parts.Add("utrzymac paper-live, ale traktowac dane jako material do regeneracji modelu") }
        "UTRZYMAJ_PAPER_I_ZBIERAJ" { [void]$parts.Add("utrzymac paper-live jako biezace zrodlo swiezych obserwacji") }
        default { [void]$parts.Add("nie wykonywac autonomicznej migracji bez ponownej oceny gate") }
    }

    switch ($PaperLearningRole) {
        "PAPER_ZWROT_ONNX_AKTYWNY" { [void]$parts.Add("maly ONNX juz oddaje runtime feedback") }
        "PAPER_CIEN_ONNX_BRAK_WIERSZY" { [void]$parts.Add("runtime jest gotowy, ale nie zapisuje nawet cienkiego shadow strumienia ONNX") }
        "PAPER_DLA_PROBKI" { [void]$parts.Add("paper jest potrzebny glownie do budowy lokalnej probki i telemetryki") }
        "PAPER_WYMAGA_WGRANIA_RUNTIME" { [void]$parts.Add("runtime ONNX nie jest jeszcze kompletny na paper-live") }
    }

    if ($RuntimeRows -gt 0) {
        [void]$parts.Add(("jest juz {0} runtime rows z paper" -f [int]$RuntimeRows))
    }
    if ($OnnxRecentRows180m -gt 0) {
        [void]$parts.Add(("w ostatnich 180m przyszlo {0} nowych wierszy ONNX" -f [int]$OnnxRecentRows180m))
    }
    elseif ($RuntimeRows -gt 0) {
        [void]$parts.Add("brak swiezego doplywu ONNX w ostatnich 180m")
    }
    if ([math]::Abs($PaperNet) -gt 0.000001) {
        [void]$parts.Add(("biezacy paper_net_pln={0}" -f [math]::Round($PaperNet, 2)))
    }
    if (-not $PaperFresh) {
        [void]$parts.Add("heartbeat paper-live nie jest swiezy")
    }

    return (($parts.ToArray()) -join "; ")
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$learningHealth = Read-JsonFile -Path $LearningHealthPath
if ($null -eq $learningHealth) {
    throw "Learning health registry missing or invalid: $LearningHealthPath"
}

$onnxFeedback = Read-JsonFile -Path $OnnxFeedbackPath
$paperLive = Read-JsonFile -Path $PaperLiveFeedbackPath
$onnxRegistry = Read-JsonFile -Path $OnnxSymbolRegistryPath
$audit = Read-JsonFile -Path $AuditSupervisorPath

$healthItems = @($learningHealth.items)
$healthMap = New-MapByKeys -Items $healthItems -Keys @("symbol_alias", "broker_symbol")

$runtimeBootstrap = @()
if ($null -ne $onnxFeedback -and ($onnxFeedback.PSObject.Properties.Name -contains "runtime_bootstrap")) {
    $runtimeBootstrap = @($onnxFeedback.runtime_bootstrap)
}
$runtimeMap = New-MapByKeys -Items $runtimeBootstrap -Keys @("symbol_alias")

$onnxFeedbackItems = @()
if ($null -ne $onnxFeedback -and ($onnxFeedback.PSObject.Properties.Name -contains "items")) {
    $onnxFeedbackItems = @($onnxFeedback.items)
}
$onnxFeedbackMap = New-MapByKeys -Items $onnxFeedbackItems -Keys @("symbol_alias")
$onnxFeedbackSummary = if ($null -ne $onnxFeedback -and ($onnxFeedback.PSObject.Properties.Name -contains "summary")) { $onnxFeedback.summary } else { $null }

$paperItems = @()
if ($null -ne $paperLive) {
    if ($paperLive.PSObject.Properties.Name -contains "key_instruments") {
        $paperItems = @($paperLive.key_instruments)
    }
    elseif ($paperLive.PSObject.Properties.Name -contains "items") {
        $paperItems = @($paperLive.items)
    }
}
$paperMap = New-MapByKeys -Items $paperItems -Keys @("instrument", "symbol_alias")

$onnxRegistryItems = @()
if ($null -ne $onnxRegistry -and ($onnxRegistry.PSObject.Properties.Name -contains "items")) {
    $onnxRegistryItems = @($onnxRegistry.items)
}
$onnxRegistryMap = New-MapByKeys -Items $onnxRegistryItems -Keys @("symbol")

$rolloutGate = ""
if ($null -ne $audit -and ($audit.PSObject.Properties.Name -contains "overall")) {
    $rolloutGate = Get-OptionalString -Object $audit.overall -Name "rollout_gate" -Default "UNKNOWN"
}
if ([string]::IsNullOrWhiteSpace($rolloutGate)) {
    $rolloutGate = "UNKNOWN"
}

$items = foreach ($health in ($healthItems | Sort-Object health_priority, priority_rank, symbol_alias)) {
    $symbolAlias = Normalize-Symbol -Value ([string]$health.symbol_alias)
    $paper = if ($paperMap.ContainsKey($symbolAlias)) { $paperMap[$symbolAlias] } else { $null }
    $runtime = if ($runtimeMap.ContainsKey($symbolAlias)) { $runtimeMap[$symbolAlias] } else { $null }
    $onnxItem = if ($onnxFeedbackMap.ContainsKey($symbolAlias)) { $onnxFeedbackMap[$symbolAlias] } else { $null }
    $registryEntry = if ($onnxRegistryMap.ContainsKey($symbolAlias)) { $onnxRegistryMap[$symbolAlias] } else { $null }
    $deployedRuntime = Get-DeployedRuntimeState -SymbolAlias $symbolAlias

    $paperFresh = Get-OptionalBool -Object $paper -Name "fresh" -Default $false
    $paperNet = Get-OptionalNumber -Object $paper -Name "net" -Default ([double](Get-OptionalNumber -Object $health -Name "paper_net_pln" -Default 0))
    $paperOpens = [int](Get-OptionalNumber -Object $paper -Name "opens" -Default 0)
    $paperCloses = [int](Get-OptionalNumber -Object $paper -Name "closes" -Default 0)
    $runtimeInitialized = Get-OptionalBool -Object $runtime -Name "runtime_initialized" -Default $false
    $runtimeRows = [int](Get-OptionalNumber -Object $runtime -Name "data_rows" -Default ([double](Get-OptionalNumber -Object $health -Name "sample_runtime_onnx_rows" -Default 0)))
    $onnxRecentRows60m = [int](Get-OptionalNumber -Object $onnxItem -Name "obserwacje_60m" -Default 0)
    $onnxRecentRows180m = [int](Get-OptionalNumber -Object $onnxItem -Name "obserwacje_180m" -Default 0)
    $onnxLatestObservationUtc = Get-OptionalString -Object $onnxItem -Name "latest_observation_utc" -Default ""
    $paperLearningRole = Get-PaperLearningRole -OnnxStatus ([string]$health.onnx_status) -RuntimeInitialized $runtimeInitialized -RuntimeRows $runtimeRows
    $migrationAction = Get-MigrationAction `
        -PaperFresh $paperFresh `
        -OnnxStatus ([string]$health.onnx_status) `
        -RuntimeInitialized $runtimeInitialized `
        -RuntimeRows $runtimeRows `
        -DeployedRuntimeModelExists $deployedRuntime.runtime_model_exists `
        -LearningHealthState ([string]$health.learning_health_state) `
        -WorkMode ([string]$health.work_mode)
    $runtimeFlowFresh = ($onnxRecentRows180m -gt 0)
    $runtimeFlowHistoricallyActive = ($runtimeRows -gt 0)
    $runtimeFlowStale = ($runtimeFlowHistoricallyActive -and -not $runtimeFlowFresh)
    $runtimeShadowGap = ($paperFresh -and $runtimeInitialized -and $runtimeRows -le 0 -and [string]$health.onnx_status -eq "MODEL_PER_SYMBOL_READY")
    $isCollecting = $false
    if ($paperFresh) {
        switch ($paperLearningRole) {
            "PAPER_DLA_PROBKI" { $isCollecting = $true }
            "PAPER_ZWROT_ONNX_AKTYWNY" { $isCollecting = $runtimeFlowFresh }
            "PAPER_CIEN_ONNX_BRAK_WIERSZY" { $isCollecting = $false }
            default { $isCollecting = $false }
        }
    }

    [pscustomobject]@{
        symbol_alias = $symbolAlias
        broker_symbol = [string]$health.broker_symbol
        session_profile = [string]$health.session_profile
        learning_health_state = [string]$health.learning_health_state
        work_mode = [string]$health.work_mode
        onnx_status = [string]$health.onnx_status
        onnx_quality = [string]$health.onnx_quality
        onnx_registry_status = Get-OptionalString -Object $registryEntry -Name "status" -Default ""
        paper_fresh = $paperFresh
        paper_net_pln = [math]::Round($paperNet, 2)
        paper_opens = $paperOpens
        paper_closes = $paperCloses
        paper_learning_role = $paperLearningRole
        runtime_initialized = $runtimeInitialized
        runtime_rows = $runtimeRows
        onnx_recent_rows_60m = $onnxRecentRows60m
        onnx_recent_rows_180m = $onnxRecentRows180m
        onnx_latest_observation_utc = $onnxLatestObservationUtc
        runtime_flow_fresh = $runtimeFlowFresh
        runtime_flow_stale = $runtimeFlowStale
        runtime_shadow_gap = $runtimeShadowGap
        is_collecting = $isCollecting
        runtime_model_exists = [bool]$deployedRuntime.runtime_model_exists
        runtime_manifest_exists = [bool]$deployedRuntime.runtime_manifest_exists
        runtime_contract_exists = [bool]$deployedRuntime.runtime_contract_exists
        migration_action = $migrationAction
        autonomous_rollout_allowed = ($rolloutGate -eq "OPEN")
        autonomous_refresh_blocked_by_gate = (($rolloutGate -ne "OPEN") -and ($migrationAction -eq "ODSWIEZ_PAPER_RUNTIME"))
        recommendation = Get-Recommendation `
            -MigrationAction $migrationAction `
            -PaperLearningRole $paperLearningRole `
            -RuntimeRows $runtimeRows `
            -OnnxRecentRows180m $onnxRecentRows180m `
            -PaperNet $paperNet `
            -PaperFresh $paperFresh
    }
}

$refreshItems = @($items | Where-Object { $_.migration_action -eq "ODSWIEZ_PAPER_RUNTIME" })
$collectItems = @($items | Where-Object { $_.is_collecting })
$fallbackProbeItems = @($items | Where-Object { $_.migration_action -eq "UTRZYMAJ_PAPER_I_BUDUJ_PROBKE" })
$activeRuntimeItems = @($items | Where-Object { $_.paper_learning_role -eq "PAPER_ZWROT_ONNX_AKTYWNY" })
$freshRuntimeItems = @($items | Where-Object { $_.runtime_flow_fresh })
$staleRuntimeItems = @($items | Where-Object { $_.runtime_flow_stale })
$shadowGapItems = @($items | Where-Object { $_.runtime_shadow_gap })
$observationReadyItems = @($items | Where-Object { $_.learning_health_state -in @("GOTOWY_DO_OBSERWACJI", "UCZY_SIE_ZDROWO", "GOTOWY_DO_MIEKKIEJ_BRAMKI") })

$overallAction = if ($refreshItems.Count -gt 0) {
    "ODSWIEZ_PAPER_RUNTIME"
}
elseif ($shadowGapItems.Count -gt 0) {
    "NAPRAW_CIEN_ONNX_NA_PAPER"
}
else {
    "UTRZYMAJ_PAPER_I_ZBIERAJ"
}

$summary = [ordered]@{
    rollout_gate = $rolloutGate
    overall_action = $overallAction
    symbols_total = @($items).Count
    symbols_to_refresh = $refreshItems.Count
    symbols_collecting = $collectItems.Count
    symbols_fallback_probe = $fallbackProbeItems.Count
    symbols_runtime_active = $activeRuntimeItems.Count
    symbols_runtime_fresh_180m = $freshRuntimeItems.Count
    symbols_runtime_stale = $staleRuntimeItems.Count
    symbols_shadow_observation_gap = $shadowGapItems.Count
    onnx_recent_rows_60m = [int](@($items | Measure-Object -Property onnx_recent_rows_60m -Sum).Sum)
    onnx_recent_rows_180m = [int](@($items | Measure-Object -Property onnx_recent_rows_180m -Sum).Sum)
    onnx_recent_symbols_60m = @($items | Where-Object { $_.onnx_recent_rows_60m -gt 0 }).Count
    onnx_recent_symbols_180m = @($items | Where-Object { $_.onnx_recent_rows_180m -gt 0 }).Count
    symbols_ready_for_observation = $observationReadyItems.Count
    paper_live_fresh_symbols = @($items | Where-Object { $_.paper_fresh }).Count
    autonomous_rollout_allowed = ($rolloutGate -eq "OPEN")
    onnx_feedback_recent_symbols_60m = [int](Get-OptionalNumber -Object $onnxFeedbackSummary -Name "liczba_symboli_aktywnych_60m" -Default 0)
    onnx_feedback_recent_symbols_180m = [int](Get-OptionalNumber -Object $onnxFeedbackSummary -Name "liczba_symboli_aktywnych_180m" -Default 0)
    onnx_feedback_recent_rows_60m = [int](Get-OptionalNumber -Object $onnxFeedbackSummary -Name "liczba_obserwacji_onnx_60m" -Default 0)
    onnx_feedback_recent_rows_180m = [int](Get-OptionalNumber -Object $onnxFeedbackSummary -Name "liczba_obserwacji_onnx_180m" -Default 0)
    onnx_feedback_latest_observation_utc = Get-OptionalString -Object $onnxFeedbackSummary -Name "najnowsza_obserwacja_utc" -Default ""
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    common_files_root = $CommonFilesRoot
    source_paths = [ordered]@{
        learning_health_registry = $LearningHealthPath
        onnx_feedback = $OnnxFeedbackPath
        paper_live_feedback = $PaperLiveFeedbackPath
        onnx_symbol_registry = $OnnxSymbolRegistryPath
        audit_supervisor = $AuditSupervisorPath
    }
    summary = $summary
    top_refresh = @($refreshItems | Select-Object -First 5)
    top_collect = @($collectItems | Select-Object -First 5)
    top_runtime_active = @($activeRuntimeItems | Sort-Object runtime_rows -Descending | Select-Object -First 5)
    top_shadow_gap = @($shadowGapItems | Select-Object -First 5)
    items = $items
}

$jsonPath = Join-Path $OutputRoot "learning_paper_runtime_plan_latest.json"
$mdPath = Join-Path $OutputRoot "learning_paper_runtime_plan_latest.md"

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Learning Paper Runtime Plan")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- rollout_gate: {0}" -f $summary.rollout_gate))
$lines.Add(("- overall_action: {0}" -f $summary.overall_action))
$lines.Add(("- symbols_to_refresh: {0}" -f $summary.symbols_to_refresh))
$lines.Add(("- symbols_collecting: {0}" -f $summary.symbols_collecting))
$lines.Add(("- symbols_runtime_active: {0}" -f $summary.symbols_runtime_active))
$lines.Add(("- symbols_runtime_fresh_180m: {0}" -f $summary.symbols_runtime_fresh_180m))
$lines.Add(("- symbols_runtime_stale: {0}" -f $summary.symbols_runtime_stale))
$lines.Add(("- symbols_shadow_observation_gap: {0}" -f $summary.symbols_shadow_observation_gap))
$lines.Add(("- onnx_recent_rows_60m: {0}" -f $summary.onnx_recent_rows_60m))
$lines.Add(("- onnx_recent_rows_180m: {0}" -f $summary.onnx_recent_rows_180m))
$lines.Add(("- onnx_recent_symbols_180m: {0}" -f $summary.onnx_recent_symbols_180m))
$lines.Add(("- paper_live_fresh_symbols: {0}" -f $summary.paper_live_fresh_symbols))
$lines.Add(("- symbols_ready_for_observation: {0}" -f $summary.symbols_ready_for_observation))
$lines.Add("")
$lines.Add("## Top Refresh")
$lines.Add("")
if ($refreshItems.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in ($refreshItems | Select-Object -First 8)) {
        $lines.Add(("- {0}: action={1}, role={2}, health={3}, fresh={4}" -f
            $item.symbol_alias,
            $item.migration_action,
            $item.paper_learning_role,
            $item.learning_health_state,
            $item.paper_fresh))
    }
}
$lines.Add("")
$lines.Add("## Shadow Gap")
$lines.Add("")
if ($shadowGapItems.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in ($shadowGapItems | Select-Object -First 8)) {
        $lines.Add(("- {0}: action={1}, role={2}, runtime_initialized={3}, runtime_rows={4}, fresh={5}" -f
            $item.symbol_alias,
            $item.migration_action,
            $item.paper_learning_role,
            $item.runtime_initialized,
            $item.runtime_rows,
            $item.paper_fresh))
    }
}
$lines.Add("")
$lines.Add("## Top Runtime Active")
$lines.Add("")
if ($activeRuntimeItems.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in ($activeRuntimeItems | Sort-Object runtime_rows -Descending | Select-Object -First 8)) {
        $lines.Add(("- {0}: runtime_rows={1}, paper_net={2}, health={3}, action={4}" -f
            $item.symbol_alias,
            $item.runtime_rows,
            $item.paper_net_pln,
            $item.learning_health_state,
            $item.migration_action))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
