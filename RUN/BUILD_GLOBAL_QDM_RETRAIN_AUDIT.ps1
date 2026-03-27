param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [int]$MetricsStaleMinutes = 180,
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "Light",
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
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

function Get-WrapperCount {
    param([string]$Pattern)

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like $Pattern
            }
    ).Count
}

function Get-FileAgeSeconds {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int]::MaxValue
    }

    return [int][Math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds)
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

$qdmVisibilityScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_VISIBILITY_REFRESH_PROFILE.ps1"
$starterScript = Join-Path $ProjectRoot "RUN\START_GLOBAL_QDM_RETRAIN_BACKGROUND.ps1"
$qdmVisibilityPath = Join-Path $opsRoot "qdm_visibility_refresh_profile_latest.json"
$qdmSyncStatusPath = Join-Path $opsRoot "qdm_missing_supported_sync_latest.json"
$jsonPath = Join-Path $opsRoot "global_qdm_retrain_audit_latest.json"
$mdPath = Join-Path $opsRoot "global_qdm_retrain_audit_latest.md"
$metricsPath = Join-Path $ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json"

foreach ($path in @($qdmVisibilityScript, $starterScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$qdmVisibility = (& $qdmVisibilityScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot | ConvertFrom-Json)
$qdmSyncStatus = Read-JsonSafe -Path $qdmSyncStatusPath
$metricsItem = if (Test-Path -LiteralPath $metricsPath) { Get-Item -LiteralPath $metricsPath } else { $null }
$metricsAgeSeconds = Get-FileAgeSeconds -Path $metricsPath
$metricsStaleSeconds = [Math]::Max(60, [int]$MetricsStaleMinutes * 60)

$refreshRequiredCount = if ($null -ne $qdmVisibility) { [int]$qdmVisibility.summary.refresh_required_count } else { 0 }
$serverTailBridgeRequiredCount = if ($null -ne $qdmVisibility -and $null -ne $qdmVisibility.summary.PSObject.Properties['server_tail_bridge_required_count']) { [int]$qdmVisibility.summary.server_tail_bridge_required_count } else { 0 }
$retrainRequiredCount = if ($null -ne $qdmVisibility) { [int]$qdmVisibility.summary.retrain_required_count } else { 0 }
$currentVisibleCount = if ($null -ne $qdmVisibility) { [int]$qdmVisibility.summary.current_contract_qdm_visible_symbols_count } else { 0 }
$trainedVisibleCount = if ($null -ne $qdmVisibility) { [int]$qdmVisibility.summary.trained_global_qdm_visible_symbols_count } else { 0 }
$metricsStale = ($metricsAgeSeconds -gt $metricsStaleSeconds)
$qdmSyncRunning = ((Get-WrapperCount -Pattern "*qdm_missing_supported_sync_wrapper_*") -gt 0) -or ((Get-WrapperCount -Pattern "*qdm_missing_supported_batch_wrapper_*") -gt 0) -or ([string]$qdmSyncStatus.state -in @("running", "export_in_progress"))
$mlPipelineRunning = (Get-WrapperCount -Pattern "*refresh_and_train_ml_wrapper_*") -gt 0
$retrainRunning = (Get-WrapperCount -Pattern "*global_qdm_retrain_wrapper_*") -gt 0

$verdict = "RETRAIN_NIEPOTRZEBNY"
$reason = "Brak swiezej luki miedzy aktualnym kontraktem QDM i metrykami modelu globalnego."
$recommendation = "Utrzymac tylko nadzor."
$startAllowed = $false
$retrainAction = ""

if ($retrainRequiredCount -gt 0) {
    if ($retrainRunning) {
        $verdict = "RETRAIN_W_TOKU"
        $reason = "Globalny retraining juz pracuje w tle."
        $recommendation = "Czekac na zakonczenie i potem odswiezyc raport widocznosci QDM."
    }
    elseif ($refreshRequiredCount -gt 0 -or $qdmSyncRunning) {
        $verdict = "RETRAIN_ZABLOKOWANY_QDM"
        $reason = "Najpierw trzeba domknac odswiezanie QDM dla symboli, ktore nadal nie dochodza do okna kandydatow."
        $recommendation = "Kontynuowac odswiezanie QDM; nie trenowac globalnego modelu na polowie naprawionego kontraktu."
    }
    elseif ($serverTailBridgeRequiredCount -gt 0) {
        $verdict = "RETRAIN_ZABLOKOWANY_OGONEM_SERWERA"
        $reason = "Zwykly refresh QDM jest juz domkniety, ale brakuje jeszcze biezacego ogona dnia z serwera lub brokera dla czesci symboli."
        $recommendation = "Najpierw zbudowac most biezacego ogona serwerowego; dopiero potem trenowac globalny model."
    }
    elseif ($mlPipelineRunning) {
        $verdict = "RETRAIN_ZABLOKOWANY_PRZEZ_ML"
        $reason = "Juz trwa glowny pipeline ML i nie nalezy dublowac ciezkiego treningu globalnego."
        $recommendation = "Poczekac az pipeline ML skonczy cykl, a potem ponowic audyt retrainu."
    }
    elseif ($metricsStale -or $trainedVisibleCount -lt $currentVisibleCount) {
        $verdict = "RETRAIN_GOTOWY"
        $reason = "Kontrakt widzi wiecej symboli z QDM niz ostatni trening globalny i metryki sa nieaktualne."
        $recommendation = "Uruchomic kontrolowane przetrenowanie modelu globalnego."
        $startAllowed = $true
    }
}

if ($Apply -and $startAllowed) {
    & $starterScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -PerfProfile $PerfProfile | Out-Null
    $retrainAction = "started_global_qdm_retrain_background"
    $retrainRunning = $true
    $startAllowed = $false
    $verdict = "RETRAIN_URUCHOMIONY"
    $reason = "Globalny retraining zostal uruchomiony w tle po domknieciu warunkow bezpieczenstwa."
    $recommendation = "Obserwowac log retrainu i po zakonczeniu sprawdzic nowe metryki."
}

$topRetrain = if ($null -ne $qdmVisibility) { @($qdmVisibility.retrain_required | Select-Object -First 5) } else { @() }
$allRetrainItems = if ($null -ne $qdmVisibility) { @($qdmVisibility.retrain_required) } else { @() }
$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    research_root = $ResearchRoot
    apply_mode = [bool]$Apply
    verdict = $verdict
    reason = $reason
    recommendation = $recommendation
    summary = [ordered]@{
        current_contract_qdm_visible_symbols_count = $currentVisibleCount
        trained_global_qdm_visible_symbols_count = $trainedVisibleCount
        refresh_required_count = $refreshRequiredCount
        server_tail_bridge_required_count = $serverTailBridgeRequiredCount
        retrain_required_count = $retrainRequiredCount
        metrics_last_write_local = if ($null -ne $metricsItem) { $metricsItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        metrics_age_seconds = if ($metricsAgeSeconds -eq [int]::MaxValue) { $null } else { $metricsAgeSeconds }
        metrics_stale_seconds = $metricsStaleSeconds
        metrics_stale = $metricsStale
        qdm_sync_running = $qdmSyncRunning
        ml_pipeline_running = $mlPipelineRunning
        retrain_running = $retrainRunning
        start_allowed = $startAllowed
        retrain_action = $retrainAction
    }
    top_retrain_required = [object[]]@($topRetrain)
    items = [object[]]@($allRetrainItems)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Global QDM Retrain Audit")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- reason: {0}" -f $report.reason))
$lines.Add(("- recommendation: {0}" -f $report.recommendation))
$lines.Add(("- current_visible: {0}" -f $report.summary.current_contract_qdm_visible_symbols_count))
$lines.Add(("- trained_visible: {0}" -f $report.summary.trained_global_qdm_visible_symbols_count))
$lines.Add(("- refresh_required_count: {0}" -f $report.summary.refresh_required_count))
$lines.Add(("- server_tail_bridge_required_count: {0}" -f $report.summary.server_tail_bridge_required_count))
$lines.Add(("- retrain_required_count: {0}" -f $report.summary.retrain_required_count))
$lines.Add(("- metrics_stale: {0}" -f ([string]$report.summary.metrics_stale).ToLowerInvariant()))
$lines.Add(("- qdm_sync_running: {0}" -f ([string]$report.summary.qdm_sync_running).ToLowerInvariant()))
$lines.Add(("- ml_pipeline_running: {0}" -f ([string]$report.summary.ml_pipeline_running).ToLowerInvariant()))
$lines.Add(("- retrain_running: {0}" -f ([string]$report.summary.retrain_running).ToLowerInvariant()))
$lines.Add(("- start_allowed: {0}" -f ([string]$report.summary.start_allowed).ToLowerInvariant()))
$lines.Add(("- retrain_action: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.retrain_action)) { "none" } else { $report.summary.retrain_action })))
$lines.Add("")
$lines.Add("## Top Retrain Required")
$lines.Add("")
if (@($topRetrain).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $topRetrain) {
        $lines.Add(("- {0}: cause={1}, why={2}" -f $item.symbol_alias, $item.main_root_cause, $item.dlatego_ze))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
