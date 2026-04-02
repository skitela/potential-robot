param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonObject {
    param(
        [string]$Path
    )

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

function Get-SafePropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    throw "Registry not found: $RegistryPath"
}

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($registry.items)
$reportItems = New-Object System.Collections.Generic.List[object]

foreach ($item in $items) {
    $symbol = [string]$item.symbol
    $status = [string]$item.status
    $symbolToken = ($symbol -replace '[^A-Za-z0-9]+', '_')
    $botPath = Join-Path $ProjectRoot ("MQL5\Experts\MicroBots\MicroBot_{0}.mq5" -f $symbol)
    $botCode = if (Test-Path -LiteralPath $botPath) { Get-Content -LiteralPath $botPath -Raw -Encoding UTF8 } else { "" }

    $codeHasInclude = ($botCode -match 'MbOnnxPilotObservation\.mqh')
    $codeHasToggle = ($botCode -match 'InpEnableOnnxObservation')
    $codeHasObservationInit = ($botCode -match 'MbOnnxObservationInit\(')
    $codeHasObservationRuntime = ($botCode -match 'MbOnnxObservationEmitTimerShadow\(') -or ($botCode -match 'MbOnnxObservationEvaluate\(')
    $codeHasBridge = ($botCode -match 'MbMlRuntimeBridgeApplyStudentGate\(') -or ($botCode -match 'MbMlRuntimeBridgeInit\(')
    $codeHasChannel = ($botCode -match '\? "PAPER" : "LIVE"')
    $codeWired = ($codeHasInclude -and $codeHasToggle -and $codeHasObservationInit -and $codeHasObservationRuntime -and $codeHasBridge)

    $keyDir = Join-Path $CommonRoot ("key\{0}" -f $symbol)
    $runtimeOnnxPath = Join-Path $keyDir "paper_gate_acceptor_runtime_latest.onnx"
    $runtimeManifestPath = Join-Path $keyDir "paper_gate_acceptor_runtime_manifest_latest.json"
    $runtimeMetricsPath = Join-Path $keyDir "paper_gate_acceptor_runtime_metrics_latest.json"
    $runtimeContractPath = Join-Path $keyDir "paper_gate_acceptor_runtime_contract_latest.csv"
    $runtimeArtifactsReady = (Test-Path -LiteralPath $runtimeOnnxPath) -and
                             (Test-Path -LiteralPath $runtimeManifestPath) -and
                             (Test-Path -LiteralPath $runtimeMetricsPath) -and
                             (Test-Path -LiteralPath $runtimeContractPath)

    $pilotReportPath = Join-Path $EvidenceDir ("runtime_onnx_pilot_{0}_latest.json" -f $symbolToken)
    $pilotReport = Read-JsonObject -Path $pilotReportPath
    $featureCount = [int](Get-SafePropertyValue -Object $pilotReport -Name 'feature_count' -Default 0)
    $runtimeRocAuc = [double](Get-SafePropertyValue -Object $pilotReport -Name 'runtime_roc_auc' -Default 0.0)
    $runtimeBalancedAccuracy = [double](Get-SafePropertyValue -Object $pilotReport -Name 'runtime_balanced_accuracy' -Default 0.0)

    $overallStatus = "NIEZNANY"
    if ($status -eq "MODEL_PER_SYMBOL_READY") {
        if ($codeWired -and $runtimeArtifactsReady) {
            $overallStatus = "POLACZONY_GOTOWY"
        }
        elseif ($codeWired) {
            $overallStatus = "KOD_GOTOWY_BRAK_ARTEFAKTOW"
        }
        elseif ($runtimeArtifactsReady) {
            $overallStatus = "ARTEFAKTY_GOTOWE_BRAK_KABLA"
        }
        else {
            $overallStatus = "MODEL_GOTOWY_BRAK_POLACZENIA"
        }
    }
    elseif ($status -eq "GLOBAL_FALLBACK") {
        $overallStatus = "FALLBACK_GLOBALNY"
    }
    else {
        $overallStatus = "POZA_ZAKRESEM"
    }

    $reportItems.Add([pscustomobject]@{
            symbol = $symbol
            status_modelu = $status
            status_polaczenia = $overallStatus
            kod_polaczony = $codeWired
            kod_ma_kanal_paper_live = $codeHasChannel
            artefakty_runtime_gotowe = $runtimeArtifactsReady
            cechy_runtime = $featureCount
            pole_pod_krzywa_roc = [math]::Round($runtimeRocAuc, 6)
            trafnosc_zbalansowana = [math]::Round($runtimeBalancedAccuracy, 6)
            teacher_enabled = [bool](Get-SafePropertyValue -Object $item -Name 'teacher_enabled' -Default $false)
            rows_total = [int](Get-SafePropertyValue -Object $item -Name 'rows_total' -Default 0)
            reason = [string](Get-SafePropertyValue -Object $item -Name 'reason' -Default '')
            bot_path = $botPath
            key_dir = $keyDir
        })
}

