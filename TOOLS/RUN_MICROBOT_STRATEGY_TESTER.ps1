param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [switch]$PortableTerminal,
    [Parameter(Mandatory = $true)]
    [string]$SymbolAlias,
    [string]$Symbol = "",
    [string]$ExpertName = "",
    [string]$ExpertPath = "",
    [string]$SandboxTag = "",
    [string]$Period = "M5",
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$Model = 4,
    [ValidateSet(0,1,2,3)]
    [int]$Optimization = 0,
    [ValidateSet(0,1,2,3,4,5,6,7)]
    [int]$OptimizationCriterion = 6,
    [string]$ExpertParameters = "",
    [double]$Deposit = 10000.0,
    [int]$Leverage = 100,
    [int]$TimeoutSec = 1800,
    [string]$WorkerName = "",
    [string]$EvidenceSubdir = "",
    [switch]$SkipKnowledgeExport,
    [switch]$SkipResearchRefresh,
    [string]$ResearchOutputRoot = "C:\TRADING_DATA\RESEARCH",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$ResearchPerfProfile = "Light",
    [switch]$RestoreMicrobotsProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Stop-MatchingTerminalProcesses {
    param([string]$ExecutablePath)

    $normalizedTarget = [System.IO.Path]::GetFullPath($ExecutablePath).ToLowerInvariant()
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "terminal64.exe" -and
            -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
            ([System.IO.Path]::GetFullPath($_.ExecutablePath).ToLowerInvariant() -eq $normalizedTarget)
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Get-MatchingTerminalProcessId {
    param(
        [string]$ExecutablePath,
        [string]$ConfigPath
    )

    $normalizedTarget = [System.IO.Path]::GetFullPath($ExecutablePath).ToLowerInvariant()
    $normalizedConfig = [System.IO.Path]::GetFullPath($ConfigPath).ToLowerInvariant()

    $match = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "terminal64.exe" -and
            -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
            ([System.IO.Path]::GetFullPath($_.ExecutablePath).ToLowerInvariant() -eq $normalizedTarget) -and
            -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
            $_.CommandLine.ToLowerInvariant().Contains($normalizedConfig)
        } |
        Sort-Object CreationDate -Descending |
        Select-Object -First 1

    if ($null -eq $match) {
        return $null
    }

    return [int]$match.ProcessId
}

function Convert-ToSandboxToken {
    param([string]$Value)
    $chars = $Value.ToCharArray() | ForEach-Object {
        if (($_ -ge 'A' -and $_ -le 'Z') -or ($_ -ge 'a' -and $_ -le 'z') -or ($_ -ge '0' -and $_ -le '9') -or $_ -eq '_' -or $_ -eq '-') {
            [string]$_
        } else {
            "_"
        }
    }
    $out = -join $chars
    if ([string]::IsNullOrWhiteSpace($out)) {
        return "DEFAULT"
    }
    return $out
}

function Convert-ToMtCanonicalSymbol {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $out = $Value.Trim().ToUpperInvariant()
    $dotPos = $out.IndexOf('.')
    if ($dotPos -gt 0) {
        $out = $out.Substring(0, $dotPos)
    }
    return $out
}

function Resolve-EvidenceDir {
    param(
        [string]$ProjectRootPath,
        [string]$Subdir
    )
    $base = Join-Path $ProjectRootPath "EVIDENCE\STRATEGY_TESTER"
    if ([string]::IsNullOrWhiteSpace($Subdir)) {
        return $base
    }
    return (Join-Path $base $Subdir)
}

function Resolve-ExpertParametersPath {
    param(
        [string]$ProjectRootPath,
        [string]$ExpertName,
        [string]$ExplicitPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if ([System.IO.Path]::IsPathRooted($ExplicitPath)) {
            if (Test-Path -LiteralPath $ExplicitPath) {
                return (Resolve-Path -LiteralPath $ExplicitPath).Path
            }
            throw "ExpertParameters file not found: $ExplicitPath"
        }

        $candidatePaths = @(
            (Join-Path $ProjectRootPath $ExplicitPath),
            (Join-Path $ProjectRootPath ("MQL5\\Presets\\{0}" -f $ExplicitPath))
        )

        foreach ($candidate in $candidatePaths) {
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }

        throw "ExpertParameters file not found relative to project: $ExplicitPath"
    }

    $defaultPreset = Join-Path $ProjectRootPath ("MQL5\\Presets\\{0}_Live.set" -f $ExpertName)
    if (Test-Path -LiteralPath $defaultPreset) {
        return (Resolve-Path -LiteralPath $defaultPreset).Path
    }

    return ""
}

function Set-OptimizationRangesInPreset {
    param([string]$PresetPath)

    if ([string]::IsNullOrWhiteSpace($PresetPath)) {
        return
    }

    $lines = @()
    if (Test-Path -LiteralPath $PresetPath) {
        $lines = @(Get-Content -LiteralPath $PresetPath -Encoding Default -ErrorAction SilentlyContinue)
    }

    $desired = [ordered]@{
        "InpTesterSafetyMarginScale" = "InpTesterSafetyMarginScale=1.00||0.50||0.25||2.00||Y"
        "InpTesterEdgeRequirementScale" = "InpTesterEdgeRequirementScale=1.00||0.75||0.25||2.25||Y"
        "InpTesterTimeStopScale" = "InpTesterTimeStopScale=1.00||0.75||0.25||2.25||Y"
    }

    foreach ($key in $desired.Keys) {
        $replacement = [string]$desired[$key]
        $matched = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -like "$key=*") {
                $lines[$i] = $replacement
                $matched = $true
                break
            }
        }

        if (-not $matched) {
            $lines += $replacement
        }
    }

    Set-Content -LiteralPath $PresetPath -Value $lines -Encoding Default
}

function Set-PresetKeyValue {
    param(
        [string]$PresetPath,
        [string]$Key,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($PresetPath) -or [string]::IsNullOrWhiteSpace($Key)) {
        return
    }

    $lines = @()
    if (Test-Path -LiteralPath $PresetPath) {
        $lines = @(Get-Content -LiteralPath $PresetPath -Encoding Default -ErrorAction SilentlyContinue)
    }

    $replacement = "{0}={1}" -f $Key, $Value
    $matched = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -like "$Key=*") {
            $lines[$i] = $replacement
            $matched = $true
            break
        }
    }

    if (-not $matched) {
        $lines += $replacement
    }

    Set-Content -LiteralPath $PresetPath -Value $lines -Encoding Default
}

function Resolve-TesterSymbol {
    param(
        [object]$RegistryItem,
        [string]$ExplicitSymbol
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitSymbol)) {
        return $ExplicitSymbol
    }
    return (Get-RegistryBrokerSymbol -RegistryItem $RegistryItem)
}

function Get-RegistryEntry {
    param(
        [string]$RegistryPath,
        [string]$Alias
    )
    $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return (Find-RegistryEntryByAlias -Registry $registry -Alias $Alias)
}

