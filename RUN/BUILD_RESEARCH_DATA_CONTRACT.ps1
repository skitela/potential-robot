param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [int]$FreshContractThresholdSeconds = 1800,
    [int]$RetryCount = 6,
    [int]$RetryDelaySeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pythonExe = Join-Path $EnvRoot "Scripts\python.exe"
$scriptPath = Join-Path $ProjectRoot "TOOLS\EXPORT_MT5_RESEARCH_DATA.py"
$spoolSyncScript = Join-Path $ProjectRoot "RUN\SYNC_VPS_SPOOL_BACKLOG.ps1"

if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Research python not found: $pythonExe"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Export script not found: $scriptPath"
}
if (-not (Test-Path -LiteralPath $spoolSyncScript)) {
    throw "Spool sync script not found: $spoolSyncScript"
}

$contractManifestPath = Join-Path $ResearchRoot "reports\research_contract_manifest_latest.json"
$researchManifestPath = Join-Path $ResearchRoot "reports\research_export_manifest_latest.json"

function Get-ContractFileAgeSecondsOrMax {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int]::MaxValue
    }

    return [int][math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds)
}

function Get-ExportProcessCount {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "python.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*EXPORT_MT5_RESEARCH_DATA.py*"
            }
    ).Count
}

function Test-ContractUpToDate {
    param(
        [string]$ResearchRoot,
        [string]$ContractManifestPath,
        [string]$ResearchManifestPath
    )

    if (-not (Test-Path -LiteralPath $ContractManifestPath)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $ResearchManifestPath)) {
        return $false
    }

    $contractManifest = Get-Content -LiteralPath $ContractManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $researchManifest = Get-Content -LiteralPath $ResearchManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $requiredSchemas = @{
        onnx_observations_norm = @("feedback_key")
        candidate_signals_norm = @("feedback_key", "outcome_key", "side_normalized", "advisory_match_key")
        learning_observations_v2_norm = @("outcome_key", "side_normalized", "advisory_match_key")
    }
    foreach ($itemName in $requiredSchemas.Keys) {
        $item = $contractManifest.items.$itemName
        if ($null -eq $item) {
            return $false
        }
        $schemaNames = @($item.schema | ForEach-Object { [string]$_.name })
        foreach ($requiredColumn in $requiredSchemas[$itemName]) {
            if ($schemaNames -notcontains $requiredColumn) {
                return $false
            }
        }
    }

    $datasetRowChecks = @(
        @{ raw = "onnx_observations"; normalized = "onnx_observations_norm" },
        @{ raw = "candidate_signals"; normalized = "candidate_signals_norm" },
        @{ raw = "learning_observations_v2"; normalized = "learning_observations_v2_norm" }
    )
    foreach ($entry in $datasetRowChecks) {
        $dataset = $researchManifest.datasets.($entry.raw)
        $contractItem = $contractManifest.items.($entry.normalized)
        if ($null -eq $dataset -or $null -eq $contractItem) {
            return $false
        }

        $manifestRows = [int]$dataset.rows
        $sourceRows = [int]$contractItem.source_rows
        if ($manifestRows -ne $sourceRows) {
            return $false
        }
    }

    $contractFiles = @(
        (Join-Path $ResearchRoot "datasets\contracts\onnx_observations_norm_latest.parquet"),
        (Join-Path $ResearchRoot "datasets\contracts\candidate_signals_norm_latest.parquet"),
        (Join-Path $ResearchRoot "datasets\contracts\learning_observations_v2_norm_latest.parquet")
    )
    foreach ($path in $contractFiles) {
        if (-not (Test-Path -LiteralPath $path)) {
            return $false
        }
    }

    $contractTime = (Get-Item -LiteralPath $ContractManifestPath).LastWriteTime
    $researchManifestTime = (Get-Item -LiteralPath $ResearchManifestPath).LastWriteTime
    $sourceFiles = @(
        (Join-Path $ResearchRoot "datasets\onnx_observations_latest.parquet"),
        (Join-Path $ResearchRoot "datasets\candidate_signals_latest.parquet"),
        (Join-Path $ResearchRoot "datasets\learning_observations_v2_latest.parquet")
    )

    foreach ($path in $sourceFiles) {
        if (-not (Test-Path -LiteralPath $path)) {
            return $false
        }
        if ((Get-Item -LiteralPath $path).LastWriteTime -gt $contractTime) {
            return $false
        }
        if ((Get-Item -LiteralPath $path).LastWriteTime -gt $researchManifestTime) {
            return $false
        }
    }

    return $true
}

$contractAgeSeconds = Get-ContractFileAgeSecondsOrMax -Path $contractManifestPath
if ((Test-ContractUpToDate -ResearchRoot $ResearchRoot -ContractManifestPath $contractManifestPath -ResearchManifestPath $researchManifestPath) -and $contractAgeSeconds -le [Math]::Max(120, $FreshContractThresholdSeconds)) {
    Write-Host "Research contract already up to date; skipping rebuild."
    return
}

$attempt = 0
while ($true) {
    $attempt++
    $activeExports = Get-ExportProcessCount
    if ($activeExports -gt 0) {
        $contractAgeSeconds = Get-ContractFileAgeSecondsOrMax -Path $contractManifestPath
        if ((Test-ContractUpToDate -ResearchRoot $ResearchRoot -ContractManifestPath $contractManifestPath -ResearchManifestPath $researchManifestPath) -and $contractAgeSeconds -le [Math]::Max(120, $FreshContractThresholdSeconds)) {
            Write-Host "Research contract already fresh; skipping duplicate export cycle."
            return
        }

        if ($attempt -lt [Math]::Max(1, $RetryCount)) {
            Start-Sleep -Seconds ([Math]::Max(1, $RetryDelaySeconds))
            continue
        }

        Write-Host ("Research export runner already active; deferring contract rebuild. contract_age_seconds={0}" -f $contractAgeSeconds)
        return
    }

    break
}

& $spoolSyncScript `
    -ProjectRoot $ProjectRoot `
    -EnvRoot $EnvRoot `
    -ResearchRoot $ResearchRoot | Out-Null

& $pythonExe $scriptPath `
    --project-root $ProjectRoot `
    --output-root $ResearchRoot `
    --contract-only
