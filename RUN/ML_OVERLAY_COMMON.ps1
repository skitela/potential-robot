Set-StrictMode -Version Latest

function ConvertFrom-JsonCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonText
    )

    return $JsonText | ConvertFrom-Json
}

function Get-MlOverlayResolvedRoots {
    param(
        [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
        [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
        [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
        [string]$CommonStateRoot = ""
    )

    $resolvedCommonStateRoot = $CommonStateRoot
    if ([string]::IsNullOrWhiteSpace($resolvedCommonStateRoot)) {
        if ($env:APPDATA) {
            $resolvedCommonStateRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
        }
        else {
            $resolvedCommonStateRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
        }
    }

    [pscustomobject]@{
        ProjectRoot      = $ProjectRoot
        ResearchRoot     = $ResearchRoot
        ResearchPython   = $ResearchPython
        CommonStateRoot  = $resolvedCommonStateRoot
        AuditScript      = Join-Path $ProjectRoot "TOOLS\BUILD_ML_OVERLAY_AUDIT.py"
        SyncStateScript  = Join-Path $ProjectRoot "TOOLS\SYNC_MT5_ML_RUNTIME_STATE.py"
        TailBridgeScript = Join-Path $ProjectRoot "RUN\BUILD_SERVER_PARITY_TAIL_BRIDGE.ps1"
        LedgerScript     = Join-Path $ProjectRoot "RUN\BUILD_BROKER_NET_LEDGER.ps1"
        ExportScript     = Join-Path $ProjectRoot "RUN\EXPORT_MT5_PAPER_GATE_PACKAGE.ps1"
        AuditJsonPath    = Join-Path $ProjectRoot "EVIDENCE\OPS\ml_overlay_supervision_latest.json"
    }
}

function Invoke-MlOverlayPreTrain {
    param(
        [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
        [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
        [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
        [string]$CommonStateRoot = "",
        [switch]$AllowFreshSkip
    )

    $roots = Get-MlOverlayResolvedRoots -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot

    if ($AllowFreshSkip -and (Test-Path $roots.AuditJsonPath)) {
        try {
            $cached = ConvertFrom-JsonCompat -JsonText (Get-Content $roots.AuditJsonPath -Raw)
            if ($cached.tail_bridge.ok -and $cached.broker_net_ledger.ok) {
                return $cached
            }
        }
        catch {
        }
    }

    & $roots.TailBridgeScript -ProjectRoot $roots.ProjectRoot -ResearchRoot $roots.ResearchRoot -ResearchPython $roots.ResearchPython -CommonStateRoot $roots.CommonStateRoot
    if ($LASTEXITCODE -ne 0) {
        throw "BUILD_SERVER_PARITY_TAIL_BRIDGE_FAILED"
    }

    & $roots.LedgerScript -ProjectRoot $roots.ProjectRoot -ResearchRoot $roots.ResearchRoot -ResearchPython $roots.ResearchPython -CommonStateRoot $roots.CommonStateRoot
    if ($LASTEXITCODE -ne 0) {
        throw "BUILD_BROKER_NET_LEDGER_FAILED"
    }

    return Invoke-MlOverlayAudit -ProjectRoot $roots.ProjectRoot -ResearchRoot $roots.ResearchRoot -ResearchPython $roots.ResearchPython -CommonStateRoot $roots.CommonStateRoot
}

function Invoke-MlOverlayPostTrain {
    param(
        [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
        [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
        [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
        [string]$CommonStateRoot = "",
        [switch]$ExportOnPromotionOnly,
        [switch]$FailOnRolloutBlock
    )

    $roots = Get-MlOverlayResolvedRoots -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot
    $auditBefore = Invoke-MlOverlayAudit -ProjectRoot $roots.ProjectRoot -ResearchRoot $roots.ResearchRoot -ResearchPython $roots.ResearchPython -CommonStateRoot $roots.CommonStateRoot
    $shouldExport = $true

    if ($ExportOnPromotionOnly -and $auditBefore.summary.rollout_blocked) {
        $shouldExport = $false
        Write-Warning "ML overlay export skipped because rollout is currently blocked by audit."
    }

    if ($shouldExport) {
        & $roots.ExportScript -ProjectRoot $roots.ProjectRoot -ResearchRoot $roots.ResearchRoot -ResearchPython $roots.ResearchPython -CommonStateRoot $roots.CommonStateRoot
        if ($LASTEXITCODE -ne 0) {
            throw "EXPORT_MT5_PAPER_GATE_PACKAGE_FAILED"
        }

        & $roots.ResearchPython $roots.SyncStateScript `
            --project-root $roots.ProjectRoot `
            --research-root $roots.ResearchRoot `
            --common-state-root $roots.CommonStateRoot
        if ($LASTEXITCODE -ne 0) {
            throw "SYNC_MT5_ML_RUNTIME_STATE_FAILED"
        }
    }

    $auditAfter = Invoke-MlOverlayAudit -ProjectRoot $roots.ProjectRoot -ResearchRoot $roots.ResearchRoot -ResearchPython $roots.ResearchPython -CommonStateRoot $roots.CommonStateRoot
    if ($FailOnRolloutBlock -and $auditAfter.summary.rollout_blocked) {
        throw "ML_OVERLAY_ROLLOUT_BLOCKED"
    }
    return $auditAfter
}

function Invoke-MlOverlayAudit {
    param(
        [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
        [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
        [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
        [string]$CommonStateRoot = "",
        [switch]$FailOnRolloutBlock
    )

    $roots = Get-MlOverlayResolvedRoots -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot

    $auditArgs = @(
        $roots.AuditScript,
        "--project-root", $roots.ProjectRoot,
        "--research-root", $roots.ResearchRoot,
        "--common-state-root", $roots.CommonStateRoot
    )
    if ($FailOnRolloutBlock) {
        $auditArgs += "--fail-on-rollout-block"
    }

    & $roots.ResearchPython @auditArgs | Out-Null
    $exitCode = $LASTEXITCODE

    if (-not (Test-Path $roots.AuditJsonPath)) {
        if ($exitCode -eq 0) {
            throw "ML_OVERLAY_AUDIT_OUTPUT_MISSING"
        }
        throw "ML_OVERLAY_AUDIT_FAILED"
    }

    $payload = ConvertFrom-JsonCompat -JsonText (Get-Content $roots.AuditJsonPath -Raw)
    if ($FailOnRolloutBlock -and $payload.summary.rollout_blocked) {
        throw "ML_OVERLAY_ROLLOUT_BLOCKED"
    }
    return $payload
}

function Get-MlOverlayMigrationArtifacts {
    param(
        [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
        [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
        [string]$CommonStateRoot = ""
    )

    $roots = Get-MlOverlayResolvedRoots -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -CommonStateRoot $CommonStateRoot
    $registryPath = Join-Path $roots.ProjectRoot "CONFIG\microbots_registry.json"
    $artifacts = New-Object System.Collections.Generic.List[string]

    $globalArtifacts = @(
        (Join-Path $roots.ResearchRoot "models\paper_gate_acceptor\paper_gate_acceptor_latest.onnx"),
        (Join-Path $roots.ResearchRoot "models\paper_gate_acceptor_mt5_package_latest.json"),
        (Join-Path $roots.CommonStateRoot "MAKRO_I_MIKRO_BOT\state\_global\student_gate_registry_latest.json")
    )
    foreach ($item in $globalArtifacts) {
        if (Test-Path $item) {
            [void]$artifacts.Add($item)
        }
    }

    if (Test-Path $registryPath) {
        $registry = ConvertFrom-JsonCompat -JsonText (Get-Content $registryPath -Raw)
        foreach ($entry in $registry.symbols) {
            $symbol = $entry.symbol
            $symbolModelDir = Join-Path $roots.ResearchRoot ("models\paper_gate_acceptor_by_symbol\" + $symbol)
            if (Test-Path $symbolModelDir) {
                Get-ChildItem -Path $symbolModelDir -File -Include *.onnx,*.json,*.joblib | ForEach-Object {
                    [void]$artifacts.Add($_.FullName)
                }
            }
            $contractPath = Join-Path $roots.CommonStateRoot ("MAKRO_I_MIKRO_BOT\state\" + $symbol + "\student_gate_contract.csv")
            if (Test-Path $contractPath) {
                [void]$artifacts.Add($contractPath)
            }
        }
    }

    return $artifacts
}

function Get-MlOverlaySpoolIncludePatterns {
    @(
        "*\onnx_observations.csv",
        "*\learning_observations_v2.csv",
        "*\ml_execution_snapshot_latest.json",
        "*\student_gate_latest.json",
        "*\broker_net_ledger_runtime.csv",
        "*\execution_summary.json",
        "*\runtime_state.csv"
    )
}