function Get-KeyValueCsvMap {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $map[$parts[0]] = $parts[1]
    }
    return $map
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
    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        return $Object.$PropertyName
    }
    return $Default
}

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

function Get-LatestWriteTimeUtc {
    param([string[]]$Paths)

    $latest = [datetime]::MinValue
    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $writeTime = (Get-Item -LiteralPath $path).LastWriteTimeUtc
        if ($writeTime -gt $latest) {
            $latest = $writeTime
        }
    }
    return $latest
}

function Import-TabCsvWithRetry {
    param(
        [string]$Path,
        [int]$MaxAttempts = 20,
        [int]$DelayMs = 500
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return @(Import-Csv -LiteralPath $Path -Delimiter "`t")
        } catch {
            $message = $_.Exception.Message
            $isLast = ($attempt -ge $MaxAttempts)
            $isLockError = (
                $message -match 'being used by another process' -or
                $message -match 'used by another process' -or
                $message -match 'używany przez inny proces' -or
                $message -match 'cannot access the file'
            )
            if (-not $isLockError -or $isLast) {
                throw
            }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    return @()
}

function Wait-ProcessTerminationGracefully {
    param(
        [int[]]$ProcessIds,
        [int]$TimeoutSeconds = 30
    )

    $ids = @($ProcessIds | Where-Object { $null -ne $_ } | Select-Object -Unique)
    if ($ids.Count -le 0) {
        return
    }

    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
    do {
        $alive = @(
            $ids |
                Where-Object {
                    $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue)
                }
        )
        if ($alive.Count -le 0) {
            return
        }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
}

function Get-TesterRunOutcome {
    param(
        [string[]]$LogPaths,
        [string]$ExpertName,
        [string]$Symbol,
        [string]$Period,
        [string]$FromDate,
        [string]$ToDate
    )
    $outcome = [ordered]@{
        final_balance = $null
        test_duration = ""
        result_label  = ""
    }

    $escapedExpert = [regex]::Escape(("Experts\MicroBots\{0}.ex5" -f $ExpertName))
    $escapedSymbol = [regex]::Escape($Symbol)
    $escapedPeriod = [regex]::Escape($Period)
    $escapedFrom = [regex]::Escape(($FromDate + " 00:00"))
    $escapedTo = [regex]::Escape(($ToDate + " 00:00"))
    $startPattern = ("{0},{1}: testing of {2} from {3} to {4} started" -f $escapedSymbol, $escapedPeriod, $escapedExpert, $escapedFrom, $escapedTo)

    foreach ($logPath in $LogPaths) {
        if (-not (Test-Path -LiteralPath $logPath)) {
            continue
        }
        $lines = @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue)
        if ($lines.Count -eq 0) {
            continue
        }

        $startIndex = -1
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match $startPattern) {
                $startIndex = $i
                break
            }
        }
        if ($startIndex -lt 0) {
            continue
        }

        for ($i = $startIndex; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($null -eq $outcome.final_balance -and $line -match 'final balance ([0-9\.\-]+)') {
                $outcome.final_balance = [double]$matches[1]
            }
            if ([string]::IsNullOrWhiteSpace($outcome.result_label) -and $line -match 'Test passed in ([0-9:\.]+)') {
                $outcome.test_duration = $matches[1]
                $outcome.result_label = "successfully_finished"
            }
        }

        if ($null -ne $outcome.final_balance -or -not [string]::IsNullOrWhiteSpace($outcome.result_label)) {
            break
        }
    }

    return $outcome
}

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$entry = Get-RegistryEntry -RegistryPath $registryPath -Alias $SymbolAlias
if (-not $entry) {
    throw "SymbolAlias not found in registry: $SymbolAlias"
}

function Get-OptimizationReportRowCount {
    param([string[]]$ReportPaths)

    foreach ($reportPath in @($ReportPaths)) {
        if ([string]::IsNullOrWhiteSpace($reportPath) -or -not (Test-Path -LiteralPath $reportPath)) {
            continue
        }

        try {
            $content = Get-Content -LiteralPath $reportPath -Raw -ErrorAction Stop
            $rowMatches = [regex]::Matches($content, "<Row>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
            if ($rowMatches -gt 0) {
                return [Math]::Max(0, ($rowMatches - 1))
            }
        }
        catch {
        }
    }

    return 0
}

function Convert-ToDoubleOrNull {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $raw = [string]$Value
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    try {
        return [double]($raw -replace ',', '.')
    }
    catch {
        return $null
    }
}

function Initialize-StrategyTesterSandboxContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SandboxRoot,
        [Parameter(Mandatory = $true)]
        [string]$StorageAlias,
        [Parameter(Mandatory = $true)]
        [string]$RuntimeSymbol
    )

    $paths = @(
        $SandboxRoot,
        (Join-Path $SandboxRoot "state"),
        (Join-Path $SandboxRoot "state\\_global"),
        (Join-Path $SandboxRoot "state\\_domains"),
        (Join-Path $SandboxRoot "logs"),
        (Join-Path $SandboxRoot "run"),
        (Join-Path $SandboxRoot "key"),
        (Join-Path $SandboxRoot ("state\\{0}" -f $StorageAlias)),
        (Join-Path $SandboxRoot ("logs\\{0}" -f $StorageAlias)),
        (Join-Path $SandboxRoot ("run\\{0}" -f $StorageAlias)),
        (Join-Path $SandboxRoot ("key\\{0}" -f $StorageAlias))
    )

    foreach ($path in $paths) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    $commonFilesRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
    $sourceRoot = Join-Path $commonFilesRoot "MAKRO_I_MIKRO_BOT"
    if (-not (Test-Path -LiteralPath $sourceRoot)) {
        return
    }

    $runtimeAlias = Convert-ToMtCanonicalSymbol $RuntimeSymbol
    $storageAliasCanonical = Convert-ToMtCanonicalSymbol $StorageAlias

    $keyArtifactNames = @(
        "paper_gate_acceptor_runtime_latest.onnx",
        "paper_gate_acceptor_runtime_manifest_latest.json",
        "paper_gate_acceptor_runtime_metrics_latest.json",
        "paper_gate_acceptor_runtime_contract_latest.csv"
    )

    $sourceGlobalKeyDir = Join-Path $sourceRoot "key\_GLOBAL"
    $targetGlobalKeyDir = Join-Path $SandboxRoot "key\_GLOBAL"
    if (Test-Path -LiteralPath $sourceGlobalKeyDir) {
        New-Item -ItemType Directory -Force -Path $targetGlobalKeyDir | Out-Null
        foreach ($artifactName in $keyArtifactNames) {
            $sourceArtifact = Join-Path $sourceGlobalKeyDir $artifactName
            if (-not (Test-Path -LiteralPath $sourceArtifact)) {
                continue
            }
            Copy-Item -LiteralPath $sourceArtifact -Destination (Join-Path $targetGlobalKeyDir $artifactName) -Force
        }
    }

    $symbolSourceCandidates = @()
    foreach ($candidate in @($runtimeAlias, $storageAliasCanonical)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if ($candidate -notin $symbolSourceCandidates) {
            $symbolSourceCandidates += $candidate
        }
    }

    $symbolTargetAliases = @()
    foreach ($candidate in @($runtimeAlias, $storageAliasCanonical)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if ($candidate -notin $symbolTargetAliases) {
            $symbolTargetAliases += $candidate
        }
    }

    $resolvedSymbolSourceDir = $null
    foreach ($candidate in $symbolSourceCandidates) {
        $candidateDir = Join-Path $sourceRoot ("key\{0}" -f $candidate)
        if (Test-Path -LiteralPath $candidateDir) {
            $resolvedSymbolSourceDir = $candidateDir
            break
        }
    }

    if ($null -ne $resolvedSymbolSourceDir) {
        foreach ($targetAlias in $symbolTargetAliases) {
            $targetKeyDir = Join-Path $SandboxRoot ("key\{0}" -f $targetAlias)
            New-Item -ItemType Directory -Force -Path $targetKeyDir | Out-Null
            foreach ($artifactName in $keyArtifactNames) {
                $sourceArtifact = Join-Path $resolvedSymbolSourceDir $artifactName
                if (-not (Test-Path -LiteralPath $sourceArtifact)) {
                    continue
                }
                Copy-Item -LiteralPath $sourceArtifact -Destination (Join-Path $targetKeyDir $artifactName) -Force
            }
        }
    }

    $sourceStateCandidates = @()
    foreach ($candidate in @($runtimeAlias, $storageAliasCanonical)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if ($candidate -notin $sourceStateCandidates) {
            $sourceStateCandidates += $candidate
        }
    }

    $studentGateContractSource = $null
    foreach ($candidate in $sourceStateCandidates) {
        $candidatePath = Join-Path $sourceRoot ("state\{0}\student_gate_contract.csv" -f $candidate)
        if (Test-Path -LiteralPath $candidatePath) {
            $studentGateContractSource = $candidatePath
            break
        }
    }

    if ($null -ne $studentGateContractSource) {
        foreach ($targetAlias in $symbolTargetAliases) {
            $targetStateDir = Join-Path $SandboxRoot ("state\{0}" -f $targetAlias)
            New-Item -ItemType Directory -Force -Path $targetStateDir | Out-Null
            Copy-Item -LiteralPath $studentGateContractSource -Destination (Join-Path $targetStateDir "student_gate_contract.csv") -Force
        }
    }
}

