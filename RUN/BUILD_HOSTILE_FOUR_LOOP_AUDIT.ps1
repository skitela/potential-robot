param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1")

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$evidenceRoot = Join-Path $ProjectRoot "EVIDENCE"
$commonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
$stateRoot = Join-Path $commonRoot "state"
$logRoot = Join-Path $commonRoot "logs"

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$familyPolicyPath = Join-Path $ProjectRoot "CONFIG\family_policy_registry.json"
$familyReferencePath = Join-Path $ProjectRoot "CONFIG\family_reference_registry.json"
$chartPlanPath = Join-Path $ProjectRoot "DOCS\06_MT5_CHART_ATTACHMENT_PLAN.json"
$researchPlanPath = Join-Path $opsRoot "qdm_intensive_research_plan_latest.json"
$mt5QueuePath = Join-Path $opsRoot "mt5_retest_queue_latest.json"
$technicalReadinessPath = Join-Path $opsRoot "instrument_technical_readiness_latest.json"
$retiredExclusionPath = Join-Path $opsRoot "retired_symbol_exclusion_latest.json"
$fullStackAuditPath = Join-Path $opsRoot "full_stack_audit_latest.json"
$trustButVerifyPath = Join-Path $opsRoot "trust_but_verify_latest.json"
$tripleLoopAuditPath = Join-Path $opsRoot "microbot_triple_loop_audit_latest.json"
$learningStackAuditPath = Join-Path $opsRoot "learning_stack_audit_latest.json"
$onnxCrossAuditPath = Join-Path $opsRoot "onnx_micro_cross_audit_latest.json"
$onnxFeedbackPath = Join-Path $opsRoot "onnx_feedback_loop_latest.json"
$runtimePersistenceAuditPath = Join-Path $evidenceRoot "runtime_persistence_audit_report.json"
$runtimeArtifactAuditPath = Join-Path $evidenceRoot "runtime_artifact_audit_report.json"
$symbolPolicyConsistencyPath = Join-Path $evidenceRoot "symbol_policy_consistency_report.json"
$learningHotPathPath = Join-Path $opsRoot "learning_hot_path_latest.json"

$refreshScripts = @(
    (Join-Path $ProjectRoot "RUN\BUILD_RETIRED_SYMBOL_EXCLUSION_REPORT.ps1"),
    (Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_TECHNICAL_READINESS_REPORT.ps1"),
    (Join-Path $ProjectRoot "RUN\BUILD_QDM_INTENSIVE_RESEARCH_PLAN.ps1"),
    (Join-Path $ProjectRoot "RUN\SYNC_MT5_RETEST_QUEUE_FROM_RESEARCH_PLAN.ps1"),
    (Join-Path $ProjectRoot "RUN\BUILD_ONNX_MICRO_CROSS_AUDIT_REPORT.ps1"),
    (Join-Path $ProjectRoot "RUN\BUILD_LEARNING_STACK_AUDIT.ps1"),
    (Join-Path $ProjectRoot "RUN\BUILD_MICROBOT_TRIPLE_LOOP_AUDIT.ps1"),
    (Join-Path $ProjectRoot "RUN\BUILD_TRUST_BUT_VERIFY_AUDIT.ps1"),
    (Join-Path $ProjectRoot "RUN\BUILD_FULL_STACK_AUDIT.ps1")
)

foreach ($path in @($registryPath, $familyPolicyPath, $familyReferencePath, $chartPlanPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file not found: $path"
    }
}

function Normalize-SymbolAlias {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $normalized = $Value.Trim().ToUpperInvariant()
    if ($normalized.EndsWith(".PRO")) {
        $normalized = $normalized.Substring(0, $normalized.Length - 4)
    }
    return $normalized
}

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-OptionalValue {
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

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Collection,
        [string]$Loop,
        [string]$Severity,
        [string]$Component,
        [string]$Message,
        [object]$Context = $null
    )

    $Collection.Add([pscustomobject]@{
        loop = $Loop
        severity = $Severity
        component = $Component
        message = $Message
        context = $Context
    }) | Out-Null
}

function Invoke-RefreshScript {
    param([string]$ScriptPath)

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return [pscustomobject]@{
            script = $ScriptPath
            ok = $false
            exit_code = -1
            note = "missing"
        }
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath *> $null
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        script = $ScriptPath
        ok = ($exitCode -eq 0)
        exit_code = $exitCode
        note = $(if ($exitCode -eq 0) { "refreshed" } else { "failed" })
    }
}

