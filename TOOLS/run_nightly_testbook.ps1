param(
    [string]$Action = "run-tests",
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [int]$LookbackHours = 24,
    [int]$LatencyDurationMin = 20,
    [bool]$ContinueOnError = $true,
    [switch]$RequireIdle,
    [int]$IdleThresholdSec = 900,
    [switch]$RequireOutsideActive,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Utc-IsoNow {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Utc-Stamp {
    return (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Payload
    )
    ($Payload | ConvertTo-Json -Depth 12) + "`n" | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Append-Jsonl {
    param(
        [string]$Path,
        [object]$Payload
    )
    (($Payload | ConvertTo-Json -Depth 12 -Compress) + "`n") | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Normalize-Action {
    param([string]$Raw)
    $x = [string]$Raw
    $x = $x.Trim().ToLowerInvariant().Replace("_", "-").Replace(" ", "-")
    switch ($x) {
        "rozpocznij-testy" { return "start-tests" }
        "przeprowadz-testy" { return "run-tests" }
        "testy-start" { return "start-tests" }
        "testy-run" { return "run-tests" }
        default { return $x }
    }
}

function Build-TextSummary {
    param([hashtable]$Summary)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("NIGHTLY TESTBOOK")
    $lines.Add("run_id: $($Summary.run_id)")
    $lines.Add("status: $($Summary.status)")
    $lines.Add("started_at_utc: $($Summary.started_at_utc)")
    $lines.Add("finished_at_utc: $($Summary.finished_at_utc)")
    $lines.Add("lookback_hours: $($Summary.config.lookback_hours)")
    $lines.Add("latency_duration_min: $($Summary.config.latency_duration_min)")
    $lines.Add("")
    $lines.Add("STEPS:")
    foreach ($s in @($Summary.steps)) {
        $lines.Add(("- {0} | status={1} rc={2} duration_s={3} log={4}" -f $s.name, $s.status, $s.exit_code, $s.duration_sec, $s.log_path))
    }
    if (@($Summary.outputs).Count -gt 0) {
        $lines.Add("")
        $lines.Add("OUTPUTS:")
        foreach ($k in $Summary.outputs.Keys) {
            $lines.Add(("- {0}: {1}" -f $k, $Summary.outputs[$k]))
        }
    }
    return ($lines -join "`r`n") + "`r`n"
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Exe,
        [string[]]$CmdArgs,
        [string]$LogPath
    )
    $stepStart = Get-Date
    $stepStartIso = $stepStart.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $status = "PASS"
    $exitCode = 0
    $errorText = ""
    $stdOut = ($LogPath + ".stdout")
    $stdErr = ($LogPath + ".stderr")

    try {
        if (Test-Path -LiteralPath $stdOut) { Remove-Item -LiteralPath $stdOut -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stdErr) { Remove-Item -LiteralPath $stdErr -Force -ErrorAction SilentlyContinue }

        $proc = Start-Process `
            -FilePath $Exe `
            -ArgumentList $CmdArgs `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdOut `
            -RedirectStandardError $stdErr

        $exitCode = [int]$proc.ExitCode
        $buf = New-Object System.Collections.Generic.List[string]
        if (Test-Path -LiteralPath $stdOut) {
            foreach ($ln in (Get-Content -LiteralPath $stdOut -ErrorAction SilentlyContinue)) { $buf.Add([string]$ln) }
        }
        if (Test-Path -LiteralPath $stdErr) {
            $errLines = Get-Content -LiteralPath $stdErr -ErrorAction SilentlyContinue
            if (@($errLines).Count -gt 0) {
                if ($buf.Count -gt 0) { $buf.Add("--- STDERR ---") }
                foreach ($ln in $errLines) { $buf.Add([string]$ln) }
            }
        }
        Set-Content -LiteralPath $LogPath -Encoding UTF8 -Value $buf
        if (Test-Path -LiteralPath $stdOut) { Remove-Item -LiteralPath $stdOut -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stdErr) { Remove-Item -LiteralPath $stdErr -Force -ErrorAction SilentlyContinue }

        if ($exitCode -ne 0) {
            throw "Step failed with rc=$exitCode"
        }
    } catch {
        $status = "FAIL"
        if ($exitCode -eq 0) {
            $exitCode = 1
        }
        $errorText = $_.Exception.Message
    }

    $stepEnd = Get-Date
    $durationSec = [Math]::Round(($stepEnd - $stepStart).TotalSeconds, 3)
    $result = [ordered]@{
        name = $Name
        status = $status
        exit_code = [int]$exitCode
        started_at_utc = $stepStartIso
        finished_at_utc = $stepEnd.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        duration_sec = $durationSec
        command = ($Exe + " " + ($CmdArgs -join " "))
        log_path = $LogPath
        error = $errorText
    }
    return $result
}

$mode = Normalize-Action -Raw $Action
$allowed = @("start-tests", "run-tests", "status")
if ($allowed -notcontains $mode) {
    throw "Unsupported Action='$Action'. Allowed: start-tests | run-tests | status (or: rozpocznij testy | przeprowadz testy)."
}

$reportRoot = Join-Path $LabDataRoot "reports\nightly_tests"
$runRoot = Join-Path $LabDataRoot "run"
$latestJson = Join-Path $reportRoot "nightly_testbook_latest.json"
$latestTxt = Join-Path $reportRoot "nightly_testbook_latest.txt"
$registryJsonl = Join-Path $runRoot "nightly_testbook_registry.jsonl"
$queueJson = Join-Path $runRoot "nightly_testbook_queue.json"

Ensure-Dir -Path $reportRoot
Ensure-Dir -Path $runRoot

if ($mode -eq "status") {
    if (-not (Test-Path -LiteralPath $latestJson)) {
        Write-Host "NIGHTLY_TESTBOOK status=NO_DATA latest=$latestJson"
        exit 0
    }
    Get-Content -LiteralPath $latestJson -Raw -Encoding UTF8 | Write-Output
    exit 0
}

if ($mode -eq "start-tests") {
    $stamp = Utc-Stamp
    $plan = [ordered]@{
        schema = "oanda.mt5.nightly_testbook.plan.v1"
        requested_at_utc = Utc-IsoNow
        requested_by = $env:USERNAME
        run_id = "nightly_$stamp"
        root = $Root
        lab_data_root = $LabDataRoot
        config = [ordered]@{
            lookback_hours = [int]$LookbackHours
            latency_duration_min = [int]$LatencyDurationMin
            require_idle = [bool]$RequireIdle.IsPresent
            idle_threshold_sec = [int]$IdleThresholdSec
            require_outside_active = [bool]$RequireOutsideActive.IsPresent
            force = [bool]$Force.IsPresent
            continue_on_error = [bool]$ContinueOnError
        }
        steps = @(
            "compile_smoke",
            "unit_tests_core_plus_black_swan",
            "stage1_shadow_plus_cycle",
            "runtime_latency_audit",
            "black_swan_v2_runtime_report_24h",
            "active_checklist_snapshot"
        )
        status = "QUEUED"
    }
    Write-JsonFile -Path $queueJson -Payload $plan
    Append-Jsonl -Path $registryJsonl -Payload ([ordered]@{
        ts_utc = Utc-IsoNow
        event = "QUEUED"
        run_id = $plan.run_id
        mode = "start-tests"
        queue_path = $queueJson
    })
    Write-Host "NIGHTLY_TESTBOOK queued run_id=$($plan.run_id) queue=$queueJson"
    exit 0
}

$runStamp = Utc-Stamp
$runId = "nightly_$runStamp"
$runDir = Join-Path $reportRoot $runId
$logsDir = Join-Path $runDir "logs"
Ensure-Dir -Path $runDir
Ensure-Dir -Path $logsDir

$summary = [ordered]@{
    schema = "oanda.mt5.nightly_testbook.run.v1"
    run_id = $runId
    started_at_utc = Utc-IsoNow
    finished_at_utc = ""
    status = "RUNNING"
    root = $Root
    lab_data_root = $LabDataRoot
    config = [ordered]@{
        lookback_hours = [int]$LookbackHours
        latency_duration_min = [int]$LatencyDurationMin
        require_idle = [bool]$RequireIdle.IsPresent
        idle_threshold_sec = [int]$IdleThresholdSec
        require_outside_active = [bool]$RequireOutsideActive.IsPresent
        force = [bool]$Force.IsPresent
        continue_on_error = [bool]$ContinueOnError
    }
    steps = @()
    outputs = [ordered]@{
        run_dir = $runDir
    }
}

Append-Jsonl -Path $registryJsonl -Payload ([ordered]@{
    ts_utc = Utc-IsoNow
    event = "STARTED"
    run_id = $runId
    summary_path = (Join-Path $runDir "nightly_testbook_$runStamp.json")
})

function Add-Step {
    param([hashtable]$StepResult)
    $summary.steps += $StepResult
    if ($StepResult.status -eq "FAIL" -and (-not $ContinueOnError)) {
        throw "Stopped on failed step: $($StepResult.name)"
    }
}

$compileReport = Join-Path $runDir ("compile_report_" + $runStamp + ".json")
$step1 = Invoke-Step -Name "compile_smoke" -Exe "py" -CmdArgs @(
    "-3.12",
    "-B",
    (Join-Path $Root "TOOLS\smoke_compile_v6_2.py"),
    "--root", $Root,
    "--out", $compileReport
) -LogPath (Join-Path $logsDir "01_compile_smoke.log")
Add-Step -StepResult $step1
$summary.outputs["compile_report"] = $compileReport

$step2 = Invoke-Step -Name "unit_tests_core_plus_black_swan" -Exe "py" -CmdArgs @(
    "-3.12",
    "-m",
    "unittest",
    "tests.test_black_swan_guard",
    "tests.test_capital_protection_black_swan_guard_v2",
    "tests.test_runtime_housekeeping",
    "tests.test_api_contracts",
    "-v"
) -LogPath (Join-Path $logsDir "02_unit_tests.log")
Add-Step -StepResult $step2

$shadowArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $Root "TOOLS\run_stage1_shadow_plus_cycle.ps1"),
    "-Root", $Root,
    "-LabDataRoot", $LabDataRoot,
    "-LookbackHours", "$LookbackHours",
    "-FocusGroup", "FX",
    "-CoverageScope", "active",
    "-ShadowDryRun"
)
if ($RequireIdle.IsPresent) {
    $shadowArgs += @("-RequireIdle", "-IdleThresholdSec", "$IdleThresholdSec")
}
if ($RequireOutsideActive.IsPresent) {
    $shadowArgs += "-RequireOutsideActive"
}
if ($Force.IsPresent) {
    $shadowArgs += "-Force"
}
$step3 = Invoke-Step -Name "stage1_shadow_plus_cycle" -Exe "powershell" -CmdArgs $shadowArgs -LogPath (Join-Path $logsDir "03_stage1_shadow_plus.log")
Add-Step -StepResult $step3
$summary.outputs["stage1_shadow_plus_latest"] = (Join-Path $LabDataRoot "reports\stage1\stage1_shadow_plus_cycle_latest.json")

$latArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $Root "TOOLS\run_runtime_latency_audit.ps1"),
    "-Root", $Root,
    "-DurationMin", "$LatencyDurationMin",
    "-Profile", "safety_only"
)
if ($RequireIdle.IsPresent) {
    $latArgs += @("-RequireIdle", "-IdleThresholdSec", "$IdleThresholdSec")
}
if ($RequireOutsideActive.IsPresent) {
    $latArgs += "-RequireOutsideActive"
}
if ($Force.IsPresent) {
    $latArgs += "-Force"
}
$step4 = Invoke-Step -Name "runtime_latency_audit" -Exe "powershell" -CmdArgs $latArgs -LogPath (Join-Path $logsDir "04_runtime_latency_audit.log")
Add-Step -StepResult $step4
$summary.outputs["latency_latest_dir"] = (Join-Path $Root "EVIDENCE\runtime_latency")