$canonicalAlias = Get-RegistryCanonicalSymbol -RegistryItem $entry
$entryCodeSymbol = if ($entry.PSObject.Properties.Name -contains 'code_symbol') { [string]$entry.code_symbol } else { "" }
$resolvedAlias = Convert-ToSandboxToken $(if (-not [string]::IsNullOrWhiteSpace($entryCodeSymbol)) { $entryCodeSymbol } else { Get-RegistryCanonicalSymbol -RegistryItem $entry })
$storageAlias = Convert-ToSandboxToken (Get-RegistryCanonicalSymbol -RegistryItem $entry)
if ([string]::IsNullOrWhiteSpace($storageAlias)) {
    $storageAlias = $resolvedAlias
}
$sandboxSymbolAlias = if ($Symbol -like "*_QDM_*") {
    Convert-ToMtCanonicalSymbol $Symbol
} else {
    $storageAlias
}
$workerToken = Convert-ToSandboxToken $WorkerName
if ([string]::IsNullOrWhiteSpace($SandboxTag)) {
    if (-not [string]::IsNullOrWhiteSpace($workerToken)) {
        $SandboxTag = "${workerToken}_AGENT"
    }
    else {
        $SandboxTag = "${resolvedAlias}_AGENT"
    }
}
$sanitizedTag = Convert-ToSandboxToken $SandboxTag

$Symbol = Resolve-TesterSymbol -RegistryItem $entry -ExplicitSymbol $Symbol
if ([string]::IsNullOrWhiteSpace($ExpertName)) {
    $ExpertName = [string]$entry.expert
}
if ([string]::IsNullOrWhiteSpace($ExpertPath)) {
    $ExpertPath = "MicroBots\$ExpertName.ex5"
}
if ($ExpertPath -match '^(?i)Experts\\') {
    $ExpertPath = $ExpertPath.Substring(8)
}

$runId = ("{0}_strategy_tester_{1}" -f $resolvedAlias.ToLowerInvariant(), (Get-Date -Format "yyyyMMdd_HHmmss"))
$runDir = Join-Path $ProjectRoot "RUN\strategy_tester"
if ([string]::IsNullOrWhiteSpace($EvidenceSubdir) -and -not [string]::IsNullOrWhiteSpace($workerToken)) {
    $EvidenceSubdir = $workerToken.ToLowerInvariant()
}

$requestedModel = $Model
$modelNormalizedForQdmCustomSymbol = $false
if (($Symbol -like "*_QDM_*") -and $Model -eq 4) {
    # QDM custom-symbol pilot currently runs reliably on OHLC minute modeling.
    # Leaving the default model 4 here causes false "no history data" failures
    # before the expert even gets a chance to initialize.
    $Model = 1
    $modelNormalizedForQdmCustomSymbol = $true
}