function New-NormalizedSet {
    return @{}
}

function Convert-CollectionToSet {
    param([object[]]$Items)

    $set = New-NormalizedSet
    foreach ($item in @($Items)) {
        $alias = Normalize-SymbolAlias -Value ([string]$item)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $set[$alias] = $true
        }
    }
    return $set
}

function Get-SetDifference {
    param(
        [hashtable]$Left,
        [hashtable]$Right
    )

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Left.Keys)) {
        if (-not $Right.ContainsKey($item)) {
            $missing.Add($item) | Out-Null
        }
    }
    return @($missing.ToArray() | Sort-Object)
}

function Get-DirNames {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "_*" } |
            ForEach-Object { [string]$_.Name }
    )
}

function Search-TextMatches {
    param(
        [string]$Pattern,
        [string[]]$Paths
    )

    $results = New-Object System.Collections.Generic.List[object]
    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if ($null -ne $rg) {
        $output = & $rg.Source -n --color never $Pattern @Paths 2>$null
        foreach ($line in @($output)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            $match = [regex]::Match($line, '^(?<path>[A-Za-z]:.*?):(?<line>\d+):(?<text>.*)$')
            if (-not $match.Success) {
                continue
            }
            $results.Add([pscustomobject]@{
                path = $match.Groups["path"].Value
                line = $match.Groups["line"].Value
                text = $match.Groups["text"].Value
            }) | Out-Null
        }
        return @($results.ToArray())
    }

    $files = @()
    foreach ($path in @($Paths)) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            $files += Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue
        }
        elseif (Test-Path -LiteralPath $path -PathType Leaf) {
            $files += Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        }
    }

    foreach ($file in @($files)) {
        foreach ($hit in @(Select-String -Path $file.FullName -Pattern $Pattern -SimpleMatch -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $results.Add([pscustomobject]@{
                path = $hit.Path
                line = $hit.LineNumber
                text = $hit.Line.Trim()
            }) | Out-Null
        }
    }

    return @($results.ToArray())
}

function Should-IgnoreRetiredReferencePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $normalized = $Path.Replace('/','\')
    return (
        $normalized -match '\\CONFIG\\strategy_variant_registry\.json$' -or
        $normalized -match '\\SERVER_PROFILE\\HANDOFF\\DOCS\\' -or
        $normalized -match '\\TOOLS\\VALIDATE_PROJECT_LAYOUT\.ps1$' -or
        $normalized -match '\\TOOLS\\EXPORT_MT5_RESEARCH_DATA\.py$' -or
        $normalized -match '\\TOOLS\\qdm_.*_pack\.csv$' -or
        $normalized -match '\\RUN\\strategy_tester\\' -or
        $normalized -match '\\RUN\\TUNING\\' -or
        $normalized -match '\\RUN\\BUILD_RETIRED_SYMBOL_EXCLUSION_REPORT\.ps1$' -or
        $normalized -match '\\RUN\\overnight_tuning_supervisor_state\.json$'
    )
}

$refreshResults = New-Object System.Collections.Generic.List[object]
foreach ($scriptPath in $refreshScripts) {
    $refreshResults.Add((Invoke-RefreshScript -ScriptPath $scriptPath)) | Out-Null
}
$validatorResult = Invoke-RefreshScript -ScriptPath (Join-Path $ProjectRoot "TOOLS\VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1")
$refreshResults.Add($validatorResult) | Out-Null

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$familyPolicy = Read-JsonSafe -Path $familyPolicyPath
$familyReference = Read-JsonSafe -Path $familyReferencePath
$chartPlan = Read-JsonSafe -Path $chartPlanPath
$researchPlan = Read-JsonSafe -Path $researchPlanPath
$mt5Queue = Read-JsonSafe -Path $mt5QueuePath
$technicalReadiness = Read-JsonSafe -Path $technicalReadinessPath
$retiredExclusion = Read-JsonSafe -Path $retiredExclusionPath
$fullStack = Read-JsonSafe -Path $fullStackAuditPath
$trustButVerify = Read-JsonSafe -Path $trustButVerifyPath
$tripleLoop = Read-JsonSafe -Path $tripleLoopAuditPath
$learningStack = Read-JsonSafe -Path $learningStackAuditPath
$onnxCross = Read-JsonSafe -Path $onnxCrossAuditPath
$onnxFeedback = Read-JsonSafe -Path $onnxFeedbackPath
$runtimePersistence = Read-JsonSafe -Path $runtimePersistenceAuditPath
$runtimeArtifact = Read-JsonSafe -Path $runtimeArtifactAuditPath
$symbolPolicyConsistency = Read-JsonSafe -Path $symbolPolicyConsistencyPath
$learningHotPath = Read-JsonSafe -Path $learningHotPathPath

