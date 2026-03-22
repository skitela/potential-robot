param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

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

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Read-TabFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $map = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split "`t", 2
        if ($parts.Count -lt 2) {
            continue
        }

        $map[$parts[0]] = $parts[1]
    }

    return [pscustomobject]$map
}

function ConvertTo-BoolLoose {
    param($Value)

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    return @("1","true","yes","on") -contains $text.ToLowerInvariant()
}

function ConvertTo-DoubleLoose {
    param($Value)

    $text = [string]$Value
    $number = 0.0
    if ([double]::TryParse($text,[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$number)) {
        return $number
    }

    return 0.0
}

function Get-FileFreshness {
    param(
        [string]$Path,
        [int]$ThresholdSeconds
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            exists = $false
            fresh = $false
            age_seconds = $null
            last_write_local = $null
            threshold_seconds = $ThresholdSeconds
        }
    }

    $item = Get-Item -LiteralPath $Path
    $ageSeconds = [int][math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)
    return [pscustomobject]@{
        exists = $true
        fresh = ($ageSeconds -le $ThresholdSeconds)
        age_seconds = $ageSeconds
        last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        threshold_seconds = $ThresholdSeconds
    }
}

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$Severity,
        [string]$Component,
        [string]$Message
    )

    $Findings.Add([pscustomobject]@{
        severity = $Severity
        component = $Component
        message = $Message
    }) | Out-Null
}

$mt5StatusPath = Join-Path $opsRoot "mt5_tester_status_latest.json"
$mt5QueuePath = Join-Path $opsRoot "mt5_retest_queue_latest.json"
$autonomousPath = Join-Path $opsRoot "autonomous_90p_latest.json"
$mlHintsPath = Join-Path $opsRoot "ml_tuning_hints_latest.json"
$qdmProfilePath = Join-Path $opsRoot "qdm_weakest_profile_latest.json"
$stateRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state"

$mt5Status = Read-JsonFile -Path $mt5StatusPath
$mt5Queue = Read-JsonFile -Path $mt5QueuePath
$autonomous = Read-JsonFile -Path $autonomousPath

$freshness = [ordered]@{
    mt5_status = Get-FileFreshness -Path $mt5StatusPath -ThresholdSeconds 600
    mt5_retest_queue = Get-FileFreshness -Path $mt5QueuePath -ThresholdSeconds 900
    autonomous_90p = Get-FileFreshness -Path $autonomousPath -ThresholdSeconds 600
    ml_tuning_hints = Get-FileFreshness -Path $mlHintsPath -ThresholdSeconds 1200
    qdm_weakest_profile = Get-FileFreshness -Path $qdmProfilePath -ThresholdSeconds 1200
}

$wrapperState = [ordered]@{
    supervisor = ((Get-WrapperCount -Pattern "*autonomous_90p_supervisor_wrapper_*") -gt 0)
    mt5_status_watcher = ((Get-WrapperCount -Pattern "*mt5_tester_status_watcher_wrapper_*") -gt 0)
    ml = ((Get-WrapperCount -Pattern "*refresh_and_train_ml_wrapper_*") -gt 0)
}

$processState = [ordered]@{
    qdmcli = @(Get-Process qdmcli -ErrorAction SilentlyContinue).Count
    secondary_terminal = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "terminal64.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                $_.ExecutablePath -eq "C:\Program Files\MetaTrader 5\terminal64.exe"
            }
    ).Count
    secondary_metatester = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "metatester64.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                $_.ExecutablePath -eq "C:\Program Files\MetaTrader 5\metatester64.exe"
            }
    ).Count
}

$findings = New-Object System.Collections.Generic.List[object]
$tuningSyncIssues = New-Object System.Collections.Generic.List[object]

if ($wrapperState.supervisor -and -not $freshness.autonomous_90p.fresh) {
    Add-Finding -Findings $findings -Severity "high" -Component "supervisor" -Message "Supervisor wrapper is running but autonomous_90p_latest is stale."
}

if ($wrapperState.mt5_status_watcher -and -not $freshness.mt5_status.fresh) {
    Add-Finding -Findings $findings -Severity "high" -Component "mt5_watcher" -Message "MT5 watcher is running but mt5_tester_status_latest is stale."
}