$evidenceDir = Resolve-EvidenceDir -ProjectRootPath $ProjectRoot -Subdir $EvidenceSubdir
$mt5Root = Split-Path -Parent $Mt5Exe
$mt5ReportsDir = if ($PortableTerminal) { Join-Path $TerminalDataDir "reports" } else { Join-Path $mt5Root "reports" }
$testerAgentsRoot = if ($PortableTerminal) {
    Join-Path $TerminalDataDir "Tester"
} else {
    $terminalHash = Split-Path $TerminalDataDir -Leaf
    $metaQuotesRoot = Split-Path (Split-Path $TerminalDataDir -Parent) -Parent
    Join-Path $metaQuotesRoot ("Tester\" + $terminalHash)
}
$configPath = Join-Path $runDir ($runId + ".ini")
$testerLogDir = Join-Path $TerminalDataDir "Tester\logs"
$terminalLogDir = Join-Path $TerminalDataDir "logs"
$testerProfilesDir = Join-Path $TerminalDataDir "MQL5\Profiles\Tester"
$reportBaseRel = "reports\" + $runId
$sandboxName = "MAKRO_I_MIKRO_BOT_TESTER_${sandboxSymbolAlias}_${sanitizedTag}"
$sandboxRoot = Join-Path (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files") $sandboxName
New-Item -ItemType Directory -Force -Path $testerProfilesDir | Out-Null

$expertParametersSourcePath = Resolve-ExpertParametersPath -ProjectRootPath $ProjectRoot -ExpertName $ExpertName -ExplicitPath $ExpertParameters
$expertParametersTargetName = ""
if (-not [string]::IsNullOrWhiteSpace($expertParametersSourcePath)) {
    $expertParametersTargetName = "{0}_{1}.set" -f $runId, [System.IO.Path]::GetFileNameWithoutExtension($expertParametersSourcePath)
    $expertParametersTargetPath = Join-Path $testerProfilesDir $expertParametersTargetName
    Copy-Item -LiteralPath $expertParametersSourcePath -Destination $expertParametersTargetPath -Force
    Set-PresetKeyValue -PresetPath $expertParametersTargetPath -Key "InpEnableStrategyTesterSandbox" -Value "true"
    Set-PresetKeyValue -PresetPath $expertParametersTargetPath -Key "InpStrategyTesterSandboxTag" -Value $sanitizedTag
    if ($Symbol -like "*_QDM_*") {
        # QDM custom-symbol smoke is an integration check, not a fidelity benchmark.
        # A 5-second timer across multi-day M1 tests creates tens of thousands of cycles
        # and needlessly pushes the tester into timeout before the run can close.
        Set-PresetKeyValue -PresetPath $expertParametersTargetPath -Key "InpTimerSec" -Value "60"
    }
    if ($Optimization -ne 0) {
        Set-OptimizationRangesInPreset -PresetPath $expertParametersTargetPath
    }
}

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
New-Item -ItemType Directory -Force -Path $mt5ReportsDir | Out-Null

& (Join-Path $ProjectRoot "TOOLS\RESET_MICROBOT_STRATEGY_TESTER_SANDBOX.ps1") -ProjectRoot $ProjectRoot -SymbolAlias $sandboxSymbolAlias -SandboxTag $sanitizedTag | Out-Null
Initialize-StrategyTesterSandboxContract -SandboxRoot $sandboxRoot -StorageAlias $storageAlias -RuntimeSymbol $Symbol
& (Join-Path $ProjectRoot "TOOLS\COMPILE_MICROBOT.ps1") -ExpertName $ExpertName | Out-Null

$config = @"
[Tester]
Expert=$ExpertPath
ExpertParameters=$expertParametersTargetName
Symbol=$Symbol
Period=$Period
Model=$Model
Optimization=$Optimization
OptimizationCriterion=$OptimizationCriterion
FromDate=$FromDate
ToDate=$ToDate
ForwardMode=0
Deposit=$Deposit
Currency=USD
Leverage=$Leverage
UseLocal=1
UseRemote=0
ReplaceReport=1
Report=$reportBaseRel
ShutdownTerminal=1
"@

$config | Set-Content -LiteralPath $configPath -Encoding ASCII

$beforeTesterLogs = @()
if (Test-Path -LiteralPath $testerLogDir) {
    $beforeTesterLogs = @(Get-ChildItem -LiteralPath $testerLogDir -File | Select-Object -ExpandProperty FullName)
}
$beforeTerminalLogs = @()
if (Test-Path -LiteralPath $terminalLogDir) {
    $beforeTerminalLogs = @(Get-ChildItem -LiteralPath $terminalLogDir -File | Select-Object -ExpandProperty FullName)
}
$beforeAgentLogs = @()
if (Test-Path -LiteralPath $testerAgentsRoot) {
    $beforeAgentLogs = @(Get-ChildItem -LiteralPath $testerAgentsRoot -Recurse -File -Filter *.log | Select-Object -ExpandProperty FullName)
}

Stop-MatchingTerminalProcesses -ExecutablePath $Mt5Exe
Start-Sleep -Seconds 2

$runLaunchedAt = Get-Date
$terminalArgs = @("/config:$configPath")
if ($PortableTerminal) {
    $terminalArgs += "/portable"
}
$process = Start-Process -FilePath $Mt5Exe -ArgumentList $terminalArgs -PassThru
$trackedProcessId = $null
for ($attempt = 1; $attempt -le 40; $attempt++) {
    $trackedProcessId = Get-MatchingTerminalProcessId -ExecutablePath $Mt5Exe -ConfigPath $configPath
    if ($null -ne $trackedProcessId) {
        break
    }

    if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
        $trackedProcessId = $process.Id
    }

    Start-Sleep -Milliseconds 500
}

$timedOut = $false
try {
    if ($null -ne $trackedProcessId) {
        Wait-Process -Id $trackedProcessId -Timeout $TimeoutSec -ErrorAction Stop
    } else {
        Wait-Process -Id $process.Id -Timeout $TimeoutSec -ErrorAction Stop
    }
} catch {
    $timedOut = $true
    foreach ($processIdToStop in @($trackedProcessId, $process.Id) | Where-Object { $null -ne $_ } | Select-Object -Unique) {
        Get-Process -Id $processIdToStop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Wait-ProcessTerminationGracefully -ProcessIds @($trackedProcessId, $process.Id) -TimeoutSeconds 30
}

Start-Sleep -Seconds 2

$reportCandidates = @(
    (Join-Path $mt5ReportsDir ($runId + ".htm")),
    (Join-Path $mt5ReportsDir ($runId + ".html")),
    (Join-Path $mt5ReportsDir ($runId + ".xml"))
) | Where-Object { Test-Path -LiteralPath $_ }

$copiedReports = @()
foreach ($reportPath in $reportCandidates) {
    $target = Join-Path $evidenceDir ($runId + "__report__" + [System.IO.Path]::GetFileName($reportPath))
    Copy-Item -LiteralPath $reportPath -Destination $target -Force
    $copiedReports += $target
}

$afterTesterLogs = @()
if (Test-Path -LiteralPath $testerLogDir) {
    $afterTesterLogs = @(Get-ChildItem -LiteralPath $testerLogDir -File | Select-Object -ExpandProperty FullName)
}
$newTesterLogs = @($afterTesterLogs | Where-Object { $_ -notin $beforeTesterLogs })
if ($newTesterLogs.Count -eq 0 -and (Test-Path -LiteralPath $testerLogDir)) {
    $latest = Get-ChildItem -LiteralPath $testerLogDir -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $newTesterLogs = @($latest.FullName) }
}

$copiedTesterLogs = @()
foreach ($logPath in $newTesterLogs) {
    $target = Join-Path $evidenceDir ($runId + "__tester__" + [System.IO.Path]::GetFileName($logPath))
    Copy-Item -LiteralPath $logPath -Destination $target -Force
    $copiedTesterLogs += $target
}

$afterTerminalLogs = @()
if (Test-Path -LiteralPath $terminalLogDir) {
    $afterTerminalLogs = @(Get-ChildItem -LiteralPath $terminalLogDir -File | Select-Object -ExpandProperty FullName)
}
$newTerminalLogs = @($afterTerminalLogs | Where-Object { $_ -notin $beforeTerminalLogs })
if ($newTerminalLogs.Count -eq 0 -and (Test-Path -LiteralPath $terminalLogDir)) {
    $latest = Get-ChildItem -LiteralPath $terminalLogDir -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $newTerminalLogs = @($latest.FullName) }
}

$copiedTerminalLogs = @()
foreach ($logPath in $newTerminalLogs) {
    $target = Join-Path $evidenceDir ($runId + "__terminal__" + [System.IO.Path]::GetFileName($logPath))
    Copy-Item -LiteralPath $logPath -Destination $target -Force
    $copiedTerminalLogs += $target
}