$activeSymbols = @($registry.symbols | ForEach-Object { [string]$_.symbol })
$activeSet = Convert-CollectionToSet -Items $activeSymbols

$familyPolicyRawSymbols = @()
foreach ($family in @($familyPolicy.families)) {
    $familyPolicyRawSymbols += @($family.symbols)
}
$familyPolicySet = Convert-CollectionToSet -Items $familyPolicyRawSymbols

$familyReferenceRawSymbols = @()
foreach ($reference in @($familyReference.references)) {
    $familyReferenceRawSymbols += @($reference.target_symbols)
}
$familyReferenceSet = Convert-CollectionToSet -Items $familyReferenceRawSymbols

$chartPlanSet = Convert-CollectionToSet -Items @($chartPlan | ForEach-Object { [string]$_.symbol })
$researchQueueSet = Convert-CollectionToSet -Items @($researchPlan.tester_queue)
$mt5QueueSet = Convert-CollectionToSet -Items @($mt5Queue.queue)
$technicalSet = Convert-CollectionToSet -Items @(
    @($technicalReadiness.full_qdm_custom_ready) +
    @($technicalReadiness.qdm_export_blocked) +
    @($technicalReadiness.qdm_history_ready) +
    @($technicalReadiness.fallback_only) +
    @($technicalReadiness.compiled_only) +
    @($technicalReadiness.not_ready) |
        ForEach-Object { [string]$_.symbol_alias }
)

$retiredSymbols = @($retiredExclusion.items | ForEach-Object { [string]$_.symbol_alias })
$retiredSet = Convert-CollectionToSet -Items $retiredSymbols

$findings = New-Object System.Collections.Generic.List[object]

# Petla 1: synchronizacja krzyzowa
$loop = "synchronizacja_krzyzowa"

$chartMissing = Get-SetDifference -Left $activeSet -Right $chartPlanSet
$chartExtra = Get-SetDifference -Left $chartPlanSet -Right $activeSet
if (@($chartMissing).Count -gt 0 -or @($chartExtra).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "critical" -Component "plan_wykresow" -Message "Plan wykresow nie zgadza sie z aktywnym rejestrem floty." -Context @{
        missing_in_chart_plan = $chartMissing
        extra_in_chart_plan = $chartExtra
    }
}

$familyPolicyMissing = Get-SetDifference -Left $activeSet -Right $familyPolicySet
$familyPolicyExtra = Get-SetDifference -Left $familyPolicySet -Right $activeSet
if (@($familyPolicyMissing).Count -gt 0 -or @($familyPolicyExtra).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "family_policy_registry" -Message "Rejestr rodzin nie pokrywa sie z aktywna flota." -Context @{
        missing_in_family_policy = $familyPolicyMissing
        extra_in_family_policy = $familyPolicyExtra
    }
}

$familyReferenceMissing = Get-SetDifference -Left $activeSet -Right $familyReferenceSet
$familyReferenceExtra = Get-SetDifference -Left $familyReferenceSet -Right $activeSet
if (@($familyReferenceMissing).Count -gt 0 -or @($familyReferenceExtra).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "family_reference_registry" -Message "Referencje rodzin nie pokrywaja sie z aktywna flota." -Context @{
        missing_in_family_reference = $familyReferenceMissing
        extra_in_family_reference = $familyReferenceExtra
    }
}

$researchMissing = Get-SetDifference -Left $activeSet -Right $researchQueueSet
$researchExtra = Get-SetDifference -Left $researchQueueSet -Right $activeSet
if (@($researchMissing).Count -gt 0 -or @($researchExtra).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "research_plan" -Message "Plan badawczy laptopa nie zgadza sie z aktywna flota." -Context @{
        missing_in_research_plan = $researchMissing
        extra_in_research_plan = $researchExtra
    }
}