$reportItems = @($reportItems | Sort-Object symbol)
$summary = [ordered]@{
    total_symbols = @($reportItems).Count
    model_per_symbol_ready = @($reportItems | Where-Object { $_.status_modelu -eq 'MODEL_PER_SYMBOL_READY' }).Count
    fallback_globalny = @($reportItems | Where-Object { $_.status_modelu -eq 'GLOBAL_FALLBACK' }).Count
    polaczony_gotowy = @($reportItems | Where-Object { $_.status_polaczenia -eq 'POLACZONY_GOTOWY' }).Count
    kod_ma_kanal_paper_live = @($reportItems | Where-Object { $_.kod_ma_kanal_paper_live }).Count
    artefakty_runtime_gotowe = @($reportItems | Where-Object { $_.artefakty_runtime_gotowe }).Count
}

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    summary = $summary
    items = $reportItems
}

$jsonPath = Join-Path $EvidenceDir "onnx_cable_status_latest.json"
$mdPath = Join-Path $EvidenceDir "onnx_cable_status_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Status Kabli ONNX")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- wszystkie_symbole: {0}" -f $summary.total_symbols))
$lines.Add(("- modele_per_symbol: {0}" -f $summary.model_per_symbol_ready))
$lines.Add(("- fallback_globalny: {0}" -f $summary.fallback_globalny))
$lines.Add(("- polaczone_gotowe: {0}" -f $summary.polaczony_gotowy))
$lines.Add(("- kabel_z_kanalem_paper_live: {0}" -f $summary.kod_ma_kanal_paper_live))
$lines.Add(("- artefakty_runtime_gotowe: {0}" -f $summary.artefakty_runtime_gotowe))
$lines.Add("")
$lines.Add("## Symbole")
$lines.Add("")

foreach ($item in $reportItems) {
    $lines.Add(("### {0}" -f $item.symbol))
    $lines.Add(("- status_modelu: {0}" -f $item.status_modelu))
    $lines.Add(("- status_polaczenia: {0}" -f $item.status_polaczenia))
    $lines.Add(("- kod_polaczony: {0}" -f $item.kod_polaczony))
    $lines.Add(("- kanal_paper_live: {0}" -f $item.kod_ma_kanal_paper_live))
    $lines.Add(("- artefakty_runtime_gotowe: {0}" -f $item.artefakty_runtime_gotowe))
    $lines.Add(("- cechy_runtime: {0}" -f $item.cechy_runtime))
    $lines.Add(("- pole_pod_krzywa_roc: {0}" -f $item.pole_pod_krzywa_roc))
    $lines.Add(("- trafnosc_zbalansowana: {0}" -f $item.trafnosc_zbalansowana))
    if ($item.reason) {
        $lines.Add(("- uwaga: {0}" -f $item.reason))
    }
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report