$afterAgentLogs = @()
if (Test-Path -LiteralPath $testerAgentsRoot) {
    $afterAgentLogs = @(Get-ChildItem -LiteralPath $testerAgentsRoot -Recurse -File -Filter *.log | Select-Object -ExpandProperty FullName)
}
$newAgentLogs = @($afterAgentLogs | Where-Object { $_ -notin $beforeAgentLogs })
if ($newAgentLogs.Count -eq 0 -and (Test-Path -LiteralPath $testerAgentsRoot)) {
    $latest = Get-ChildItem -LiteralPath $testerAgentsRoot -Recurse -File -Filter *.log | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($latest) { $newAgentLogs = @($latest.FullName) }
}

$copiedAgentLogs = @()
foreach ($logPath in $newAgentLogs) {
    $target = Join-Path $evidenceDir ($runId + "__agent__" + [System.IO.Path]::GetFileName($logPath))
    Copy-Item -LiteralPath $logPath -Destination $target -Force
    $copiedAgentLogs += $target
}

$runOutcome = Get-TesterRunOutcome -LogPaths $copiedTesterLogs -ExpertName $ExpertName -Symbol $Symbol -Period $Period -FromDate $FromDate -ToDate $ToDate
$finalBalance = $runOutcome.final_balance
$testDuration = $runOutcome.test_duration
$resultLabel = $runOutcome.result_label
 $optimizationResultRows = 0
if ($timedOut -and [string]::IsNullOrWhiteSpace($resultLabel)) {
    $resultLabel = "timed_out"
}
if ($Optimization -ne 0) {
    $optimizationResultRows = Get-OptimizationReportRowCount -ReportPaths $copiedReports
}

$executionSummaryPath = Join-Path $sandboxRoot ("state\{0}\execution_summary.json" -f $sandboxSymbolAlias)
$runtimeStatePath = Join-Path $sandboxRoot ("state\{0}\runtime_state.csv" -f $sandboxSymbolAlias)
$candidateSignalsPath = Join-Path $sandboxRoot ("logs\{0}\candidate_signals.csv" -f $sandboxSymbolAlias)
$onnxObservationPath = Join-Path $sandboxRoot ("logs\{0}\onnx_observations.csv" -f $sandboxSymbolAlias)
$bucketSummaryPath = Join-Path $sandboxRoot ("logs\{0}\learning_bucket_summary_v1.csv" -f $sandboxSymbolAlias)
$learningObservationsPath = Join-Path $sandboxRoot ("logs\{0}\learning_observations_v2.csv" -f $sandboxSymbolAlias)
$tuningDeckhandPath = Join-Path $sandboxRoot ("logs\{0}\tuning_deckhand.csv" -f $sandboxSymbolAlias)
$testerTelemetryPath = Join-Path $sandboxRoot ("state\{0}\tester_telemetry_latest.json" -f $sandboxSymbolAlias)
$testerTelemetrySessionPath = Join-Path $sandboxRoot ("run\{0}\tester_telemetry_session.json" -f $sandboxSymbolAlias)
$testerOptimizationPassesPath = Join-Path $sandboxRoot ("run\{0}\tester_optimization_passes.jsonl" -f $sandboxSymbolAlias)

$executionSummary = $null
if (Test-Path -LiteralPath $executionSummaryPath) {
    $executionSummary = Get-Content -LiteralPath $executionSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$testerTelemetry = $null
if (Test-Path -LiteralPath $testerTelemetryPath) {
    $testerTelemetry = Get-Content -LiteralPath $testerTelemetryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$testerOptimizationPassCount = 0
if (Test-Path -LiteralPath $testerOptimizationPassesPath) {
    $testerOptimizationPassCount = @(Get-Content -LiteralPath $testerOptimizationPassesPath -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
}

$runtimeMap = Get-KeyValueCsvMap -Path $runtimeStatePath
$runtimeRealizedPnlLifetime = if ($runtimeMap.Contains('realized_pnl_lifetime')) { $runtimeMap['realized_pnl_lifetime'] } else { $null }
$testerTelemetryRealizedPnl = Convert-ToDoubleOrNull (Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'realized_pnl_lifetime' -Default $null)
$testerTelemetryExperimentStatus = [string](Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'experiment_status' -Default '')
$optimizationMaterialized = (($Optimization -ne 0) -and ($testerOptimizationPassCount -gt 0))
$optimizationResultSource = if ($optimizationResultRows -gt 0) { "mt5_report" } else { "none" }

if ($optimizationMaterialized -and $optimizationResultRows -lt $testerOptimizationPassCount) {
    $optimizationResultRows = $testerOptimizationPassCount
    $optimizationResultSource = "agent_passes"
}

$effectiveResultLabel = $resultLabel
if ($timedOut -and $testerOptimizationPassCount -gt 0) {
    $effectiveResultLabel = "timed_out_with_materialized_passes"
}

$effectiveRealizedPnlLifetime = $runtimeRealizedPnlLifetime
if (($optimizationMaterialized -or $testerTelemetryExperimentStatus -eq 'OPTIMIZATION_PASS') -and $null -ne $testerTelemetryRealizedPnl) {
    $effectiveRealizedPnlLifetime = [string]([math]::Round($testerTelemetryRealizedPnl, 2))
}

$paperOpenRows = 0
$paperScoreGateRows = 0
$acceptedEvaluatedRows = 0
$scoreBelowTriggerRows = 0
$candidateSignalRowsTotal = 0
$onnxObservationRows = 0
$learningObservationRows = 0
$topCandidateReasons = @()
$paperCloseStats = @()
$paperOpenBySetupRegime = @()
$deckhandSnapshot = $null
if (Test-Path -LiteralPath $candidateSignalsPath) {
    $candidateRows = Import-TabCsvWithRetry -Path $candidateSignalsPath
    $candidateSignalRowsTotal = @($candidateRows).Count
    $paperOpenRows = @($candidateRows | Where-Object { $_.stage -eq 'PAPER_OPEN' -and $_.reason_code -eq 'PAPER_POSITION_OPENED' }).Count
    $paperScoreGateRows = @($candidateRows | Where-Object { $_.stage -eq 'EVALUATED' -and $_.reason_code -eq 'PAPER_SCORE_GATE' }).Count
    $acceptedEvaluatedRows = @($candidateRows | Where-Object { $_.stage -eq 'EVALUATED' -and $_.accepted -eq '1' }).Count
    $scoreBelowTriggerRows = @($candidateRows | Where-Object { $_.stage -eq 'EVALUATED' -and $_.reason_code -eq 'SCORE_BELOW_TRIGGER' }).Count
    $topCandidateReasons = @(
        $candidateRows |
        Group-Object stage,reason_code |
        Sort-Object Count -Descending |
        Select-Object -First 12 @{ Name = 'count'; Expression = { $_.Count } }, @{ Name = 'name'; Expression = { $_.Name } }
    )
    $paperOpenBySetupRegime = @(
        $candidateRows |
        Where-Object { $_.stage -eq 'PAPER_OPEN' -and $_.reason_code -eq 'PAPER_POSITION_OPENED' } |
        Group-Object setup_type,market_regime |
        Sort-Object Count -Descending |
        Select-Object -First 12 @{ Name = 'count'; Expression = { $_.Count } }, @{ Name = 'name'; Expression = { $_.Name } }
    )
}

if (Test-Path -LiteralPath $onnxObservationPath) {
    $onnxObservationRows = @(Import-TabCsvWithRetry -Path $onnxObservationPath).Count
}

$worstBuckets = @()
if (Test-Path -LiteralPath $bucketSummaryPath) {
    $worstBuckets = @(
        Import-TabCsvWithRetry -Path $bucketSummaryPath |
        Sort-Object { [double]$_.avg_pnl } |
        Select-Object -First 6 setup_type,market_regime,samples,wins,losses,avg_pnl
    )
}

if (Test-Path -LiteralPath $learningObservationsPath) {
    $learningObservationRows = @(Import-TabCsvWithRetry -Path $learningObservationsPath).Count
    $paperCloseStats = @(
        Import-TabCsvWithRetry -Path $learningObservationsPath |
        Group-Object close_reason |
        Sort-Object Count -Descending |
        ForEach-Object {
            [pscustomobject]@{
                close_reason = $_.Name
                count        = $_.Count
                avg_pnl      = [math]::Round((($_.Group | Measure-Object -Property pnl -Average).Average), 4)
            }
        }
    )
}

if (Test-Path -LiteralPath $tuningDeckhandPath) {
    $deckhandRows = @(Import-TabCsvWithRetry -Path $tuningDeckhandPath)
    if ($deckhandRows.Count -gt 0) {
        $deckhandSnapshot = $deckhandRows[-1]
    }
}

$summaryTrustState = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'trust_state' -Default '')
$summaryTrustReason = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'trust_reason' -Default '')
$summaryExecutionQualityState = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'execution_quality_state' -Default '')
$summaryCostPressureState = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'cost_pressure_state' -Default '')