$queueMissing = Get-SetDifference -Left $activeSet -Right $mt5QueueSet
$queueExtra = Get-SetDifference -Left $mt5QueueSet -Right $activeSet
if (@($queueMissing).Count -gt 0 -or @($queueExtra).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "mt5_queue" -Message "Kolejka MT5 nie zgadza sie z aktywna flota." -Context @{
        missing_in_mt5_queue = $queueMissing
        extra_in_mt5_queue = $queueExtra
    }
}

$technicalMissing = Get-SetDifference -Left $activeSet -Right $technicalSet
$technicalExtra = Get-SetDifference -Left $technicalSet -Right $activeSet
if (@($technicalMissing).Count -gt 0 -or @($technicalExtra).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "technical_readiness" -Message "Raport gotowosci technicznej nie pokrywa calej aktywnej floty." -Context @{
        missing_in_technical_readiness = $technicalMissing
        extra_in_technical_readiness = $technicalExtra
    }
}

if ($null -ne $retiredExclusion -and -not [bool]$retiredExclusion.all_clean) {
    Add-Finding -Collection $findings -Loop $loop -Severity "critical" -Component "retired_symbols" -Message "Wycofane symbole wciaz przeciekaja do aktywnej warstwy." -Context $retiredExclusion.items
}

foreach ($retiredSymbol in @($retiredSymbols)) {
    $normalizedRetired = Normalize-SymbolAlias -Value $retiredSymbol
    if ($researchQueueSet.ContainsKey($normalizedRetired) -or $mt5QueueSet.ContainsKey($normalizedRetired) -or $chartPlanSet.ContainsKey($normalizedRetired)) {
        Add-Finding -Collection $findings -Loop $loop -Severity "critical" -Component "retired_symbols" -Message ("Wycofany symbol {0} pojawia sie w aktywnej sciezce." -f $retiredSymbol) -Context @{
            in_research_plan = $researchQueueSet.ContainsKey($normalizedRetired)
            in_mt5_queue = $mt5QueueSet.ContainsKey($normalizedRetired)
            in_chart_plan = $chartPlanSet.ContainsKey($normalizedRetired)
        }
    }
}

if ($null -ne $symbolPolicyConsistency -and -not [bool]$symbolPolicyConsistency.ok) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "symbol_policy_consistency" -Message "Walidacja polityk symboli wykryla rozjazdy." -Context @{
        mismatches = @($symbolPolicyConsistency.mismatches | Select-Object -First 12)
    }
}

if ($null -ne $fullStack) {
    $queueConsistent = [bool](Get-OptionalValue -Object (Get-OptionalValue -Object $fullStack -PropertyName "consistency") -PropertyName "mt5_retest_queue_consistent_with_tester" -Default $true)
    if (-not $queueConsistent) {
        Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "full_stack_consistency" -Message "Pelny audyt nadal widzi rozjazd miedzy kolejka MT5 a stanem testera." -Context @{
            mt5_retest_queue_consistent_with_tester = $queueConsistent
        }
    }
}

# Petla 2: higiena i smieci systemowe
$loop = "higiena_i_smieci"

$gitStatusLines = @()
function Invoke-GitStatusSafe {
    param([string]$RepoRoot)

    $command = 'git -c core.safecrlf=false -C "' + $RepoRoot + '" status --short 2>nul'
    return @(
        & cmd.exe /d /c $command |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                ($_ -notmatch 'could not open directory .+\.pytest_cache')
            }
    )
}
try {
    $gitStatusLines = @(Invoke-GitStatusSafe -RepoRoot $ProjectRoot)
}
catch {
    $gitStatusLines = @()
}

if (@($gitStatusLines).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "medium" -Component "git" -Message "Repo nie jest czyste; brud moze maskowac realne zmiany lub generowane artefakty." -Context @{
        dirty_count = $gitStatusLines.Count
        dirty_head = @($gitStatusLines | Select-Object -First 20)
    }
}

$runtimeUnexpectedTotal = 0
if ($null -ne $runtimeArtifact) {
    foreach ($bucket in @($runtimeArtifact.unexpected_by_root)) {
        $runtimeUnexpectedTotal += @($bucket.unexpected).Count
    }
}
if ($runtimeUnexpectedTotal -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "runtime_artifacts" -Message "Audyt runtime widzi nieoczekiwane artefakty." -Context @{
        unexpected_total = $runtimeUnexpectedTotal
        buckets = @($runtimeArtifact.unexpected_by_root)
    }
}

