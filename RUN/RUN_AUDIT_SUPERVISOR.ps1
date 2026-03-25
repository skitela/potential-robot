param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [ValidateSet("Once", "Loop")]
    [string]$Mode = "Once",
    [int]$CycleSeconds = 300,
    [int]$HeavySweepEveryCycles = 36,
    [switch]$ApplySafeAutoHeal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

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

function Get-OptionalValue {
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

function ConvertTo-SeverityRank {
    param([string]$Severity)

    $normalized = ""
    if (-not [string]::IsNullOrWhiteSpace($Severity)) {
        $normalized = $Severity.Trim().ToLowerInvariant()
    }

    switch ($normalized) {
        "critical" { return 4 }
        "high" { return 3 }
        "medium" { return 2 }
        "low" { return 1 }
        default { return 0 }
    }
}

function ConvertTo-GateRank {
    param([string]$Gate)

    $normalized = ""
    if (-not [string]::IsNullOrWhiteSpace($Gate)) {
        $normalized = $Gate.Trim().ToUpperInvariant()
    }

    switch ($normalized) {
        "BLOKUJ_LIVE" { return 4 }
        "BLOKUJ_ROLLOUT" { return 3 }
        "NAPRAW_W_CYKLU" { return 2 }
        "RAPORTUJ" { return 1 }
        default { return 0 }
    }
}

function Invoke-PowerShellScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    $result = [ordered]@{
        script = $ScriptPath
        ok = $false
        message = ""
    }

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        $result.message = "missing"
        return [pscustomobject]$result
    }

    try {
        & $ScriptPath @Parameters | Out-Null
        $result.ok = $true
        $result.message = "ok"
    }
    catch {
        $result.message = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Invoke-WrapperStarter {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    $result = [ordered]@{
        script = $ScriptPath
        ok = $false
        message = ""
    }

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        $result.message = "missing"
        return [pscustomobject]$result
    }

    try {
        $output = & $ScriptPath @Parameters 2>&1 | Out-String
        $result.ok = $true
        $result.message = ($output -replace '\s+', ' ').Trim()
    }
    catch {
        $result.message = $_.Exception.Message
    }

    return [pscustomobject]$result
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

function New-DomainStatus {
    param(
        [string]$Domain,
        [string]$Gate,
        [string]$Severity,
        [string]$Reason,
        [object[]]$Evidence = @()
    )

    return [pscustomobject]@{
        domain = $Domain
        gate = $Gate
        severity = $Severity
        reason = $Reason
        evidence = @($Evidence)
    }
}

function Get-OverallGate {
    param([object[]]$DomainStatuses)

    $best = "OK"
    $bestRank = 0

    foreach ($status in @($DomainStatuses)) {
        $rank = ConvertTo-GateRank -Gate ([string]$status.gate)
        if ($rank -gt $bestRank) {
            $bestRank = $rank
            $best = [string]$status.gate
        }
    }

    return $best
}

function Get-HighestSeverity {
    param([object[]]$Findings)

    $best = "info"
    $bestRank = 0

    foreach ($finding in @($Findings)) {
        $rank = ConvertTo-SeverityRank -Severity ([string]$finding.severity)
        if ($rank -gt $bestRank) {
            $bestRank = $rank
            $best = [string]$finding.severity
        }
    }

    return $best
}

function Test-IsIgnorableRetiredSymbolFinding {
    param([object]$Finding)

    if ($null -eq $Finding -or [string]$Finding.component -ne "retired_symbol_references") {
        return $false
    }

    $hits = @()
    if ($null -ne $Finding.context) {
        $hits = @($Finding.context.hits)
    }
    if ($hits.Count -eq 0) {
        return $false
    }

    foreach ($hit in $hits) {
        $path = [string](Get-OptionalValue -Object $hit -Name "path" -Default "")
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }

        $normalizedPath = $path.Replace("/", "\").ToUpperInvariant()
        $isAuditOrValidationHelper =
            $normalizedPath -like "*\TOOLS\VALIDATE_TRANSFER_PACKAGE.PS1" -or
            $normalizedPath -like "*\RUN\RUN_AUDIT_SUPERVISOR.PS1" -or
            $normalizedPath -like "*\RUN\BUILD_HOSTILE_FOUR_LOOP_AUDIT.PS1"

        if (-not $isAuditOrValidationHelper) {
            return $false
        }
    }

    return $true
}

function Get-ShouldRunHeavySweep {
    param(
        [string]$ModeValue,
        [int]$CycleNumber,
        [int]$EveryCycles
    )

    if ($ModeValue -eq "Once") {
        return $true
    }

    if ($EveryCycles -le 1) {
        return $true
    }

    return (($CycleNumber % $EveryCycles) -eq 0)
}

function Get-FreshnessEntry {
    param(
        [object[]]$Freshness,
        [string]$Label
    )

    return ,@($Freshness | Where-Object { $_.label -eq $Label } | Select-Object -First 1)
}

function Invoke-AuditCycle {
    param(
        [int]$CycleNumber
    )

    $heavySweep = Get-ShouldRunHeavySweep -ModeValue $Mode -CycleNumber $CycleNumber -EveryCycles $HeavySweepEveryCycles
    $timestampLocal = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $timestampUtc = (Get-Date).ToUniversalTime().ToString("o")

    $refreshResults = New-Object System.Collections.Generic.List[object]
    $autoHealResults = New-Object System.Collections.Generic.List[object]

    $fullStackPath = Join-Path $opsRoot "full_stack_audit_latest.json"
    $trustPath = Join-Path $opsRoot "trust_but_verify_latest.json"
    $learningPath = Join-Path $opsRoot "learning_stack_audit_latest.json"
    $learningHealthPath = Join-Path $opsRoot "learning_health_registry_latest.json"
    $learningPaperRuntimePath = Join-Path $opsRoot "learning_paper_runtime_plan_latest.json"
    $learningDataContractPath = Join-Path $opsRoot "learning_data_contract_audit_latest.json"
    $onnxFeedbackPath = Join-Path $opsRoot "onnx_feedback_loop_latest.json"
    $onnxCrossAuditPath = Join-Path $opsRoot "onnx_micro_cross_audit_latest.json"
    $hostilePath = Join-Path $opsRoot "hostile_four_loop_audit_latest.json"
    $discoveryPath = Join-Path $opsRoot "audit_supervisor_discovery_latest.json"
    $learningHygienePath = Join-Path $opsRoot "learning_path_hygiene_latest.json"
    $learningWellbeingPath = Join-Path $opsRoot "learning_wellbeing_latest.json"
    $vpsSpoolWellbeingPath = Join-Path $opsRoot "vps_spool_wellbeing_latest.json"
    $instrumentDataReadinessPath = Join-Path $opsRoot "instrument_data_readiness_latest.json"
    $instrumentShadowDatasetsPath = Join-Path $opsRoot "instrument_shadow_datasets_latest.json"
    $instrumentTrainingReadinessPath = Join-Path $opsRoot "instrument_training_readiness_latest.json"

    $buildScripts = @(
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_TRUST_BUT_VERIFY_AUDIT.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_PATH_HYGIENE.ps1")
            params = @{
                ProjectRoot = $ProjectRoot
                Apply = [bool]$ApplySafeAutoHeal
            }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_FULL_STACK_AUDIT.ps1")
            params = @{
                ProjectRoot = $ProjectRoot
                ApplyRuntimeCleanup = [bool]$ApplySafeAutoHeal
                ApplyLogRotation = [bool]$ApplySafeAutoHeal
            }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_STACK_AUDIT.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_HEALTH_REGISTRY.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_DATA_READINESS_REPORT.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_SHADOW_DATASETS_REPORT.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_TRAINING_READINESS_REPORT.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_PAPER_RUNTIME_PLAN.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\MAINTAIN_LEARNING_WELLBEING.ps1")
            params = @{
                ProjectRoot = $ProjectRoot
                Apply = [bool]$ApplySafeAutoHeal
            }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_RESEARCH_DATA_CONTRACT.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_DATA_CONTRACT_AUDIT.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_ONNX_FEEDBACK_LOOP_REPORT.ps1")
            params = @{ ProjectRoot = $ProjectRoot }
        },
        @{
            path = (Join-Path $ProjectRoot "RUN\BUILD_ONNX_MICRO_CROSS_AUDIT_REPORT.ps1")
            params = @{ EvidenceDir = $opsRoot }
        }
    )

    if ($heavySweep) {
        $buildScripts += @(
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_HOSTILE_FOUR_LOOP_AUDIT.ps1")
                params = @{ ProjectRoot = $ProjectRoot; EvidenceDir = $opsRoot }
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_AUDIT_SUPERVISOR_DISCOVERY_REPORT.ps1")
                params = @{ ProjectRoot = $ProjectRoot; EvidenceRoot = (Join-Path $ProjectRoot "EVIDENCE"); OpsRoot = $opsRoot; LookbackDays = 7 }
            }
        )
    }

    foreach ($script in $buildScripts) {
        $refreshResults.Add((Invoke-PowerShellScript -ScriptPath $script.path -Parameters $script.params)) | Out-Null
    }

    if ($ApplySafeAutoHeal) {
        $starterScripts = @(
            @{
                path = (Join-Path $ProjectRoot "RUN\START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1")
                params = @{ ProjectRoot = $ProjectRoot; OutputRoot = $opsRoot; IntervalMinutes = 5 }
                pattern = "*local_operator_archiver_wrapper_*"
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\START_MT5_TESTER_STATUS_WATCHER_BACKGROUND.ps1")
                params = @{ ProjectRoot = $ProjectRoot; OutputRoot = $opsRoot; PollSeconds = 60 }
                pattern = "*mt5_tester_status_watcher_wrapper_*"
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\START_AUTONOMOUS_90P_SUPERVISOR_BACKGROUND.ps1")
                params = @{ ProjectRoot = $ProjectRoot; LogRoot = $opsRoot; CycleSeconds = 180 }
                pattern = "*autonomous_90p_supervisor_wrapper_*"
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1")
                params = @{ ProjectRoot = $ProjectRoot; LogRoot = "C:\TRADING_DATA\RESEARCH\reports" }
                pattern = "*refresh_and_train_ml_wrapper_*"
            }
        )

        foreach ($starter in $starterScripts) {
            if ((Get-WrapperCount -Pattern $starter.pattern) -gt 0) {
                $autoHealResults.Add([pscustomobject]@{
                    script = $starter.path
                    ok = $true
                    message = "already_running"
                }) | Out-Null
                continue
            }

            $autoHealResults.Add((Invoke-WrapperStarter -ScriptPath $starter.path -Parameters $starter.params)) | Out-Null
        }

        $postHealScripts = @(
            @{
                path = (Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_PATH_HYGIENE.ps1")
                params = @{
                    ProjectRoot = $ProjectRoot
                    Apply = $true
                }
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_TRUST_BUT_VERIFY_AUDIT.ps1")
                params = @{ ProjectRoot = $ProjectRoot }
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_FULL_STACK_AUDIT.ps1")
                params = @{
                    ProjectRoot = $ProjectRoot
                    ApplyRuntimeCleanup = $true
                    ApplyLogRotation = $true
                }
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_STACK_AUDIT.ps1")
                params = @{ ProjectRoot = $ProjectRoot }
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_HEALTH_REGISTRY.ps1")
                params = @{ ProjectRoot = $ProjectRoot }
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_RESEARCH_DATA_CONTRACT.ps1")
                params = @{ ProjectRoot = $ProjectRoot }
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_DATA_CONTRACT_AUDIT.ps1")
                params = @{ ProjectRoot = $ProjectRoot }
            },
            @{
                path = (Join-Path $ProjectRoot "RUN\BUILD_ONNX_FEEDBACK_LOOP_REPORT.ps1")
                params = @{ ProjectRoot = $ProjectRoot }
            }
        )

        foreach ($script in $postHealScripts) {
            $refreshResults.Add((Invoke-PowerShellScript -ScriptPath $script.path -Parameters $script.params)) | Out-Null
        }

        $postHealFullStack = Read-JsonSafe -Path $fullStackPath
        $postHealLearningHygiene = Read-JsonSafe -Path $learningHygienePath
        $postHealFreshness = @()
        if ($null -ne $postHealFullStack) {
            $postHealFreshness = @((Get-OptionalValue -Object $postHealFullStack -Name "freshness" -Default @()))
        }

        $researchManifestEntry = Get-FreshnessEntry -Freshness $postHealFreshness -Label "research_export_manifest"
        $researchManifestFresh = ($researchManifestEntry.Count -gt 0 -and [bool](Get-OptionalValue -Object $researchManifestEntry[0] -Name "fresh" -Default $false))
        $learningLogBacklog = 0
        if ($null -ne $postHealLearningHygiene) {
            $learningLogBacklog = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $postHealLearningHygiene -Name "refresh_and_train_logs" -Default $null) -Name "archive_candidate_count" -Default 0)
        }

        if (-not $researchManifestFresh) {
            $autoHealResults.Add((Invoke-PowerShellScript -ScriptPath (Join-Path $ProjectRoot "RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1") -Parameters @{
                ProjectRoot = $ProjectRoot
                PerfProfile = "Light"
            })) | Out-Null
        }

        if ((-not $researchManifestFresh) -or $learningLogBacklog -gt 0 -or $heavySweep) {
            $focusedRepairScripts = @(
                @{
                    path = (Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_PATH_HYGIENE.ps1")
                    params = @{
                        ProjectRoot = $ProjectRoot
                        Apply = $true
                    }
                },
                @{
                    path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_STACK_AUDIT.ps1")
                    params = @{ ProjectRoot = $ProjectRoot }
                },
                @{
                    path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_HEALTH_REGISTRY.ps1")
                    params = @{ ProjectRoot = $ProjectRoot }
                },
                @{
                    path = (Join-Path $ProjectRoot "RUN\BUILD_RESEARCH_DATA_CONTRACT.ps1")
                    params = @{ ProjectRoot = $ProjectRoot }
                },
                @{
                    path = (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_DATA_CONTRACT_AUDIT.ps1")
                    params = @{ ProjectRoot = $ProjectRoot }
                },
                @{
                    path = (Join-Path $ProjectRoot "RUN\BUILD_FULL_STACK_AUDIT.ps1")
                    params = @{
                        ProjectRoot = $ProjectRoot
                        ApplyRuntimeCleanup = $true
                        ApplyLogRotation = $true
                    }
                },
                @{
                    path = (Join-Path $ProjectRoot "RUN\BUILD_ONNX_FEEDBACK_LOOP_REPORT.ps1")
                    params = @{ ProjectRoot = $ProjectRoot }
                }
            )

            foreach ($script in $focusedRepairScripts) {
                $refreshResults.Add((Invoke-PowerShellScript -ScriptPath $script.path -Parameters $script.params)) | Out-Null
            }
        }
    }

    $fullStack = Read-JsonSafe -Path $fullStackPath
    $trust = Read-JsonSafe -Path $trustPath
    $learning = Read-JsonSafe -Path $learningPath
    $learningHealth = Read-JsonSafe -Path $learningHealthPath
    $instrumentDataReadiness = Read-JsonSafe -Path $instrumentDataReadinessPath
    $instrumentShadowDatasets = Read-JsonSafe -Path $instrumentShadowDatasetsPath
    $instrumentTrainingReadiness = Read-JsonSafe -Path $instrumentTrainingReadinessPath
    $learningPaperRuntime = Read-JsonSafe -Path $learningPaperRuntimePath
    $learningDataContract = Read-JsonSafe -Path $learningDataContractPath
    $onnxFeedback = Read-JsonSafe -Path $onnxFeedbackPath
    $onnxCrossAudit = Read-JsonSafe -Path $onnxCrossAuditPath
    $hostile = Read-JsonSafe -Path $hostilePath
    $discovery = Read-JsonSafe -Path $discoveryPath
    $learningHygiene = Read-JsonSafe -Path $learningHygienePath
    $learningWellbeing = Read-JsonSafe -Path $learningWellbeingPath
    $vpsSpoolWellbeing = Read-JsonSafe -Path $vpsSpoolWellbeingPath

    $hostileFindings = @()
    if ($null -ne $hostile) {
        $hostileFindings = @($hostile.findings)
    }

    $domainStatuses = New-Object System.Collections.Generic.List[object]

    $deploymentEvidence = New-Object System.Collections.Generic.List[object]
    $deploymentFindings = @($hostileFindings | Where-Object { $_.component -eq "registry_files" })
    foreach ($finding in $deploymentFindings) {
        $deploymentEvidence.Add($finding) | Out-Null
    }
    foreach ($result in ([object[]]$refreshResults.ToArray() | Where-Object { -not $_.ok })) {
        if ([string]$result.script -like "*BUILD_FULL_STACK_AUDIT*" -or
            [string]$result.script -like "*BUILD_HOSTILE_FOUR_LOOP_AUDIT*" -or
            [string]$result.script -like "*BUILD_AUDIT_SUPERVISOR_DISCOVERY_REPORT*") {
            $deploymentEvidence.Add($result) | Out-Null
        }
    }

    if ($deploymentEvidence.Count -gt 0) {
        $domainStatuses.Add((New-DomainStatus -Domain "POCHODZENIE_WDROZENIA" -Gate "BLOKUJ_ROLLOUT" -Severity "critical" -Reason "Brak pewnosci co do poprawnosci paczki lub raportow rolloutowych." -Evidence $deploymentEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "POCHODZENIE_WDROZENIA" -Gate "RAPORTUJ" -Severity "info" -Reason "Brak aktywnych sygnalow o zlej paczce lub uszkodzonym pochodzeniu wdrozenia.")) | Out-Null
    }

    $fleetEvidence = New-Object System.Collections.Generic.List[object]
    $fleetFindings = @(
        $hostileFindings |
            Where-Object { $_.component -in @("retired_symbol_references", "family_symbol_naming", "family_reference_registry") } |
            Where-Object { -not (Test-IsIgnorableRetiredSymbolFinding -Finding $_) }
    )
    foreach ($finding in $fleetFindings) {
        $fleetEvidence.Add($finding) | Out-Null
    }
    if ($fleetEvidence.Count -gt 0) {
        $hasBlockingFleet = @($fleetEvidence | Where-Object { $_.component -eq "retired_symbol_references" }).Count -gt 0
        $gate = if ($hasBlockingFleet) { "BLOKUJ_ROLLOUT" } else { "NAPRAW_W_CYKLU" }
        $severity = if ($hasBlockingFleet) { "high" } else { "medium" }
        $reason = if ($hasBlockingFleet) {
            "Flota i runtime nie sa calkiem zgodne; wycofane symbole nie moga wracac bokiem."
        }
        else {
            "Nazewnictwo rodzin lub referencji wymaga dalszego porzadku."
        }
        $domainStatuses.Add((New-DomainStatus -Domain "SPOJNOSC_FLOTY" -Gate $gate -Severity $severity -Reason $reason -Evidence $fleetEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "SPOJNOSC_FLOTY" -Gate "RAPORTUJ" -Severity "info" -Reason "Flota, kolejki i wycofane symbole sa spojne.")) | Out-Null
    }

    $learningHygieneEvidence = New-Object System.Collections.Generic.List[object]
    foreach ($result in ([object[]]$refreshResults.ToArray() | Where-Object {
        -not $_.ok -and (
            [string]$_.script -like "*CLEAN_LEARNING_PATH_HYGIENE*" -or
            [string]$_.script -like "*REFRESH_MICROBOT_RESEARCH_DATA*"
        )
    })) {
        $learningHygieneEvidence.Add($result) | Out-Null
    }
    foreach ($result in ([object[]]$autoHealResults.ToArray() | Where-Object {
        -not $_.ok -and [string]$_.script -like "*REFRESH_MICROBOT_RESEARCH_DATA*"
    })) {
        $learningHygieneEvidence.Add($result) | Out-Null
    }
    if ($null -ne $learningHygiene) {
        $manifestSection = Get-OptionalValue -Object $learningHygiene -Name "manifest" -Default $null
        $manifestFresh = [bool](Get-OptionalValue -Object $manifestSection -Name "fresh" -Default $false)
        $manifestAge = Get-OptionalValue -Object $manifestSection -Name "age_seconds" -Default $null
        $learningLogsSection = Get-OptionalValue -Object $learningHygiene -Name "refresh_and_train_logs" -Default $null
        $archiveCandidateCount = [int](Get-OptionalValue -Object $learningLogsSection -Name "archive_candidate_count" -Default 0)

        if (-not $manifestFresh) {
            $learningHygieneEvidence.Add([pscustomobject]@{
                severity = "high"
                component = "research_export_manifest"
                message = "Manifest eksportu research nie jest swiezy i wymaga odswiezenia."
                context = @{ age_seconds = $manifestAge }
            }) | Out-Null
        }
        if ($archiveCandidateCount -gt 0) {
            $learningHygieneEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_path_logs"
                message = "Logi sciezki uczenia wymagaja dalszej higieny."
                context = @{ archive_candidate_count = $archiveCandidateCount }
            }) | Out-Null
        }
    }
    if ($null -ne $learningWellbeing) {
        $wellbeingSummary = Get-OptionalValue -Object $learningWellbeing -Name "summary" -Default $null
        $opsPendingCount = [int](Get-OptionalValue -Object $wellbeingSummary -Name "ops_pending_count" -Default 0)
        $runtimeArchivePendingCount = [int](Get-OptionalValue -Object $wellbeingSummary -Name "runtime_archive_pending_count" -Default 0)
        $runtimeArchiveDeletedCount = [int](Get-OptionalValue -Object $wellbeingSummary -Name "runtime_archive_deleted_count" -Default 0)
        $opsDeletedCount = [int](Get-OptionalValue -Object $wellbeingSummary -Name "ops_deleted_count" -Default 0)

        if ($opsPendingCount -gt 0 -or $runtimeArchivePendingCount -gt 0) {
            $learningHygieneEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_wellbeing"
                message = "Dobrostan nadal widzi zalegly balast i wymaga dalszego porzadku."
                context = @{
                    ops_pending_count = $opsPendingCount
                    runtime_archive_pending_count = $runtimeArchivePendingCount
                }
            }) | Out-Null
        }
    }

    if ($learningHygieneEvidence.Count -gt 0) {
        $domainStatuses.Add((New-DomainStatus -Domain "HIGIENA_SCIEZKI_UCZENIA" -Gate "NAPRAW_W_CYKLU" -Severity (Get-HighestSeverity -Findings $learningHygieneEvidence) -Reason "Sciezka uczenia wymaga stalej higieny manifestu i logow." -Evidence $learningHygieneEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "HIGIENA_SCIEZKI_UCZENIA" -Gate "RAPORTUJ" -Severity "info" -Reason "Manifest research i logi sciezki uczenia sa pod kontrola.")) | Out-Null
    }

    $learningDataContractEvidence = New-Object System.Collections.Generic.List[object]
    foreach ($result in ([object[]]$refreshResults.ToArray() | Where-Object {
        -not $_.ok -and [string]$_.script -like "*BUILD_LEARNING_DATA_CONTRACT_AUDIT*"
    })) {
        $learningDataContractEvidence.Add($result) | Out-Null
    }
    if ($null -ne $learningDataContract) {
        $contractVerdict = [string](Get-OptionalValue -Object $learningDataContract -Name "verdict" -Default "")
        $contractSummary = Get-OptionalValue -Object $learningDataContract -Name "summary" -Default $null
        $tablesReady = [int](Get-OptionalValue -Object $contractSummary -Name "tables_ready" -Default 0)
        $tablesChecked = [int](Get-OptionalValue -Object $contractSummary -Name "tables_checked" -Default 0)
        $contractFresh = [bool](Get-OptionalValue -Object $contractSummary -Name "contract_fresh" -Default $false)
        $researchFresh = [bool](Get-OptionalValue -Object $contractSummary -Name "research_fresh" -Default $false)
        $findingsTotal = [int](Get-OptionalValue -Object $contractSummary -Name "findings_total" -Default 0)

        if ($contractVerdict -ne "OK") {
            $learningDataContractEvidence.Add([pscustomobject]@{
                severity = $(if ($contractVerdict -eq "NAPRAW_W_CYKLU") { "high" } else { "medium" })
                component = "learning_data_contract"
                message = "Kontrakt danych uczenia nie jest jeszcze zielony."
                context = @{
                    verdict = $contractVerdict
                    findings_total = $findingsTotal
                    tables_ready = $tablesReady
                    tables_checked = $tablesChecked
                }
            }) | Out-Null
        }
        if (-not $contractFresh) {
            $learningDataContractEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_data_contract"
                message = "Kanoniczny kontrakt danych nie jest swiezy."
            }) | Out-Null
        }
        if (-not $researchFresh) {
            $learningDataContractEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_data_contract"
                message = "Manifest research nie jest swiezy wzgledem kontraktu danych."
            }) | Out-Null
        }
    }

    if ($learningDataContractEvidence.Count -gt 0) {
        $domainStatuses.Add((New-DomainStatus -Domain "KONTRAKT_DANYCH_UCZENIA" -Gate "NAPRAW_W_CYKLU" -Severity (Get-HighestSeverity -Findings $learningDataContractEvidence) -Reason "Dane z wielu zrodel musza byc typowane i zgodne, zanim pojda dalej do ONNX i mikrobotow." -Evidence $learningDataContractEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "KONTRAKT_DANYCH_UCZENIA" -Gate "RAPORTUJ" -Severity "info" -Reason "Kanoniczny kontrakt danych uczenia jest swiezy i spojny.")) | Out-Null
    }

    $runtimeEvidence = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @($hostileFindings | Where-Object { $_.component -in @("git", "runtime_logs", "orphan_dirs") })) {
        $runtimeEvidence.Add($finding) | Out-Null
    }
    if ($null -ne $fullStack) {
        $cleanliness = Get-OptionalValue -Object $fullStack -Name "cleanliness" -Default $null
        $releaseGate = Get-OptionalValue -Object $fullStack -Name "release_gate" -Default $null
        $gitDirtyCount = [int](Get-OptionalValue -Object $cleanliness -Name "git_dirty_count" -Default 0)
        $runtimeArtifactsClean = [bool](Get-OptionalValue -Object $releaseGate -Name "runtime_artifacts_clean" -Default $false)
        $runtimeLogsRotated = [bool](Get-OptionalValue -Object $releaseGate -Name "runtime_logs_under_control" -Default (Get-OptionalValue -Object $releaseGate -Name "runtime_logs_rotated" -Default $false))

        if ($gitDirtyCount -gt 0) {
            $runtimeEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "git"
                message = "Repo nie jest czyste."
                context = @{ git_dirty_count = $gitDirtyCount }
            }) | Out-Null
        }
        if (-not $runtimeArtifactsClean) {
            $runtimeEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "runtime_artifacts"
                message = "Artefakty runtime nie sa jeszcze czyste."
            }) | Out-Null
        }
        if (-not $runtimeLogsRotated) {
            $runtimeEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "runtime_logs"
                message = "Rotacja logow runtime nie zostala potwierdzona."
            }) | Out-Null
        }
    }

    $runtimeBlockingEvidence = @($runtimeEvidence | Where-Object { [string]$_.severity -ne "low" })
    if ($runtimeBlockingEvidence.Count -gt 0) {
        $domainStatuses.Add((New-DomainStatus -Domain "HIGIENA_RUNTIME" -Gate "NAPRAW_W_CYKLU" -Severity (Get-HighestSeverity -Findings $runtimeEvidence) -Reason "Higiena runtime wymaga sprzatania albo dalszej rotacji." -Evidence $runtimeEvidence)) | Out-Null
    }
    elseif ($runtimeEvidence.Count -gt 0) {
        $domainStatuses.Add((New-DomainStatus -Domain "HIGIENA_RUNTIME" -Gate "RAPORTUJ" -Severity "info" -Reason "Runtime jest pod kontrola; pozostaly tylko gorace logi oczekujace na bezpieczne okno rotacji." -Evidence $runtimeEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "HIGIENA_RUNTIME" -Gate "RAPORTUJ" -Severity "info" -Reason "Runtime jest czysty, a logi sa pod kontrola.")) | Out-Null
    }

    $vpsBridgeEvidence = New-Object System.Collections.Generic.List[object]
    if ($null -ne $vpsSpoolWellbeing) {
        $bridgeSummary = Get-OptionalValue -Object $vpsSpoolWellbeing -Name "summary" -Default $null
        $pendingSync = [int](Get-OptionalValue -Object $bridgeSummary -Name "pending_sync_count" -Default 0)
        $bridgeOrphans = [int](Get-OptionalValue -Object $bridgeSummary -Name "state_orphan_count" -Default 0)
        $bridgeLag = [int](Get-OptionalValue -Object $bridgeSummary -Name "export_spool_lag_total" -Default 0)
        $bridgeFindings = [int](Get-OptionalValue -Object $bridgeSummary -Name "findings_total" -Default 0)
        $bridgeRepairs = [int](Get-OptionalValue -Object $bridgeSummary -Name "repair_actions_count" -Default 0)
        $bridgeVerdict = [string](Get-OptionalValue -Object $vpsSpoolWellbeing -Name "verdict" -Default "UNKNOWN")

        if ($pendingSync -gt 0) {
            $vpsBridgeEvidence.Add([pscustomobject]@{
                    severity = "medium"
                    component = "vps_spool_pending_sync"
                    message = "Most VPS-laptop ma zalegly backlog chunkow do odebrania."
                    context = @{
                        pending_sync_count = $pendingSync
                        verdict = $bridgeVerdict
                    }
                }) | Out-Null
        }

        if ($bridgeOrphans -gt 0) {
            $vpsBridgeEvidence.Add([pscustomobject]@{
                    severity = "medium"
                    component = "vps_spool_state_orphans"
                    message = "Stan mostu VPS-laptop zawiera osierocone wpisy i wymaga sprzatania."
                    context = @{
                        state_orphan_count = $bridgeOrphans
                        repair_actions_count = $bridgeRepairs
                    }
                }) | Out-Null
        }

        if ($bridgeLag -gt 0) {
            $vpsBridgeEvidence.Add([pscustomobject]@{
                    severity = "medium"
                    component = "vps_spool_export_lag"
                    message = "Research export jest opozniony wzgledem chunkow dostepnych w inboxie VPS spool."
                    context = @{
                        export_spool_lag_total = $bridgeLag
                        findings_total = $bridgeFindings
                    }
                }) | Out-Null
        }

        if ($bridgeVerdict -eq "MOST_WYMAGA_DALSZEJ_NAPRAWY") {
            $vpsBridgeEvidence.Add([pscustomobject]@{
                    severity = "high"
                    component = "vps_spool_bridge_unhealthy"
                    message = "Most VPS-laptop nie jest zdrowy i wymaga dalszej naprawy."
                    context = @{
                        verdict = $bridgeVerdict
                        findings_total = $bridgeFindings
                    }
                }) | Out-Null
        }
    }

    if ($vpsBridgeEvidence.Count -gt 0) {
        $bridgeHasHigh = @($vpsBridgeEvidence | Where-Object { $_.severity -eq "high" }).Count -gt 0
        $bridgeNeedsRepair = (
            $bridgeHasHigh -or
            $pendingSync -gt 0 -or
            $bridgeOrphans -gt 0 -or
            $bridgeVerdict -in @("MOST_WYMAGA_NAPRAWY", "MOST_WYMAGA_DALSZEJ_NAPRAWY")
        )
        $bridgeGate = if ($bridgeNeedsRepair) { "NAPRAW_W_CYKLU" } else { "RAPORTUJ" }
        $domainStatuses.Add((New-DomainStatus -Domain "MOST_VPS_LAPTOP" -Gate $bridgeGate -Severity (Get-HighestSeverity -Findings $vpsBridgeEvidence) -Reason "Most danych miedzy VPS i laptopem musi byc stale diagnozowany i samonaprawialny." -Evidence $vpsBridgeEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "MOST_VPS_LAPTOP" -Gate "RAPORTUJ" -Severity "info" -Reason "Most VPS-laptop nie pokazuje swiezych odchylen i backlog jest pod kontrola.")) | Out-Null
    }

    $executionEvidence = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @($hostileFindings | Where-Object { $_.component -eq "terminal_ping_in_core" })) {
        $executionEvidence.Add($finding) | Out-Null
    }
    if ($null -ne $trust -and [string](Get-OptionalValue -Object $trust -Name "verdict" -Default "") -ne "OK") {
        $executionEvidence.Add([pscustomobject]@{
            severity = "high"
            component = "trust_but_verify"
            message = "Krzyzowy audyt runtime nie jest zielony."
            context = @{ verdict = [string]$trust.verdict }
        }) | Out-Null
    }

    if ($executionEvidence.Count -gt 0) {
        $blockingExecution = @($executionEvidence | Where-Object { $_.component -eq "terminal_ping_in_core" }).Count -gt 0
        $gate = if ($blockingExecution) { "BLOKUJ_LIVE" } else { "NAPRAW_W_CYKLU" }
        $severity = if ($blockingExecution) { "high" } else { "medium" }
        $reason = if ($blockingExecution) {
            "Warstwa wykonania ma nieprawidlowy kontrakt pingu i nie moze sterowac live."
        }
        else {
            "Warstwa wykonania wymaga dalszej walidacji."
        }
        $domainStatuses.Add((New-DomainStatus -Domain "JAKOSC_WYKONANIA" -Gate $gate -Severity $severity -Reason $reason -Evidence $executionEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "JAKOSC_WYKONANIA" -Gate "RAPORTUJ" -Severity "info" -Reason "Kontrakt wykonania i ping operacyjny wygladaja zdrowo.")) | Out-Null
    }

    $learningEvidence = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @($hostileFindings | Where-Object { $_.component -in @("learning_stack", "learning_runtime") })) {
        $learningEvidence.Add($finding) | Out-Null
    }
    if ($null -ne $learning) {
        $learningSection = Get-OptionalValue -Object $learning -Name "learning" -Default $null
        $learningVerdict = [string](Get-OptionalValue -Object $learningSection -Name "verdict" -Default "")
        $coverage = [double](Get-OptionalValue -Object $learningSection -Name "qdm_coverage_ratio" -Default 0.0)
        if ($learningVerdict -eq "NO_QDM_SIGNAL") {
            $learningEvidence.Add([pscustomobject]@{
                severity = "high"
                component = "learning_stack"
                message = "Uczenie nie widzi sygnalu QDM."
                context = @{ qdm_coverage_ratio = $coverage }
            }) | Out-Null
        }
        elseif ($coverage -lt 0.05) {
            $learningEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_stack"
                message = "Pokrycie QDM w uczeniu jest nadal niskie."
                context = @{ qdm_coverage_ratio = $coverage; learning_verdict = $learningVerdict }
            }) | Out-Null
        }
    }

    if ($learningEvidence.Count -gt 0) {
        $domainStatuses.Add((New-DomainStatus -Domain "STOS_UCZENIA" -Gate "NAPRAW_W_CYKLU" -Severity (Get-HighestSeverity -Findings $learningEvidence) -Reason "Stos uczenia wymaga dalszego odzywienia i pilnowania pokrycia danych." -Evidence $learningEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "STOS_UCZENIA" -Gate "RAPORTUJ" -Severity "info" -Reason "Stos uczenia jest aktywny i nie pokazuje czerwonych flag.")) | Out-Null
    }

    $learningHealthEvidence = New-Object System.Collections.Generic.List[object]
    if ($null -ne $learningHealth) {
        $healthSummary = Get-OptionalValue -Object $learningHealth -Name "summary" -Default $null
        $fallbacks = [int](Get-OptionalValue -Object $healthSummary -Name "fallback_globalny" -Default 0)
        $doszkolenie = [int](Get-OptionalValue -Object $healthSummary -Name "wymaga_doszkolenia" -Default 0)
        $regeneracja = [int](Get-OptionalValue -Object $healthSummary -Name "wymaga_regeneracji" -Default 0)
        $runtimeActive = [int](Get-OptionalValue -Object $healthSummary -Name "runtime_active_symbols" -Default 0)

        if ($fallbacks -gt 0) {
            $learningHealthEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_health_fallbacks"
                message = "Czesc instrumentow nadal korzysta z fallbacku globalnego."
                context = @{ fallback_globalny = $fallbacks }
            }) | Out-Null
        }
        if ($doszkolenie -gt 0) {
            $learningHealthEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_health_retrain"
                message = "Czesc instrumentow wymaga doszkolenia malego ONNX."
                context = @{ wymaga_doszkolenia = $doszkolenie }
            }) | Out-Null
        }
        if ($regeneracja -gt 0) {
            $learningHealthEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_health_regeneration"
                message = "Czesc instrumentow wymaga regeneracji danych lub kosztu."
                context = @{ wymaga_regeneracji = $regeneracja }
            }) | Out-Null
        }
        if ($runtimeActive -le 0) {
            $learningHealthEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "learning_health_runtime"
                message = "Rejestr zdrowia nie widzi jeszcze aktywnych instrumentow runtime ONNX."
                context = @{ runtime_active_symbols = $runtimeActive }
            }) | Out-Null
        }
    }

    if ($learningHealthEvidence.Count -gt 0) {
        $domainStatuses.Add((New-DomainStatus -Domain "ZDROWIE_UCZENIA_PER_INSTRUMENT" -Gate "NAPRAW_W_CYKLU" -Severity (Get-HighestSeverity -Findings $learningHealthEvidence) -Reason "Stan zdrowia instrumentow wymaga dalszego sterowania i samoregulacji." -Evidence $learningHealthEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "ZDROWIE_UCZENIA_PER_INSTRUMENT" -Gate "RAPORTUJ" -Severity "info" -Reason "Rejestr zdrowia uczenia nie pokazuje swiezych czerwonych flag.")) | Out-Null
    }

    $instrumentReadinessEvidence = New-Object System.Collections.Generic.List[object]
    if ($null -ne $instrumentDataReadiness) {
        $dataSummary = Get-OptionalValue -Object $instrumentDataReadiness -Name "summary" -Default $null
        $exportPending = [int](Get-OptionalValue -Object $dataSummary -Name "export_pending_count" -Default 0)
        $contractPending = [int](Get-OptionalValue -Object $dataSummary -Name "contract_pending_count" -Default 0)

        if ($exportPending -gt 0) {
            $instrumentReadinessEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "instrument_data_export_pending"
                message = "Czesc instrumentow ma gotowa historie raw, ale nadal nie ma aktywnego eksportu do treningu."
                context = @{ export_pending_count = $exportPending }
            }) | Out-Null
        }
        if ($contractPending -gt 0) {
            $instrumentReadinessEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "instrument_data_contract_pending"
                message = "Czesc instrumentow ma eksport, ale kontrakt research jeszcze ich nie widzi."
                context = @{ contract_pending_count = $contractPending }
            }) | Out-Null
        }
    }
    if ($null -ne $instrumentTrainingReadiness) {
        $trainingSummary = Get-OptionalValue -Object $instrumentTrainingReadiness -Name "summary" -Default $null
        $shadowReady = [int](Get-OptionalValue -Object $trainingSummary -Name "training_shadow_ready_count" -Default 0)
        $localLimited = [int](Get-OptionalValue -Object $trainingSummary -Name "local_training_limited_count" -Default 0)
        $localReady = [int](Get-OptionalValue -Object $trainingSummary -Name "local_training_ready_count" -Default 0)

        if ($shadowReady -gt 0) {
            $instrumentReadinessEvidence.Add([pscustomobject]@{
                severity = "info"
                component = "instrument_training_shadow_ready"
                message = "Czesc instrumentow jest gotowa do shadowowego budowania lokalnych datasetow."
                context = @{ training_shadow_ready_count = $shadowReady }
            }) | Out-Null
        }
        if (($localLimited + $localReady) -gt 0) {
            $instrumentReadinessEvidence.Add([pscustomobject]@{
                severity = "info"
                component = "instrument_training_local_candidates"
                message = "Pojawili sie kandydaci do lokalnego treningu ograniczonego lub gotowego."
                context = @{ local_training_limited_count = $localLimited; local_training_ready_count = $localReady }
            }) | Out-Null
        }
    }

    if ($null -ne $instrumentShadowDatasets) {
        $shadowSummary = Get-OptionalValue -Object $instrumentShadowDatasets -Name "summary" -Default $null
        $shadowBuilt = [int](Get-OptionalValue -Object $shadowSummary -Name "eligible_for_shadow_dataset_count" -Default 0)
        $shadowReadyDatasets = [int](Get-OptionalValue -Object $shadowSummary -Name "shadow_dataset_ready_count" -Default 0) +
            [int](Get-OptionalValue -Object $shadowSummary -Name "shadow_dataset_runtime_ready_count" -Default 0) +
            [int](Get-OptionalValue -Object $shadowSummary -Name "shadow_dataset_outcome_ready_count" -Default 0)

        if ($shadowBuilt -gt 0 -and $shadowReadyDatasets -gt 0) {
            $instrumentReadinessEvidence.Add([pscustomobject]@{
                severity = "info"
                component = "instrument_shadow_datasets"
                message = "Shadow datasets per instrument sa budowane i zasilaja etap przejsciowy."
                context = @{
                    eligible_for_shadow_dataset_count = $shadowBuilt
                    shadow_dataset_ready_total = $shadowReadyDatasets
                }
            }) | Out-Null
        }
    }

    if (@($instrumentReadinessEvidence | Where-Object { $_.component -in @("instrument_data_export_pending", "instrument_data_contract_pending") }).Count -gt 0) {
        $domainStatuses.Add((New-DomainStatus -Domain "GOTOWOSC_DANYCH_I_TRENINGU_PER_INSTRUMENT" -Gate "NAPRAW_W_CYKLU" -Severity (Get-HighestSeverity -Findings $instrumentReadinessEvidence) -Reason "Przejscie do uczenia per instrument wymaga stalego odzysku danych i kontroli gotowosci." -Evidence $instrumentReadinessEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "GOTOWOSC_DANYCH_I_TRENINGU_PER_INSTRUMENT" -Gate "RAPORTUJ" -Severity (Get-HighestSeverity -Findings $instrumentReadinessEvidence) -Reason "Gotowosc danych i treningu per instrument jest pod kontrola." -Evidence $instrumentReadinessEvidence)) | Out-Null
    }

    $paperLearningEvidence = New-Object System.Collections.Generic.List[object]
    if ($null -ne $learningPaperRuntime) {
        $paperSummary = Get-OptionalValue -Object $learningPaperRuntime -Name "summary" -Default $null
        $overallAction = [string](Get-OptionalValue -Object $paperSummary -Name "overall_action" -Default "")
        $refreshCount = [int](Get-OptionalValue -Object $paperSummary -Name "symbols_to_refresh" -Default 0)
        $collectingCount = [int](Get-OptionalValue -Object $paperSummary -Name "symbols_collecting" -Default 0)
        $runtimeActive = [int](Get-OptionalValue -Object $paperSummary -Name "symbols_runtime_active" -Default 0)
        $paperFreshSymbols = [int](Get-OptionalValue -Object $paperSummary -Name "paper_live_fresh_symbols" -Default 0)
        $runtimeFresh180m = [int](Get-OptionalValue -Object $paperSummary -Name "symbols_runtime_fresh_180m" -Default 0)
        $runtimeStale = [int](Get-OptionalValue -Object $paperSummary -Name "symbols_runtime_stale" -Default 0)
        $shadowGapCount = [int](Get-OptionalValue -Object $paperSummary -Name "symbols_shadow_observation_gap" -Default 0)
        $onnxRecentSymbols180m = [int](Get-OptionalValue -Object $paperSummary -Name "onnx_recent_symbols_180m" -Default 0)
        $onnxRecentRows180m = [int](Get-OptionalValue -Object $paperSummary -Name "onnx_recent_rows_180m" -Default 0)

        if ($paperFreshSymbols -le 0) {
            $paperLearningEvidence.Add([pscustomobject]@{
                severity = "high"
                component = "paper_learning_heartbeat_stale"
                message = "Paper-live nie daje juz swiezych heartbeatow, wiec nie jest zdrowym zrodlem nauki."
                context = @{ paper_live_fresh_symbols = $paperFreshSymbols }
            }) | Out-Null
        }

        if ($overallAction -eq "ODSWIEZ_PAPER_RUNTIME" -and $refreshCount -gt 0) {
            $paperLearningEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "paper_learning_refresh"
                message = "Paper-live powinien zostac odswiezony, bo jest elementem sciezki uczenia."
                context = @{ symbols_to_refresh = $refreshCount; overall_action = $overallAction }
            }) | Out-Null
        }

        if ($collectingCount -le 0) {
            $paperLearningEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "paper_learning_collect"
                message = "Paper-live nie zbiera obecnie zdrowego strumienia obserwacji dla uczenia."
                context = @{ symbols_collecting = $collectingCount }
            }) | Out-Null
        }

        if ($shadowGapCount -gt 0) {
            $paperLearningEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "paper_learning_shadow_gap"
                message = "Czesc symboli ma gotowy runtime ONNX i swiezy heartbeat, ale nie zapisuje nawet cienkiego strumienia shadow obserwacji."
                context = @{
                    symbols_shadow_observation_gap = $shadowGapCount
                    overall_action = $overallAction
                    paper_live_fresh_symbols = $paperFreshSymbols
                }
            }) | Out-Null
        }

        if ($runtimeActive -le 0) {
            $paperLearningEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "paper_learning_runtime"
                message = "Paper-live nie ma jeszcze aktywnego symbolu oddajacego runtime ONNX."
                context = @{ symbols_runtime_active = $runtimeActive }
            }) | Out-Null
        }
        elseif ($onnxRecentRows180m -le 0 -or $onnxRecentSymbols180m -le 0) {
            $paperLearningEvidence.Add([pscustomobject]@{
                severity = "high"
                component = "paper_learning_onnx_stale"
                message = "Male ONNX byly aktywne historycznie, ale w ostatnich 180m nie oddaly swiezego strumienia danych."
                context = @{
                    symbols_runtime_active = $runtimeActive
                    symbols_runtime_fresh_180m = $runtimeFresh180m
                    symbols_runtime_stale = $runtimeStale
                    onnx_recent_symbols_180m = $onnxRecentSymbols180m
                    onnx_recent_rows_180m = $onnxRecentRows180m
                }
            }) | Out-Null
        }
    }

    if ($paperLearningEvidence.Count -gt 0) {
        $hasBlockingPaperLearning = @($paperLearningEvidence | Where-Object { $_.component -in @("paper_learning_heartbeat_stale", "paper_learning_onnx_stale") }).Count -gt 0
        $paperGate = if ($hasBlockingPaperLearning) { "BLOKUJ_LIVE" } else { "NAPRAW_W_CYKLU" }
        $domainStatuses.Add((New-DomainStatus -Domain "PAPER_LIVE_JAKO_ZRODLO_NAUKI" -Gate $paperGate -Severity (Get-HighestSeverity -Findings $paperLearningEvidence) -Reason "Paper-live jest juz czescia samoregulacji i musi pozostawac zdrowym zrodlem swiezych danych." -Evidence $paperLearningEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "PAPER_LIVE_JAKO_ZRODLO_NAUKI" -Gate "RAPORTUJ" -Severity "info" -Reason "Paper-live jest swiezym zrodlem danych i nie pokazuje czerwonych flag dla sciezki uczenia.")) | Out-Null
    }

    $onnxEvidence = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @($hostileFindings | Where-Object { $_.component -in @("onnx_feedback", "onnx_runtime", "onnx_fallbacks", "onnx_quality", "triple_loop_audit") })) {
        $onnxEvidence.Add($finding) | Out-Null
    }
    if ($null -ne $onnxFeedback) {
        $feedbackSummary = Get-OptionalValue -Object $onnxFeedback -Name "summary" -Default $null
        $rows = [int](Get-OptionalValue -Object $feedbackSummary -Name "liczba_obserwacji_onnx" -Default 0)
        $initialized = [int](Get-OptionalValue -Object $feedbackSummary -Name "liczba_symboli_zainicjalizowanych_runtime" -Default 0)
        $withRows = [int](Get-OptionalValue -Object $feedbackSummary -Name "liczba_symboli_z_wierszem_runtime" -Default 0)
        $reason = [string](Get-OptionalValue -Object $onnxFeedback -Name "powod_braku_danych" -Default "")

        if ($rows -le 0 -and $initialized -gt 0 -and $withRows -eq 0) {
            $onnxEvidence.Add([pscustomobject]@{
                severity = "high"
                component = "onnx_feedback"
                message = "Runtime ONNX zyje, ale jeszcze nie zapisal pierwszych wierszy obserwacji."
                context = @{ reason = $reason; initialized = $initialized; with_rows = $withRows }
            }) | Out-Null
        }
    }
    if ($null -ne $onnxCrossAudit) {
        $summary = Get-OptionalValue -Object $onnxCrossAudit -Name "summary" -Default $null
        $fallbacks = [int](Get-OptionalValue -Object $summary -Name "fallback_globalny" -Default 0)
        $needsTraining = [int](Get-OptionalValue -Object $summary -Name "doszkolic_maly_model" -Default 0)

        if ($fallbacks -gt 0) {
            $onnxEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "onnx_fallbacks"
                message = "Czesc symboli nadal jedzie na nauczycielu globalnym."
                context = @{ fallback_globalny = $fallbacks }
            }) | Out-Null
        }
        if ($needsTraining -gt 0) {
            $onnxEvidence.Add([pscustomobject]@{
                severity = "medium"
                component = "onnx_quality"
                message = "Czesc malych modeli nadal wymaga doszkolenia."
                context = @{ doszkolic_maly_model = $needsTraining }
            }) | Out-Null
        }
    }

    if ($onnxEvidence.Count -gt 0) {
        $onlyBootstrapWaiting = ($onnxEvidence.Count -eq 1 -and @($onnxEvidence | Where-Object { $_.component -eq "onnx_feedback" }).Count -eq 1)
        $gate = if ($onlyBootstrapWaiting) { "RAPORTUJ" } else { "NAPRAW_W_CYKLU" }
        $severity = if ($onlyBootstrapWaiting) { "low" } else { (Get-HighestSeverity -Findings $onnxEvidence) }
        $reason = if ($onlyBootstrapWaiting) {
            "Runtime ONNX jest juz zainicjalizowany i czeka na pierwszy kwalifikowany sygnal."
        }
        else {
            "Petla ONNX i sprzezenie zwrotne nadal wymagaja dalszej pracy."
        }
        $domainStatuses.Add((New-DomainStatus -Domain "ONNX_I_SPRZEZENIE_ZWROTNE" -Gate $gate -Severity $severity -Reason $reason -Evidence $onnxEvidence)) | Out-Null
    }
    else {
        $domainStatuses.Add((New-DomainStatus -Domain "ONNX_I_SPRZEZENIE_ZWROTNE" -Gate "RAPORTUJ" -Severity "info" -Reason "Kable ONNX sa aktywne i nie ma swiezych czerwonych flag.")) | Out-Null
    }

    $domainStatusesArray = [object[]]$domainStatuses.ToArray()
    $overallGate = Get-OverallGate -DomainStatuses $domainStatusesArray
    $rolloutGate = "OPEN"
    $liveGate = "OPEN"

    if (@($domainStatusesArray | Where-Object { $_.gate -eq "BLOKUJ_ROLLOUT" }).Count -gt 0) {
        $rolloutGate = "BLOCKED"
    }
    if (@($domainStatusesArray | Where-Object { $_.gate -eq "BLOKUJ_LIVE" }).Count -gt 0) {
        $liveGate = "BLOCKED"
    }

    $topRecurringComponents = @()
    if ($null -ne $discovery) {
        $topRecurringComponents = @($discovery.top_recurring_components | Select-Object -First 8)
    }

    $fullStackVerification = [string](Get-OptionalValue -Object (Get-OptionalValue -Object $fullStack -Name "verification" -Default $null) -Name "verdict" -Default "UNKNOWN")
    $trustVerdict = [string](Get-OptionalValue -Object $trust -Name "verdict" -Default "UNKNOWN")
    $heavyFindingsSummary = if ($null -ne $hostile) { $hostile.summary } else { $null }

    $overallSection = [pscustomobject]@{
        gate = $overallGate
        rollout_gate = $rolloutGate
        live_gate = $liveGate
        heavy_findings = $heavyFindingsSummary
        trust_but_verify_verdict = $trustVerdict
        full_stack_verification = $fullStackVerification
    }

    $evidencePaths = [pscustomobject]@{
        trust_but_verify = $trustPath
        full_stack = $fullStackPath
        learning_stack = $learningPath
        learning_path_hygiene = $learningHygienePath
        learning_wellbeing = $learningWellbeingPath
        vps_spool_wellbeing = $vpsSpoolWellbeingPath
        learning_health_registry = $learningHealthPath
        instrument_data_readiness = $instrumentDataReadinessPath
        instrument_shadow_datasets = $instrumentShadowDatasetsPath
        instrument_training_readiness = $instrumentTrainingReadinessPath
        learning_paper_runtime_plan = $learningPaperRuntimePath
        learning_data_contract_audit = $learningDataContractPath
        onnx_feedback = $onnxFeedbackPath
        onnx_cross_audit = $onnxCrossAuditPath
        hostile_four_loop = $hostilePath
        discovery = $discoveryPath
    }

    $report = @{}
    $refreshResultsArray = [object[]]$refreshResults.ToArray()
    $autoHealResultsArray = [object[]]$autoHealResults.ToArray()
    $report["schema_version"] = "1.0"
    $report["generated_at_local"] = $timestampLocal
    $report["generated_at_utc"] = $timestampUtc
    $report["mode"] = $Mode
    $report["cycle_number"] = $CycleNumber
    $report["cycle_seconds"] = $CycleSeconds
    $report["heavy_sweep_every_cycles"] = $HeavySweepEveryCycles
    $report["heavy_sweep_every_hours"] = [math]::Round((($CycleSeconds * $HeavySweepEveryCycles) / 3600.0), 3)
    $report["heavy_sweep"] = $heavySweep
    $report["apply_safe_auto_heal"] = [bool]$ApplySafeAutoHeal
    $report["refresh_results"] = $refreshResultsArray
    $report["auto_heal_results"] = $autoHealResultsArray
    $report["domain_status"] = $domainStatusesArray
    $report["overall"] = $overallSection
    $report["recurring_risks"] = @($topRecurringComponents)
    $report["evidence_paths"] = $evidencePaths

    $jsonPath = Join-Path $opsRoot "audit_supervisor_latest.json"
    $mdPath = Join-Path $opsRoot "audit_supervisor_latest.md"
    $historyPath = Join-Path $opsRoot "audit_supervisor_history.jsonl"

    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Superwizor Audytu")
    $lines.Add("")
    $lines.Add(("- wygenerowano: {0}" -f $timestampLocal))
    $lines.Add(("- tryb: {0}" -f $Mode))
    $lines.Add(("- cykl: {0}" -f $CycleNumber))
    $lines.Add(("- heavy_sweep: {0}" -f ([string]$heavySweep).ToLowerInvariant()))
    $lines.Add(("- gate_glowny: {0}" -f $overallGate))
    $lines.Add(("- rollout_gate: {0}" -f $rolloutGate))
    $lines.Add(("- live_gate: {0}" -f $liveGate))
    $lines.Add("")
    $lines.Add("## Domeny")
    $lines.Add("")
    foreach ($domain in $domainStatusesArray) {
        $lines.Add(("- {0}: gate={1} | severity={2}" -f $domain.domain, $domain.gate, $domain.severity))
        $lines.Add(("  powod: {0}" -f $domain.reason))
    }
    $lines.Add("")
    $lines.Add("## Ostatnie Ryzyka Powtarzalne")
    $lines.Add("")
    foreach ($item in @($topRecurringComponents)) {
        $lines.Add(("- {0}: {1}x | domena={2} | akcja={3}" -f $item.component, $item.count, $item.domain, $item.action_class))
    }

    ($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
    ($report | ConvertTo-Json -Depth 10 -Compress) | Add-Content -LiteralPath $historyPath -Encoding UTF8

    return $report
}

$cycle = 0
do {
    $cycle++
    $report = Invoke-AuditCycle -CycleNumber $cycle
    $report

    if ($Mode -eq "Loop") {
        Start-Sleep -Seconds $CycleSeconds
    }
}
while ($Mode -eq "Loop")