if ($null -ne $deckhandSnapshot) {
    if ($deckhandSnapshot.PSObject.Properties.Name -contains 'trust_state' -and -not [string]::IsNullOrWhiteSpace([string]$deckhandSnapshot.trust_state)) {
        $summaryTrustState = [string]$deckhandSnapshot.trust_state
    }
    if ($deckhandSnapshot.PSObject.Properties.Name -contains 'reason_code' -and -not [string]::IsNullOrWhiteSpace([string]$deckhandSnapshot.reason_code)) {
        $summaryTrustReason = [string]$deckhandSnapshot.reason_code
    }
    if ($deckhandSnapshot.PSObject.Properties.Name -contains 'execution_quality_state' -and -not [string]::IsNullOrWhiteSpace([string]$deckhandSnapshot.execution_quality_state)) {
        $summaryExecutionQualityState = [string]$deckhandSnapshot.execution_quality_state
    }
    if ($deckhandSnapshot.PSObject.Properties.Name -contains 'cost_pressure_state' -and -not [string]::IsNullOrWhiteSpace([string]$deckhandSnapshot.cost_pressure_state)) {
        $summaryCostPressureState = [string]$deckhandSnapshot.cost_pressure_state
    }
}

if ([string]::IsNullOrWhiteSpace($summaryTrustState) -and $runtimeMap.Contains('trust_state')) {
    $summaryTrustState = [string]$runtimeMap['trust_state']
}
if ([string]::IsNullOrWhiteSpace($summaryTrustReason) -and $runtimeMap.Contains('trust_reason')) {
    $summaryTrustReason = [string]$runtimeMap['trust_reason']
}
if ([string]::IsNullOrWhiteSpace($summaryExecutionQualityState) -and $runtimeMap.Contains('execution_quality_state')) {
    $summaryExecutionQualityState = [string]$runtimeMap['execution_quality_state']
}
if ([string]::IsNullOrWhiteSpace($summaryCostPressureState) -and $runtimeMap.Contains('cost_pressure_state')) {
    $summaryCostPressureState = [string]$runtimeMap['cost_pressure_state']
}

$conversionRatio = 0.0
if ($acceptedEvaluatedRows -gt 0) {
    $conversionRatio = [math]::Round(($paperOpenRows / [double]$acceptedEvaluatedRows), 4)
}

$testerTelemetryPresentForRun = (Test-Path -LiteralPath $testerTelemetryPath)
$candidateSignalsPresentForRun = (Test-Path -LiteralPath $candidateSignalsPath)
$onnxObservationsPresentForRun = (Test-Path -LiteralPath $onnxObservationPath)
$learningObservationsPresentForRun = (Test-Path -LiteralPath $learningObservationsPath)
$observationInfraReady = ($candidateSignalsPresentForRun -and $onnxObservationsPresentForRun -and $testerTelemetryPresentForRun)
$observationDataState = "OBSERVATION_INFRA_NOT_MATERIALIZED"
$observationDataReason = "NO_CANDIDATE_OR_ONNX_ARTIFACTS"
$paperLearningState = "MISSING_SUPPORTING_ARTIFACTS"

if ($learningObservationRows -gt 0) {
    $observationDataState = "LEARNING_OBSERVATIONS_PRESENT"
    $observationDataReason = "PAPER_LESSONS_AVAILABLE"
    $paperLearningState = "READY"
}
elseif ($paperOpenRows -gt 0) {
    $observationDataState = "PAPER_POSITIONS_OPENED_BUT_NOT_CLOSED"
    $observationDataReason = "WAIT_FOR_FIRST_PAPER_CLOSURE"
    $paperLearningState = "WAITING_FOR_FIRST_PAPER_CLOSE"
}
elseif ($paperScoreGateRows -gt 0 -or $acceptedEvaluatedRows -gt 0) {
    if ($observationInfraReady -or $candidateSignalsPresentForRun -or $onnxObservationsPresentForRun) {
        $observationDataState = "NO_PAPER_LESSONS_YET"
        $observationDataReason = "SIGNALS_EXIST_BUT_NO_PAPER_CLOSES"
        $paperLearningState = "WAITING_FOR_FIRST_PAPER_OPEN"
    }
}
elseif ($candidateSignalRowsTotal -gt 0 -or $onnxObservationRows -gt 0 -or $testerTelemetryPresentForRun) {
    $observationDataState = "SIGNAL_PATH_WITHOUT_PAPER_ACTIVITY"
    $observationDataReason = "NO_ACCEPTED_PAPER_ACTIVITY"
    $paperLearningState = "NO_ACCEPTED_PAPER_ACTIVITY"
}

if ($RestoreMicrobotsProfile) {
    & (Join-Path $ProjectRoot "RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1") | Out-Null
}