$overThresholdFiles = New-Object System.Collections.Generic.List[object]
if ($null -ne $runtimePersistence) {
    foreach ($bucket in @($runtimePersistence.buckets)) {
        foreach ($file in @($bucket.top_files | Where-Object { [bool](Get-OptionalValue -Object $_ -PropertyName "over_threshold" -Default $false) -eq $true })) {
            $overThresholdFiles.Add([pscustomobject]@{
                category = [string]$bucket.category
                path = [string]$file.path
                size_mb = [double]$file.size_mb
                threshold_mb = [double](Get-OptionalValue -Object $file -PropertyName "threshold_mb" -Default 0.0)
            }) | Out-Null
        }
    }
}
if ($overThresholdFiles.Count -gt 0) {
    $hotPathItems = @((Get-OptionalValue -Object $learningHotPath -PropertyName "items" -Default @()))
    $hotPathControlledMap = @{}
    foreach ($hotItem in $hotPathItems) {
        $path = [string](Get-OptionalValue -Object $hotItem -PropertyName "path" -Default "")
        $action = [string](Get-OptionalValue -Object $hotItem -PropertyName "action" -Default "")
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $hotPathControlledMap[$path.ToLowerInvariant()] = $action
        }
    }

    $controlledHotFiles = @(
        $overThresholdFiles |
            Where-Object {
                $action = $hotPathControlledMap[[string]$_.path.ToLowerInvariant()]
                $action -eq "HOT_ACTIVE_WAIT"
            }
    )
    $allOverThresholdFilesControlled = (
        $overThresholdFiles.Count -gt 0 -and
        $controlledHotFiles.Count -eq $overThresholdFiles.Count
    )

    if ($allOverThresholdFilesControlled) {
        Add-Finding -Collection $findings -Loop $loop -Severity "low" -Component "runtime_logs" -Message "Dzienniki runtime sa gorace, ale cleaner hot-path juz je kontroluje i czeka na bezpieczne okno rotacji." -Context @{
            over_threshold_count = $overThresholdFiles.Count
            controlled_hot_files = @($controlledHotFiles | Sort-Object size_mb -Descending | Select-Object -First 12)
            hot_path_verdict = [string](Get-OptionalValue -Object $learningHotPath -PropertyName "verdict" -Default "")
        }
    }
    else {
        Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "runtime_logs" -Message "Dzienniki runtime sa przegrzane i wymagaja rotacji lub podzialu." -Context @{
            over_threshold_count = $overThresholdFiles.Count
            top_files = @($overThresholdFiles | Sort-Object size_mb -Descending | Select-Object -First 12)
        }
    }
}

$expectedDirSet = New-NormalizedSet
foreach ($symbol in @($activeSymbols + $retiredSymbols)) {
    $alias = Normalize-SymbolAlias -Value $symbol
    if (-not [string]::IsNullOrWhiteSpace($alias)) {
        $expectedDirSet[$alias] = $true
    }
}
foreach ($item in @($registry.symbols)) {
    foreach ($candidate in @([string]$item.code_symbol, [string]$item.broker_symbol)) {
        $alias = Normalize-SymbolAlias -Value $candidate
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $expectedDirSet[$alias] = $true
        }
    }
}

$unexpectedStateDirs = @(
    Get-DirNames -Root $stateRoot |
        Where-Object { -not $expectedDirSet.ContainsKey((Normalize-SymbolAlias -Value $_)) } |
        Sort-Object
)
$unexpectedLogDirs = @(
    Get-DirNames -Root $logRoot |
        Where-Object { -not $expectedDirSet.ContainsKey((Normalize-SymbolAlias -Value $_)) } |
        Sort-Object
)
if (@($unexpectedStateDirs).Count -gt 0 -or @($unexpectedLogDirs).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "medium" -Component "orphan_dirs" -Message "W Common Files sa osierocone katalogi state/logs." -Context @{
        unexpected_state_dirs = $unexpectedStateDirs
        unexpected_log_dirs = $unexpectedLogDirs
    }
}

foreach ($retiredSymbol in @($retiredSymbols)) {
    $retiredStateDir = Join-Path $stateRoot $retiredSymbol
    $retiredLogDir = Join-Path $logRoot $retiredSymbol
    if ((Test-Path -LiteralPath $retiredStateDir) -or (Test-Path -LiteralPath $retiredLogDir)) {
        Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "retired_dirs" -Message ("Wycofany symbol {0} ma nadal katalog state lub logs." -f $retiredSymbol) -Context @{
            state_dir = (Test-Path -LiteralPath $retiredStateDir)
            log_dir = (Test-Path -LiteralPath $retiredLogDir)
        }
    }
}