if ($null -ne $mt5Status) {
    $mt5State = [string]$mt5Status.state
    $watchedTerminalRunning = [bool]$mt5Status.watched_terminal_running
    $watchedMetaTesterRunning = $false
    if ($mt5Status.PSObject.Properties.Name -contains "watched_metatester_running") {
        $watchedMetaTesterRunning = [bool]$mt5Status.watched_metatester_running
    }
    $watchedExecutorRunning = $watchedTerminalRunning -or $watchedMetaTesterRunning -or ($processState.secondary_metatester -gt 0)
    $currentSymbol = [string]$mt5Status.current_symbol

    if ($mt5State -eq "running" -and -not $watchedExecutorRunning) {
        Add-Finding -Findings $findings -Severity "high" -Component "mt5_status" -Message "MT5 status says running, but neither watched tester terminal nor its metatester executor is running."
    }

    if ($mt5State -eq "stale") {
        Add-Finding -Findings $findings -Severity "medium" -Component "mt5_status" -Message ("MT5 tester for {0} is stale and needs inspection or restart." -f $currentSymbol)
    }

    if ($mt5State -eq "running" -and -not $freshness.mt5_status.fresh) {
        Add-Finding -Findings $findings -Severity "high" -Component "mt5_status" -Message "MT5 status is marked running but the status file is stale."
    }
}

if ($null -ne $mt5Queue) {
    if (-not $freshness.mt5_retest_queue.fresh) {
        Add-Finding -Findings $findings -Severity "medium" -Component "mt5_queue" -Message "MT5 retest queue file is stale."
    }

    if ($null -ne $mt5Status) {
        $queueSymbol = [string]$mt5Queue.current_symbol
        $queueState = [string]$mt5Queue.state
        $testerSymbol = [string]$mt5Status.current_symbol
        $testerState = [string]$mt5Status.state

        if ($testerState -eq "running" -and
            $queueState -eq "running" -and
            [string]::IsNullOrWhiteSpace($queueSymbol)) {
            Add-Finding -Findings $findings -Severity "medium" -Component "mt5_queue" -Message "MT5 retest queue claims running but current_symbol is blank while tester is active."
        }

        if (-not [string]::IsNullOrWhiteSpace($queueSymbol) -and
            -not [string]::IsNullOrWhiteSpace($testerSymbol) -and
            $freshness.mt5_retest_queue.fresh -and
            $queueSymbol -ne $testerSymbol) {
            Add-Finding -Findings $findings -Severity "high" -Component "mt5_queue" -Message ("MT5 queue symbol {0} does not match tester symbol {1}." -f $queueSymbol, $testerSymbol)
        }
    }
}

if ($wrapperState.ml -and -not $freshness.ml_tuning_hints.fresh) {
    Add-Finding -Findings $findings -Severity "medium" -Component "ml" -Message "ML wrapper is active but ML hints are stale."
}

if (Test-Path -LiteralPath $stateRoot) {
    $symbolDirs = @(
        Get-ChildItem -LiteralPath $stateRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "_*" }
    )

    foreach ($dir in $symbolDirs) {
        $localPolicy = Read-TabFile -Path (Join-Path $dir.FullName "tuning_policy.csv")
        $effectivePolicy = Read-TabFile -Path (Join-Path $dir.FullName "tuning_policy_effective.csv")
        $executionSummary = Read-JsonFile -Path (Join-Path $dir.FullName "execution_summary.json")

        if ($null -eq $localPolicy -or $null -eq $effectivePolicy -or $null -eq $executionSummary) {
            continue
        }

        $paperRuntime = [bool]$executionSummary.paper_runtime_override_active
        $localAcceptedRiskMasked = (
            $paperRuntime -and
            [string]$localPolicy.experiment_status -eq "ACCEPTED" -and
            (
                [string]$localPolicy.trust_reason_domain -eq "RISK" -or
                [string]$localPolicy.trust_reason_class -eq "CONTRACT"
            )
        )

        if (-not $localAcceptedRiskMasked) {
            continue
        }

        $effectiveTrusted = ConvertTo-BoolLoose -Value $effectivePolicy.trusted_data
        $localConfidenceCap = ConvertTo-DoubleLoose -Value $localPolicy.confidence_cap
        $localRiskCap = ConvertTo-DoubleLoose -Value $localPolicy.risk_cap
        $effectiveConfidenceCap = ConvertTo-DoubleLoose -Value $effectivePolicy.confidence_cap
        $effectiveRiskCap = ConvertTo-DoubleLoose -Value $effectivePolicy.risk_cap

        if (-not $effectiveTrusted) {
            $issue = [pscustomobject]@{
                symbol = $dir.Name
                type = "accepted_policy_not_effective"
                local_trust_reason = [string]$localPolicy.trust_reason
                experiment_status = [string]$localPolicy.experiment_status
            }
            $tuningSyncIssues.Add($issue) | Out-Null
            Add-Finding -Findings $findings -Severity "medium" -Component "tuning_sync" -Message ("{0}: accepted local paper policy is still not trusted in tuning_policy_effective." -f $dir.Name)
        }

        if (
            $localConfidenceCap -gt 0.0 -and
            $localRiskCap -gt 0.0 -and
            ($effectiveConfidenceCap -le 0.0 -or $effectiveRiskCap -le 0.0)
        ) {
            $issue = [pscustomobject]@{
                symbol = $dir.Name
                type = "paper_caps_zeroed"
                local_confidence_cap = $localConfidenceCap
                local_risk_cap = $localRiskCap
                effective_confidence_cap = $effectiveConfidenceCap
                effective_risk_cap = $effectiveRiskCap
            }
            $tuningSyncIssues.Add($issue) | Out-Null
            Add-Finding -Findings $findings -Severity "medium" -Component "tuning_sync" -Message ("{0}: effective paper caps are zeroed even though local accepted caps are positive." -f $dir.Name)
        }
    }
}