$result = [ordered]@{
    run_id                = $runId
    generated_at_utc      = (Get-Date).ToUniversalTime().ToString("o")
    symbol_alias          = $canonicalAlias
    code_symbol           = $resolvedAlias
    storage_alias         = $storageAlias
    sandbox_name          = $sandboxName
    config_path           = $configPath
    mt5_exe               = $Mt5Exe
    terminal_data_dir     = $TerminalDataDir
    portable_terminal     = [bool]$PortableTerminal
    symbol                = $Symbol
    expert_name           = $ExpertName
    expert_path           = $ExpertPath
    from_date             = $FromDate
    to_date               = $ToDate
    optimization          = $Optimization
    optimization_criterion = $OptimizationCriterion
    timeout_sec           = $TimeoutSec
    optimization_result_rows = $optimizationResultRows
    optimization_result_source = $optimizationResultSource
    expert_parameters_source_path = $(if ($expertParametersSourcePath -ne "") { $expertParametersSourcePath } else { $null })
    expert_parameters_profile_name = $(if ($expertParametersTargetName -ne "") { $expertParametersTargetName } else { $null })
    requested_model       = $requestedModel
    model                 = $Model
    model_normalized_for_qdm_custom_symbol = $modelNormalizedForQdmCustomSymbol
    timed_out             = $timedOut
    reports_copied        = $copiedReports
    tester_logs_copied    = $copiedTesterLogs
    terminal_logs_copied  = $copiedTerminalLogs
    agent_logs_copied     = $copiedAgentLogs
    final_balance         = $finalBalance
    test_duration         = $testDuration
    result_label          = $effectiveResultLabel
    raw_result_label      = $resultLabel
    restore_profile       = [bool]$RestoreMicrobotsProfile
    tester_telemetry_path = $(if (Test-Path -LiteralPath $testerTelemetryPath) { $testerTelemetryPath } else { $null })
    tester_telemetry_session_path = $(if (Test-Path -LiteralPath $testerTelemetrySessionPath) { $testerTelemetrySessionPath } else { $null })
    tester_optimization_passes_path = $(if (Test-Path -LiteralPath $testerOptimizationPassesPath) { $testerOptimizationPassesPath } else { $null })
    tester_optimization_pass_count = $testerOptimizationPassCount
    candidate_signal_rows_total = $candidateSignalRowsTotal
    onnx_observation_rows = $onnxObservationRows
    learning_observation_rows = $learningObservationRows
    trust_state = $summaryTrustState
    trust_reason = $summaryTrustReason
    execution_quality_state = $summaryExecutionQualityState
    cost_pressure_state = $summaryCostPressureState
    learning_sample_count = [int](Get-SafeObjectValue -Object $executionSummary -PropertyName 'learning_sample_count' -Default 0)
    paper_open_rows = $paperOpenRows
    paper_score_gate_rows = $paperScoreGateRows
    accepted_evaluated_rows = $acceptedEvaluatedRows
    observation_infra_ready = $observationInfraReady
    observation_data_state = $observationDataState
    observation_data_reason = $observationDataReason
    paper_learning_state = $paperLearningState
}

$summary = [ordered]@{
    run_id                    = $runId
    symbol_alias              = $canonicalAlias
    code_symbol               = $resolvedAlias
    storage_alias             = $storageAlias
    symbol                    = $Symbol
    expert_name               = $ExpertName
    from_date                 = $FromDate
    to_date                   = $ToDate
    requested_model           = $requestedModel
    model                     = $Model
    model_normalized_for_qdm_custom_symbol = $modelNormalizedForQdmCustomSymbol
    optimization              = $Optimization
    optimization_criterion    = $OptimizationCriterion
    timeout_sec               = $TimeoutSec
    optimization_result_rows  = $optimizationResultRows
    optimization_result_source = $optimizationResultSource
    expert_parameters_profile_name = $expertParametersTargetName
    final_balance             = $finalBalance
    test_duration             = $testDuration
    result_label              = $effectiveResultLabel
    raw_result_label          = $resultLabel
    worker_name               = $workerToken
    evidence_dir              = $evidenceDir
    trust_state               = $summaryTrustState
    trust_reason              = $summaryTrustReason
    execution_quality_state   = $summaryExecutionQualityState
    cost_pressure_state       = $summaryCostPressureState
    market_regime             = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'market_regime' -Default '')
    last_setup_type           = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'last_setup_type' -Default '')
    learning_bias             = [double](Get-SafeObjectValue -Object $executionSummary -PropertyName 'learning_bias' -Default 0.0)
    learning_sample_count     = [int](Get-SafeObjectValue -Object $executionSummary -PropertyName 'learning_sample_count' -Default 0)
    learning_win_count        = [int](Get-SafeObjectValue -Object $executionSummary -PropertyName 'learning_win_count' -Default 0)
    learning_loss_count       = [int](Get-SafeObjectValue -Object $executionSummary -PropertyName 'learning_loss_count' -Default 0)
    tester_custom_score       = [double](Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'custom_score' -Default 0.0)
    tester_policy_revision    = [int](Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'policy_revision' -Default 0)
    tester_experiment_status  = [string](Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'experiment_status' -Default '')
    tester_trust_penalty      = [double](Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'trust_penalty' -Default 0.0)
    tester_cost_penalty       = [double](Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'cost_penalty' -Default 0.0)
    tester_execution_penalty  = [double](Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'execution_penalty' -Default 0.0)
    tester_latency_penalty    = [double](Get-SafeObjectValue -Object $testerTelemetry -PropertyName 'latency_penalty' -Default 0.0)
    candidate_signal_rows_total = $candidateSignalRowsTotal
    onnx_observation_rows    = $onnxObservationRows
    learning_observation_rows = $learningObservationRows
    paper_open_rows           = $paperOpenRows
    paper_score_gate_rows     = $paperScoreGateRows
    accepted_evaluated_rows   = $acceptedEvaluatedRows
    score_below_trigger_rows  = $scoreBelowTriggerRows
    paper_conversion_ratio    = $conversionRatio
    observation_infra_ready   = $observationInfraReady
    observation_data_state    = $observationDataState
    observation_data_reason   = $observationDataReason
    paper_learning_state      = $paperLearningState
    realized_pnl_lifetime     = $effectiveRealizedPnlLifetime
    runtime_realized_pnl_lifetime = $runtimeRealizedPnlLifetime
    execution_summary_trust_state = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'trust_state' -Default '')
    execution_summary_trust_reason = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'trust_reason' -Default '')
    execution_summary_cost_pressure_state = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'cost_pressure_state' -Default '')
    execution_summary_execution_quality_state = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName 'execution_quality_state' -Default '')
    tester_telemetry          = $testerTelemetry
    tester_optimization_passes_path = $(if (Test-Path -LiteralPath $testerOptimizationPassesPath) { $testerOptimizationPassesPath } else { $null })
    tester_optimization_pass_count = $testerOptimizationPassCount
    top_candidate_reasons     = $topCandidateReasons
    paper_open_by_setup_regime = $paperOpenBySetupRegime
    paper_close_stats         = $paperCloseStats
    deckhand_snapshot         = $deckhandSnapshot
    worst_buckets             = $worstBuckets
    tester_telemetry_present_for_run = $testerTelemetryPresentForRun
    candidate_signals_present_for_run = $candidateSignalsPresentForRun
    onnx_observations_present_for_run = $onnxObservationsPresentForRun
    learning_observations_present_for_run = $learningObservationsPresentForRun
}