# Petla 3: archeologia kodu i nazw
$loop = "archeologia_kodu_i_nazw"

$activeSearchRoots = @(
    (Join-Path $ProjectRoot "CONFIG"),
    (Join-Path $ProjectRoot "RUN"),
    (Join-Path $ProjectRoot "TOOLS"),
    (Join-Path $ProjectRoot "MQL5\Include"),
    (Join-Path $ProjectRoot "SERVER_PROFILE\HANDOFF"),
    $chartPlanPath
)

$retiredPatternParts = @(
    $retiredSymbols |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { [regex]::Escape($_) }
)

$retiredHits = @()
if ($retiredPatternParts.Count -gt 0) {
    $retiredHits = Search-TextMatches -Pattern ($retiredPatternParts -join '|') -Paths $activeSearchRoots
    $retiredHits = @($retiredHits | Where-Object {
        $_.path -ne $PSCommandPath -and -not (Should-IgnoreRetiredReferencePath -Path $_.path)
    })
}

if (@($retiredHits).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "retired_symbol_references" -Message "Aktywna orkiestracja nadal zawiera odniesienia do wycofanych symboli." -Context @{
        hit_count = $retiredHits.Count
        hits = @($retiredHits | Select-Object -First 20)
    }
}

$familyBrokerNamed = @(
    $familyPolicyRawSymbols + $familyReferenceRawSymbols |
        Where-Object { [string]$_ -like "*.pro" } |
        Sort-Object -Unique
)
if (@($familyBrokerNamed).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "medium" -Component "family_symbol_naming" -Message "Rejestry rodzin nadal mieszaja alias kanoniczny z broker_symbol." -Context @{
        broker_style_symbols = $familyBrokerNamed
    }
}

$criticalPingFiles = @(
    (Join-Path $ProjectRoot "MQL5\Include\Core\MbExecutionPrecheck.mqh"),
    (Join-Path $ProjectRoot "MQL5\Include\Core\MbMarketGuards.mqh"),
    (Join-Path $ProjectRoot "MQL5\Include\Core\MbTuningEpistemology.mqh"),
    (Join-Path $ProjectRoot "MQL5\Include\Core\MbExecutionFeedback.mqh"),
    (Join-Path $ProjectRoot "MQL5\Include\Core\MbTuningLocalAgent.mqh")
)
$criticalPingHits = Search-TextMatches -Pattern "terminal_ping" -Paths $criticalPingFiles
if (@($criticalPingHits).Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "terminal_ping_in_core" -Message "W rdzeniu decyzyjnym nadal sa odniesienia do terminal_ping." -Context @{
        hit_count = $criticalPingHits.Count
        hits = @($criticalPingHits | Select-Object -First 20)
    }
}

$expertFileIssues = New-Object System.Collections.Generic.List[object]
foreach ($item in @($registry.symbols)) {
    $expertPath = Join-Path $ProjectRoot ("MQL5\Experts\MicroBots\{0}.mq5" -f ([string]$item.expert))
    $presetPath = Join-Path $ProjectRoot ("MQL5\Presets\{0}" -f ([string]$item.preset))
    if (-not (Test-Path -LiteralPath $expertPath)) {
        $expertFileIssues.Add([pscustomobject]@{
            symbol = [string]$item.symbol
            issue = "missing_expert_file"
            path = $expertPath
        }) | Out-Null
    }
    if (-not (Test-Path -LiteralPath $presetPath)) {
        $expertFileIssues.Add([pscustomobject]@{
            symbol = [string]$item.symbol
            issue = "missing_preset_file"
            path = $presetPath
        }) | Out-Null
    }
}
if ($expertFileIssues.Count -gt 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "critical" -Component "registry_files" -Message "Rejestr aktywnych botow wskazuje na brakujace pliki experta lub preset." -Context @{
        issues = $expertFileIssues.ToArray()
    }
}