if ($processState.qdmcli -gt 0 -and -not $freshness.qdm_weakest_profile.fresh) {
    Add-Finding -Findings $findings -Severity "medium" -Component "qdm" -Message "QDM process is active but the weakest data profile is stale."
}

if ($wrapperState.supervisor -and $null -ne $autonomous) {
    $actions = $autonomous.actions
    if ($null -ne $actions) {
        foreach ($property in $actions.PSObject.Properties) {
            if ([string]$property.Value -like "failed:*") {
                Add-Finding -Findings $findings -Severity "medium" -Component "supervisor_actions" -Message ("Supervisor action {0} reports failure: {1}" -f $property.Name, $property.Value)
            }
        }
    }
}

$highCount = @($findings | Where-Object { $_.severity -eq "high" }).Count
$mediumCount = @($findings | Where-Object { $_.severity -eq "medium" }).Count
$findingsArray = @($findings | ForEach-Object { $_ })

$verdict = "OK"
if ($highCount -gt 0) {
    $verdict = "CONTRADICTION_FOUND"
}
elseif ($mediumCount -gt 0) {
    $verdict = "RECHECK_REQUIRED"
}

$report = New-Object System.Collections.Specialized.OrderedDictionary
$report.Add("generated_at_local", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
$report.Add("proverb", "panskie_oko_konia_tuczy")
$report.Add("principle", "never trust a single status source without cross-checking process, file freshness and companion state")
$report.Add("verdict", $verdict)
$report.Add("needs_manual_eye", ($verdict -ne "OK"))
$report.Add("freshness", $freshness)
$report.Add("wrapper_state", $wrapperState)
$report.Add("process_state", $processState)
$report.Add("mt5_status", $mt5Status)
$report.Add("mt5_retest_queue", $mt5Queue)
$report.Add("tuning_effective_sync_issue_count", $tuningSyncIssues.Count)
$report.Add("tuning_effective_sync_issues", @($tuningSyncIssues | ForEach-Object { $_ }))
$report.Add("finding_count", $findings.Count)
$report.Add("findings", $findingsArray)

$reportObject = [pscustomobject]$report

$jsonLatest = Join-Path $opsRoot "trust_but_verify_latest.json"
$mdLatest = Join-Path $opsRoot "trust_but_verify_latest.md"
$reportObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Trust But Verify Audit")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $reportObject.generated_at_local))
$lines.Add(("- proverb: {0}" -f $reportObject.proverb))
$lines.Add(("- verdict: {0}" -f $reportObject.verdict))
$lines.Add(("- needs_manual_eye: {0}" -f $reportObject.needs_manual_eye))
$lines.Add("")
$lines.Add("## Findings")
$lines.Add("")
if ($findings.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($finding in $findings) {
        $lines.Add(("- [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message))
    }
}
$lines.Add("")
$lines.Add("## MT5")
$lines.Add("")
if ($null -ne $mt5Status) {
    $lines.Add(("- state: {0}" -f $mt5Status.state))
    $lines.Add(("- current_symbol: {0}" -f $mt5Status.current_symbol))
    $lines.Add(("- watched_terminal_running: {0}" -f $mt5Status.watched_terminal_running))
    $lines.Add(("- last_activity_at_local: {0}" -f $mt5Status.last_activity_at_local))
}
else {
    $lines.Add("- mt5 status not available")
}
$lines.Add("")
$lines.Add("## Tuning Sync")
$lines.Add("")
if ($tuningSyncIssues.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($issue in $tuningSyncIssues) {
        $lines.Add(("- {0}: {1}" -f $issue.symbol, $issue.type))
    }
}
$lines.Add("")
$lines.Add("## Freshness")
$lines.Add("")
foreach ($name in $freshness.Keys) {
    $item = $freshness[$name]
    $lines.Add(("- {0}: fresh={1}, age_s={2}" -f $name, $item.fresh, $item.age_seconds))
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8

$reportObject