$jsonPath = Join-Path $evidenceDir ($runId + ".json")
$txtPath = Join-Path $evidenceDir ($runId + ".txt")
$summaryPath = Join-Path $evidenceDir ($runId + "_summary.json")

$knowledgeJsonPath = Join-Path $evidenceDir ($runId + "_knowledge.json")
$knowledgeMarkdownPath = Join-Path $evidenceDir ($runId + "_knowledge.md")
$researchManifestPath = Join-Path $ResearchOutputRoot "reports\research_export_manifest_latest.json"
$researchRefreshStatus = "SKIPPED_NOT_REQUIRED"
$researchRefreshNeeded = $false
$researchRefreshRan = $false
$researchRefreshError = $null
$researchManifest = $null
$researchTesterTelemetryRows = 0
$researchTesterPassRows = 0

$result['evidence_dir'] = $evidenceDir
$result['json_path'] = $jsonPath
$result['summary_path'] = $summaryPath
$summary['evidence_dir'] = $evidenceDir
$summary['summary_path'] = $summaryPath

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$result | Out-String | Set-Content -LiteralPath $txtPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

if (-not $SkipKnowledgeExport) {
    & (Join-Path $ProjectRoot "TOOLS\EXPORT_STRATEGY_TESTER_KNOWLEDGE.ps1") `
        -ProjectRoot $ProjectRoot `
        -RunId $runId `
        -SymbolAlias $storageAlias `
        -EvidenceDir $evidenceDir `
        -SandboxRoot $sandboxRoot | Out-Null
}

if ($SkipResearchRefresh) {
    $researchRefreshStatus = "SKIPPED_BY_FLAG"
}
elseif ($SkipKnowledgeExport) {
    $researchRefreshStatus = "SKIPPED_WITHOUT_KNOWLEDGE_EXPORT"
}
elseif ($Optimization -ne 0 -or $testerOptimizationPassCount -gt 0) {
    $researchRefreshStatus = "PENDING"
    $researchRefreshNeeded = $true
}

if ($researchRefreshNeeded) {
    $refreshScriptPath = Join-Path $ProjectRoot "RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1"
    $manifestWriteTimeUtc = if (Test-Path -LiteralPath $researchManifestPath) { (Get-Item -LiteralPath $researchManifestPath).LastWriteTimeUtc } else { [datetime]::MinValue }
    $evidenceWriteTimeUtc = Get-LatestWriteTimeUtc -Paths @(
        $summaryPath,
        $knowledgeJsonPath,
        $testerTelemetryPath,
        $testerTelemetrySessionPath,
        $testerOptimizationPassesPath
    )
    $researchRefreshNeeded = ($evidenceWriteTimeUtc -gt $manifestWriteTimeUtc)
    if (-not $researchRefreshNeeded) {
        $researchRefreshStatus = "SKIPPED_UP_TO_DATE"
    }
    else {
        try {
            & $refreshScriptPath -ProjectRoot $ProjectRoot -OutputRoot $ResearchOutputRoot -PerfProfile $ResearchPerfProfile | Out-Null
            $researchRefreshRan = $true
            $researchRefreshStatus = "REFRESHED"
        }
        catch {
            $researchRefreshError = $_.Exception.Message
            $researchRefreshStatus = "FAILED"
        }
    }
}

$researchManifest = Read-JsonFile -Path $researchManifestPath
if ($null -ne $researchManifest -and $researchManifest.PSObject.Properties.Name -contains "datasets") {
    $datasets = $researchManifest.datasets
    if ($null -ne $datasets -and $datasets.PSObject.Properties.Name -contains "tester_telemetry") {
        $researchTesterTelemetryRows = [int](Get-SafeObjectValue -Object $datasets.tester_telemetry -PropertyName 'rows' -Default 0)
    }
    if ($null -ne $datasets -and $datasets.PSObject.Properties.Name -contains "tester_pass_frames") {
        $researchTesterPassRows = [int](Get-SafeObjectValue -Object $datasets.tester_pass_frames -PropertyName 'rows' -Default 0)
    }
}

$result['research_export_manifest_path'] = $(if (Test-Path -LiteralPath $researchManifestPath) { $researchManifestPath } else { $null })
$result['research_export_status'] = $researchRefreshStatus
$result['research_export_refreshed'] = $researchRefreshRan
$result['research_export_error'] = $researchRefreshError
$result['research_export_tester_telemetry_rows_total'] = $researchTesterTelemetryRows
$result['research_export_tester_pass_rows_total'] = $researchTesterPassRows
$result['research_export_tester_telemetry_rows'] = $researchTesterTelemetryRows
$result['research_export_tester_pass_rows'] = $researchTesterPassRows
$result['research_export_tester_telemetry_present_for_run'] = [bool](Test-Path -LiteralPath $testerTelemetryPath)
$result['research_export_tester_telemetry_session_present_for_run'] = [bool](Test-Path -LiteralPath $testerTelemetrySessionPath)
$result['research_export_tester_pass_rows_for_run'] = $testerOptimizationPassCount
$result['knowledge_json_path'] = $(if (Test-Path -LiteralPath $knowledgeJsonPath) { $knowledgeJsonPath } else { $null })
$result['knowledge_markdown_path'] = $(if (Test-Path -LiteralPath $knowledgeMarkdownPath) { $knowledgeMarkdownPath } else { $null })

$summary['research_export_manifest_path'] = $(if (Test-Path -LiteralPath $researchManifestPath) { $researchManifestPath } else { $null })
$summary['research_export_status'] = $researchRefreshStatus
$summary['research_export_refreshed'] = $researchRefreshRan
$summary['research_export_error'] = $researchRefreshError
$summary['research_export_tester_telemetry_rows_total'] = $researchTesterTelemetryRows
$summary['research_export_tester_pass_rows_total'] = $researchTesterPassRows
$summary['research_export_tester_telemetry_rows'] = $researchTesterTelemetryRows
$summary['research_export_tester_pass_rows'] = $researchTesterPassRows
$summary['research_export_tester_telemetry_present_for_run'] = [bool](Test-Path -LiteralPath $testerTelemetryPath)
$summary['research_export_tester_telemetry_session_present_for_run'] = [bool](Test-Path -LiteralPath $testerTelemetrySessionPath)
$summary['research_export_tester_pass_rows_for_run'] = $testerOptimizationPassCount
$summary['knowledge_json_path'] = $(if (Test-Path -LiteralPath $knowledgeJsonPath) { $knowledgeJsonPath } else { $null })
$summary['knowledge_markdown_path'] = $(if (Test-Path -LiteralPath $knowledgeMarkdownPath) { $knowledgeMarkdownPath } else { $null })

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$result