if ($null -ne $tripleLoop) {
    $criticalCount = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $tripleLoop -PropertyName "summary" -Default $null) -PropertyName "critical_count" -Default 0)
    $warningCount = [int](Get-OptionalValue -Object (Get-OptionalValue -Object $tripleLoop -PropertyName "summary" -Default $null) -PropertyName "warning_count" -Default 0)
    if ($criticalCount -gt 0) {
        Add-Finding -Collection $findings -Loop $loop -Severity "critical" -Component "triple_loop_audit" -Message "Potrojny audyt mikrobotow nadal widzi krytyczne problemy." -Context @{
            critical_count = $criticalCount
            warning_count = $warningCount
        }
    }
    elseif ($warningCount -gt 0) {
        Add-Finding -Collection $findings -Loop $loop -Severity "medium" -Component "triple_loop_audit" -Message "Potrojny audyt mikrobotow nadal widzi ostrzezenia." -Context @{
            warning_count = $warningCount
        }
    }
}

# Petla 4: uczenie, ONNX i sprzezenie zwrotne
$loop = "uczenie_onnx_i_runtime"

$onnxSummary = Get-OptionalValue -Object $onnxFeedback -PropertyName "summary" -Default $null
$onnxObservationCount = [int](Get-OptionalValue -Object $onnxSummary -PropertyName "liczba_obserwacji_onnx" -Default 0)
$onnxPaperCount = [int](Get-OptionalValue -Object $onnxSummary -PropertyName "liczba_obserwacji_paper" -Default 0)
$onnxLiveCount = [int](Get-OptionalValue -Object $onnxSummary -PropertyName "liczba_obserwacji_live" -Default 0)
if ($onnxObservationCount -le 0) {
    Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "onnx_feedback" -Message "Kabel sprzezenia zwrotnego ONNX jest gotowy, ale nadal nie ma zadnych obserwacji runtime." -Context @{
        observations_total = $onnxObservationCount
        observations_paper = $onnxPaperCount
        observations_live = $onnxLiveCount
        reason = (Get-OptionalValue -Object $onnxFeedback -PropertyName "powod_braku_danych" -Default "")
    }
}

if ($null -ne $onnxCross) {
    $crossSummary = Get-OptionalValue -Object $onnxCross -PropertyName "summary" -Default $null
    $fallbackCount = [int](Get-OptionalValue -Object $crossSummary -PropertyName "fallback_globalny" -Default 0)
    $weakCount = [int](Get-OptionalValue -Object $crossSummary -PropertyName "doszkolic_maly_model" -Default 0)
    $noRuntimeCount = [int](Get-OptionalValue -Object $crossSummary -PropertyName "brak_obserwacji_runtime" -Default 0)

    if ($fallbackCount -gt 0) {
        Add-Finding -Collection $findings -Loop $loop -Severity "medium" -Component "onnx_fallbacks" -Message "Czesc floty nadal jedzie na nauczycielu globalnym zamiast na malym ONNX." -Context @{
            fallback_globalny = $fallbackCount
        }
    }

    if ($weakCount -gt 0) {
        Add-Finding -Collection $findings -Loop $loop -Severity "medium" -Component "onnx_quality" -Message "Czesc malych modeli ONNX nadal wymaga doszkolenia." -Context @{
            doszkolic_maly_model = $weakCount
        }
    }

    if ($noRuntimeCount -gt 0) {
        Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "onnx_runtime" -Message "Male ONNX sa podpiete, ale brakuje realnych obserwacji runtime." -Context @{
            brak_obserwacji_runtime = $noRuntimeCount
        }
    }
}

if ($null -ne $learningStack) {
    $learningVerdict = [string](Get-OptionalValue -Object (Get-OptionalValue -Object $learningStack -PropertyName "learning" -Default $null) -PropertyName "verdict" -Default "")
    $qdmCoverageRatio = [double](Get-OptionalValue -Object (Get-OptionalValue -Object $learningStack -PropertyName "learning" -Default $null) -PropertyName "qdm_coverage_ratio" -Default 0.0)

    if ($learningVerdict -eq "QDM_LOW_COVERAGE_ACTIVE" -or $qdmCoverageRatio -lt 0.05) {
        Add-Finding -Collection $findings -Loop $loop -Severity "medium" -Component "learning_stack" -Message "Uczenie juz korzysta z QDM, ale pokrycie jest nadal niskie." -Context @{
            learning_verdict = $learningVerdict
            qdm_coverage_ratio = $qdmCoverageRatio
        }
    }
}

