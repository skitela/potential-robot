param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$TrainingReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_training_readiness_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
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

function Get-SafeObjectValue {
    param(
        [object]$Object,
        [string]$PropertyName,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Join-StringArray {
    param([object[]]$Values)

    return (@($Values | ForEach-Object { [string]$_ }) -join '|')
}

function Convert-RuntimeManifestToContractLines {
    param([object]$Manifest)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("type,key,value")
    $lines.Add(("meta,schema_version,{0}" -f ([string](Get-SafeObjectValue -Object $Manifest -PropertyName 'schema_version' -Default '1.0'))))
    $lines.Add(("meta,symbol,{0}" -f ([string](Get-SafeObjectValue -Object $Manifest -PropertyName 'symbol' -Default 'UNKNOWN'))))
    $lines.Add(("meta,feature_count,{0}" -f (@(Get-SafeObjectValue -Object $Manifest -PropertyName 'feature_names' -Default @()).Count)))
    $lines.Add(("meta,teacher_feature_enabled,{0}" -f $(if ([bool](Get-SafeObjectValue -Object $Manifest -PropertyName 'teacher_feature_enabled' -Default $false)) { "1" } else { "0" })))
    $lines.Add(("list,feature_names,{0}" -f (Join-StringArray -Values @(Get-SafeObjectValue -Object $Manifest -PropertyName 'feature_names' -Default @()))))
    $lines.Add(("list,categorical_features,{0}" -f (Join-StringArray -Values @(Get-SafeObjectValue -Object $Manifest -PropertyName 'categorical_features' -Default @()))))
    $lines.Add(("list,numeric_float_features,{0}" -f (Join-StringArray -Values @(Get-SafeObjectValue -Object $Manifest -PropertyName 'numeric_float_features' -Default @()))))
    $lines.Add(("list,numeric_int_features,{0}" -f (Join-StringArray -Values @(Get-SafeObjectValue -Object $Manifest -PropertyName 'numeric_int_features' -Default @()))))

    $categoryMaps = Get-SafeObjectValue -Object $Manifest -PropertyName 'category_maps' -Default $null
    if ($null -ne $categoryMaps) {
        foreach ($property in $categoryMaps.PSObject.Properties) {
            $pairs = New-Object System.Collections.Generic.List[string]
            foreach ($categoryProperty in $property.Value.PSObject.Properties) {
                $pairs.Add(("{0}={1}" -f [string]$categoryProperty.Name, [string]$categoryProperty.Value))
            }
            $lines.Add(("map,{0},{1}" -f [string]$property.Name, ($pairs -join '|')))
        }
    }

    return $lines
}

function Write-RuntimeContractCsv {
    param(
        [object]$Manifest,
        [string]$TargetPath
    )

    $lines = Convert-RuntimeManifestToContractLines -Manifest $Manifest
    ($lines -join "`r`n") | Set-Content -LiteralPath $TargetPath -Encoding ASCII
}

function Test-ShadowBootstrapCandidate {
    param([object]$Item)

    $readiness = [string](Get-SafeObjectValue -Object $Item -PropertyName 'training_readiness_state' -Default '')
    $eligibility = [string](Get-SafeObjectValue -Object $Item -PropertyName 'local_training_eligibility' -Default '')
    return ($readiness -eq "TRAINING_SHADOW_READY" -or $eligibility -eq "SHADOW_ONLY")
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$globalKeyDir = Join-Path (Join-Path $CommonRoot "key") "_GLOBAL"
$globalOnnxPath = Join-Path $globalKeyDir "paper_gate_acceptor_runtime_latest.onnx"
$globalManifestPath = Join-Path $globalKeyDir "paper_gate_acceptor_runtime_manifest_latest.json"
$globalMetricsPath = Join-Path $globalKeyDir "paper_gate_acceptor_runtime_metrics_latest.json"
$globalContractPath = Join-Path $globalKeyDir "paper_gate_acceptor_runtime_contract_latest.csv"

$globalReady = @($globalOnnxPath, $globalManifestPath, $globalMetricsPath, $globalContractPath) | ForEach-Object { Test-Path -LiteralPath $_ } | Where-Object { $_ -eq $false } | Measure-Object | Select-Object -ExpandProperty Count
$trainingReadiness = Read-JsonSafe -Path $TrainingReadinessPath
$items = if ($null -ne $trainingReadiness) { @($trainingReadiness.items) } else { @() }

$candidates = New-Object System.Collections.Generic.List[object]
foreach ($item in $items) {
    if (-not (Test-ShadowBootstrapCandidate -Item $item)) {
        continue
    }

    $symbol = [string](Get-SafeObjectValue -Object $item -PropertyName 'symbol_alias' -Default '')
    if ([string]::IsNullOrWhiteSpace($symbol)) {
        continue
    }

    $symbolKeyDir = Join-Path (Join-Path $CommonRoot "key") $symbol.Trim().ToUpperInvariant()
    $targetPaths = [ordered]@{
        onnx = Join-Path $symbolKeyDir "paper_gate_acceptor_runtime_latest.onnx"
        manifest = Join-Path $symbolKeyDir "paper_gate_acceptor_runtime_manifest_latest.json"
        metrics = Join-Path $symbolKeyDir "paper_gate_acceptor_runtime_metrics_latest.json"
        contract = Join-Path $symbolKeyDir "paper_gate_acceptor_runtime_contract_latest.csv"
    }
    $missing = @($targetPaths.GetEnumerator() | Where-Object { -not (Test-Path -LiteralPath $_.Value) } | ForEach-Object { [string]$_.Key })
    if (@($missing).Count -eq 0) {
        continue
    }

    $candidates.Add([pscustomobject]@{
        symbol_alias = $symbol.Trim().ToUpperInvariant()
        training_readiness_state = [string](Get-SafeObjectValue -Object $item -PropertyName 'training_readiness_state' -Default '')
        local_training_eligibility = [string](Get-SafeObjectValue -Object $item -PropertyName 'local_training_eligibility' -Default '')
        missing_artifacts = @($missing)
        target_key_dir = $symbolKeyDir
    }) | Out-Null
}

$applied = New-Object System.Collections.Generic.List[object]
$pending = New-Object System.Collections.Generic.List[object]
$bootstrapErrors = New-Object System.Collections.Generic.List[object]

if ($globalReady -eq 0) {
    $globalManifest = Get-Content -LiteralPath $globalManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $globalMetrics = Get-Content -LiteralPath $globalMetricsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $globalManifest = $null
    $globalMetrics = $null
}

foreach ($candidate in @($candidates.ToArray())) {
    $row = [ordered]@{
        symbol_alias = $candidate.symbol_alias
        missing_artifacts = @($candidate.missing_artifacts)
        mode = "GLOBAL_SHADOW_BOOTSTRAP"
        target_key_dir = $candidate.target_key_dir
    }

    if ($globalReady -ne 0) {
        $row.status = "GLOBAL_RUNTIME_MISSING"
        $pending.Add([pscustomobject]$row) | Out-Null
        continue
    }

    if (-not $Apply) {
        $row.status = "PENDING"
        $pending.Add([pscustomobject]$row) | Out-Null
        continue
    }

    try {
        New-Item -ItemType Directory -Force -Path $candidate.target_key_dir | Out-Null

        $manifestObject = [ordered]@{}
        foreach ($property in $globalManifest.PSObject.Properties) {
            $manifestObject[$property.Name] = $property.Value
        }
        $manifestObject.symbol = $candidate.symbol_alias
        $manifestObject.bootstrap_mode = "GLOBAL_SHADOW_BOOTSTRAP"
        $manifestObject.bootstrap_source_symbol = "_GLOBAL"
        $manifestObject.bootstrap_applied_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $manifestObject.bootstrap_applied_at_utc = (Get-Date).ToUniversalTime().ToString("o")

        $metricsObject = [ordered]@{}
        foreach ($property in $globalMetrics.PSObject.Properties) {
            $metricsObject[$property.Name] = $property.Value
        }
        $metricsObject.symbol = $candidate.symbol_alias
        $metricsObject.bootstrap_mode = "GLOBAL_SHADOW_BOOTSTRAP"
        $metricsObject.bootstrap_source_symbol = "_GLOBAL"
        $metricsObject.bootstrap_applied_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $metricsObject.bootstrap_applied_at_utc = (Get-Date).ToUniversalTime().ToString("o")

        Copy-Item -LiteralPath $globalOnnxPath -Destination (Join-Path $candidate.target_key_dir "paper_gate_acceptor_runtime_latest.onnx") -Force
        ($manifestObject | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $candidate.target_key_dir "paper_gate_acceptor_runtime_manifest_latest.json") -Encoding UTF8
        ($metricsObject | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $candidate.target_key_dir "paper_gate_acceptor_runtime_metrics_latest.json") -Encoding UTF8
        Write-RuntimeContractCsv -Manifest ([pscustomobject]$manifestObject) -TargetPath (Join-Path $candidate.target_key_dir "paper_gate_acceptor_runtime_contract_latest.csv")

        $row.status = "APPLIED"
        $applied.Add([pscustomobject]$row) | Out-Null
    }
    catch {
        $row.status = "ERROR"
        $row.error = $_.Exception.Message
        $bootstrapErrors.Add([pscustomobject]$row) | Out-Null
    }
}

$appliedItems = @($applied | ForEach-Object { $_ })
$pendingItems = @($pending | ForEach-Object { $_ })
$errorItems = @($bootstrapErrors | ForEach-Object { $_ })
$candidateCount = [int]$candidates.Count
$appliedCount = [int]$appliedItems.Count
$pendingCount = [int]$pendingItems.Count
$errorCount = [int]$errorItems.Count

$summary = New-Object PSObject
$summary | Add-Member -NotePropertyName "candidate_count" -NotePropertyValue $candidateCount
$summary | Add-Member -NotePropertyName "applied_count" -NotePropertyValue $appliedCount
$summary | Add-Member -NotePropertyName "pending_count" -NotePropertyValue $pendingCount
$summary | Add-Member -NotePropertyName "error_count" -NotePropertyValue $errorCount

$report = New-Object PSObject
$report | Add-Member -NotePropertyName "schema_version" -NotePropertyValue "1.0"
$report | Add-Member -NotePropertyName "generated_at_local" -NotePropertyValue ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
$report | Add-Member -NotePropertyName "generated_at_utc" -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o"))
$report | Add-Member -NotePropertyName "apply_mode" -NotePropertyValue ([bool]$Apply)
$report | Add-Member -NotePropertyName "global_runtime_ready" -NotePropertyValue ($globalReady -eq 0)
$report | Add-Member -NotePropertyName "summary" -NotePropertyValue $summary
$report | Add-Member -NotePropertyName "applied" -NotePropertyValue $appliedItems
$report | Add-Member -NotePropertyName "pending" -NotePropertyValue $pendingItems
$report | Add-Member -NotePropertyName "errors" -NotePropertyValue $errorItems

$jsonPath = Join-Path $OutputRoot "shadow_runtime_bootstrap_latest.json"
$mdPath = Join-Path $OutputRoot "shadow_runtime_bootstrap_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Shadow Runtime Bootstrap")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- apply_mode: {0}" -f ([string]$report.apply_mode).ToLowerInvariant()))
$lines.Add(("- global_runtime_ready: {0}" -f ([string]$report.global_runtime_ready).ToLowerInvariant()))
$lines.Add(("- candidate_count: {0}" -f $report.summary.candidate_count))
$lines.Add(("- applied_count: {0}" -f $report.summary.applied_count))
$lines.Add(("- pending_count: {0}" -f $report.summary.pending_count))
$lines.Add(("- error_count: {0}" -f $report.summary.error_count))
$lines.Add("")
$lines.Add("## Applied")
$lines.Add("")
if (@($report.applied).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in @($report.applied)) {
        $lines.Add(("- {0}: {1}" -f $item.symbol_alias, ((@($item.missing_artifacts)) -join ", ")))
    }
}
$lines.Add("")
$lines.Add("## Pending")
$lines.Add("")
if (@($report.pending).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in @($report.pending)) {
        $lines.Add(("- {0}: {1} ({2})" -f $item.symbol_alias, ((@($item.missing_artifacts)) -join ", "), $item.status))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