$bsReport = Join-Path $runDir ("black_swan_v2_runtime_" + $runStamp + ".json")
$step5 = Invoke-Step -Name "black_swan_v2_runtime_report_24h" -Exe "py" -CmdArgs @(
    "-3.12",
    "-B",
    (Join-Path $Root "TOOLS\black_swan_v2_runtime_report.py"),
    "--root", $Root,
    "--hours", "24",
    "--out-report", $bsReport
) -LogPath (Join-Path $logsDir "05_black_swan_v2_report.log")
Add-Step -StepResult $step5
$summary.outputs["black_swan_v2_report"] = $bsReport

$runtimeKpiOut = Join-Path $runDir ("runtime_kpi_snapshot_" + $runStamp + ".json")
$step6 = Invoke-Step -Name "runtime_kpi_snapshot" -Exe "py" -CmdArgs @(
    "-3.12",
    "-B",
    (Join-Path $Root "TOOLS\runtime_kpi_snapshot.py"),
    "--root", $Root,
    "--hours", "24",
    "--out", $runtimeKpiOut
) -LogPath (Join-Path $logsDir "06_runtime_kpi_snapshot.log")
Add-Step -StepResult $step6
$summary.outputs["runtime_kpi_snapshot"] = $runtimeKpiOut

$failed = @($summary.steps | Where-Object { $_.status -eq "FAIL" }).Count
$summary.status = if ($failed -eq 0) { "PASS" } else { "PARTIAL_FAIL" }
$summary.finished_at_utc = Utc-IsoNow

$outJson = Join-Path $runDir ("nightly_testbook_" + $runStamp + ".json")
$outTxt = [System.IO.Path]::ChangeExtension($outJson, ".txt")
Write-JsonFile -Path $outJson -Payload $summary
$txt = Build-TextSummary -Summary $summary
Set-Content -LiteralPath $outTxt -Encoding UTF8 -Value $txt
Copy-Item -LiteralPath $outJson -Destination $latestJson -Force
Copy-Item -LiteralPath $outTxt -Destination $latestTxt -Force

Append-Jsonl -Path $registryJsonl -Payload ([ordered]@{
    ts_utc = Utc-IsoNow
    event = "FINISHED"
    run_id = $runId
    status = $summary.status
    failed_steps = [int]$failed
    summary_json = $outJson
    summary_txt = $outTxt
})

Write-Host "NIGHTLY_TESTBOOK_DONE run_id=$runId status=$($summary.status) failed_steps=$failed summary=$outJson"
if ($failed -gt 0) {
    exit 2
}
exit 0