if ($null -ne $fullStack) {
    $labHealth = Get-OptionalValue -Object $fullStack -PropertyName "lab_health" -Default $null
    $wrappers = Get-OptionalValue -Object $labHealth -PropertyName "wrappers" -Default $null
    $mlRunning = [bool](Get-OptionalValue -Object $wrappers -PropertyName "ml" -Default $false)
    $supervisorRunning = [bool](Get-OptionalValue -Object $wrappers -PropertyName "supervisor" -Default $false)
    if (-not $mlRunning -or -not $supervisorRunning) {
        Add-Finding -Collection $findings -Loop $loop -Severity "high" -Component "learning_runtime" -Message "Warstwa uczenia laptopa nie ma kompletu aktywnych wrapperow." -Context @{
            ml = $mlRunning
            supervisor = $supervisorRunning
        }
    }
}

$severityOrder = @{
    critical = 0
    high = 1
    medium = 2
    low = 3
}

$orderedFindings = @(
    $findings |
        Sort-Object @{
            Expression = { $severityOrder[[string]$_.severity] }
        }, loop, component, message
)

$summary = [ordered]@{
    total_findings = @($orderedFindings).Count
    critical = @($orderedFindings | Where-Object { $_.severity -eq "critical" }).Count
    high = @($orderedFindings | Where-Object { $_.severity -eq "high" }).Count
    medium = @($orderedFindings | Where-Object { $_.severity -eq "medium" }).Count
    low = @($orderedFindings | Where-Object { $_.severity -eq "low" }).Count
    loops = [ordered]@{
        synchronizacja_krzyzowa = @($orderedFindings | Where-Object { $_.loop -eq "synchronizacja_krzyzowa" }).Count
        higiena_i_smieci = @($orderedFindings | Where-Object { $_.loop -eq "higiena_i_smieci" }).Count
        archeologia_kodu_i_nazw = @($orderedFindings | Where-Object { $_.loop -eq "archeologia_kodu_i_nazw" }).Count
        uczenie_onnx_i_runtime = @($orderedFindings | Where-Object { $_.loop -eq "uczenie_onnx_i_runtime" }).Count
    }
}

$verdict = "OK"
if ($summary.critical -gt 0) {
    $verdict = "BLOCKERS_FOUND"
}
elseif ($summary.high -gt 0) {
    $verdict = "CLEANUP_REQUIRED"
}
elseif ($summary.medium -gt 0) {
    $verdict = "REVIEW_REQUIRED"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    audit_prompt_path = (Join-Path $ProjectRoot "DOCS\165_HOSTILE_FOUR_LOOP_AUDIT_PROMPT_V1.md")
    verdict = $verdict
    summary = $summary
    refresh_results = @($refreshResults.ToArray())
    findings = $orderedFindings
}

$jsonLatest = Join-Path $EvidenceDir "hostile_four_loop_audit_latest.json"
$mdLatest = Join-Path $EvidenceDir "hostile_four_loop_audit_latest.md"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonStamped = Join-Path $EvidenceDir ("hostile_four_loop_audit_{0}.json" -f $timestamp)
$mdStamped = Join-Path $EvidenceDir ("hostile_four_loop_audit_{0}.md" -f $timestamp)

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Hostile Four Loop Audit")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- total_findings: {0}" -f $summary.total_findings))
$lines.Add(("- critical: {0}" -f $summary.critical))
$lines.Add(("- high: {0}" -f $summary.high))
$lines.Add(("- medium: {0}" -f $summary.medium))
$lines.Add("")
$lines.Add("## Loops")
$lines.Add("")
$lines.Add(("- synchronizacja_krzyzowa: {0}" -f $summary.loops.synchronizacja_krzyzowa))
$lines.Add(("- higiena_i_smieci: {0}" -f $summary.loops.higiena_i_smieci))
$lines.Add(("- archeologia_kodu_i_nazw: {0}" -f $summary.loops.archeologia_kodu_i_nazw))
$lines.Add(("- uczenie_onnx_i_runtime: {0}" -f $summary.loops.uczenie_onnx_i_runtime))
$lines.Add("")
$lines.Add("## Top Findings")
$lines.Add("")
foreach ($item in @($orderedFindings | Select-Object -First 20)) {
    $lines.Add(("- [{0}] {1} / {2}: {3}" -f $item.severity, $item.loop, $item.component, $item.message))
}
$lines.Add("")
$lines.Add("## Refresh Results")
$lines.Add("")
foreach ($item in $refreshResults.ToArray()) {
    $lines.Add(("- {0}: ok={1}, exit_code={2}, note={3}" -f $item.script, $item.ok, $item.exit_code, $item.note))
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdStamped -Encoding UTF8

$report
