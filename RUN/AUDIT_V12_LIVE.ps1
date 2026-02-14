param(
    [string]$Root = "",
    [string]$EvidenceRoot = "",
    [string]$RunId = "",
    [int]$PreflightLoops = 1,
    [string]$SyncTarget = "C:\agentkotweight\EVIDENCE",
    [switch]$NoSync,
    [switch]$SkipPreflight,
    [switch]$SkipOffline,
    [switch]$SkipTraining,
    [switch]$SkipSecretsScan,
    [switch]$SkipReport
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $Root "EVIDENCE\audit_v12_live"
} elseif (-not [System.IO.Path]::IsPathRooted($EvidenceRoot)) {
    $EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $Root $EvidenceRoot))
} else {
    $EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = Get-Date -Format "yyyyMMdd_HHmmss"
}

if ($PreflightLoops -lt 1) {
    $PreflightLoops = 1
}

$runDir = Join-Path $EvidenceRoot $RunId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$pipelineRunLog = Join-Path $runDir "pipeline_runlog.jsonl"
$pipelineVerdictJson = Join-Path $runDir "pipeline_verdict.json"
$pipelineVerdictTxt = Join-Path $runDir "pipeline_verdict.txt"
$overallExit = 0
$stepMeta = [ordered]@{}

function To-RelPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($Root.Length).TrimStart([char]'\', [char]'/') -replace '\\','/'
    }
    return $full
}

function Append-Jsonl {
    param([string]$Path, [hashtable]$Record)
    ($Record | ConvertTo-Json -Compress -Depth 20) | Add-Content -Encoding UTF8 $Path
}

function Append-RunLog {
    param(
        [string]$Event,
        [hashtable]$Fields = @{}
    )
    $record = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        event = $Event
        run_id = $RunId
    }
    foreach ($k in $Fields.Keys) { $record[$k] = $Fields[$k] }
    Append-Jsonl -Path $pipelineRunLog -Record $record
}

function Mark-StepSkipped {
    param(
        [string]$Name,
        [string]$Reason,
        [string]$Command = ""
    )
    $logPath = Join-Path $runDir ("pipeline_{0}.txt" -f $Name)
    "COMMAND: $Command" | Set-Content -Encoding UTF8 $logPath
    "SKIPPED: $Reason" | Add-Content -Encoding UTF8 $logPath
    "EXIT_CODE: 0" | Add-Content -Encoding UTF8 $logPath

    $stepMeta[$Name] = [ordered]@{
        exit_code = 0
        skipped = $true
        reason = $Reason
        command = $Command
        log = (To-RelPath $logPath)
    }

    Append-RunLog -Event "step_skipped" -Fields @{
        step = $Name
        reason = $Reason
    }
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Command
    )

    $logPath = Join-Path $runDir ("pipeline_{0}.txt" -f $Name)
    "COMMAND: $Command" | Set-Content -Encoding UTF8 $logPath
    Append-RunLog -Event "step_start" -Fields @{ step = $Name; command = $Command }

    $stdoutPath = Join-Path $env:TEMP ("audit_v12_live_{0}_{1}.stdout.tmp" -f $Name, ([guid]::NewGuid().ToString("N")))
    $stderrPath = Join-Path $env:TEMP ("audit_v12_live_{0}_{1}.stderr.tmp" -f $Name, ([guid]::NewGuid().ToString("N")))

    if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }
    if (Test-Path $stderrPath) { Remove-Item $stderrPath -Force }

    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/d", "/c", $Command -WorkingDirectory $Root -Wait -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $code = [int]$proc.ExitCode

    if (Test-Path $stdoutPath) {
        Get-Content $stdoutPath | Add-Content -Encoding UTF8 $logPath
        Remove-Item $stdoutPath -Force
    }
    if (Test-Path $stderrPath) {
        Get-Content $stderrPath | Add-Content -Encoding UTF8 $logPath
        Remove-Item $stderrPath -Force
    }
    "EXIT_CODE: $code" | Add-Content -Encoding UTF8 $logPath

    $stepMeta[$Name] = [ordered]@{
        exit_code = $code
        skipped = $false
        command = $Command
        log = (To-RelPath $logPath)
    }

    if ($code -eq 0) {
        Append-RunLog -Event "step_ok" -Fields @{ step = $Name }
    } else {
        Append-RunLog -Event "step_fail" -Fields @{ step = $Name; exit_code = $code }
        if ($script:overallExit -eq 0) {
            $script:overallExit = $code
        }
    }
}

Write-Host "[AUDIT_V12_LIVE] Root=$Root"
Write-Host "[AUDIT_V12_LIVE] EvidenceRoot=$EvidenceRoot"
Write-Host "[AUDIT_V12_LIVE] RunId=$RunId"
Write-Host "[AUDIT_V12_LIVE] RunDir=$runDir"

Append-RunLog -Event "audit_v12_live_start" -Fields @{
    root = $Root
    evidence_root = $EvidenceRoot
    run_dir = (To-RelPath $runDir)
}

if ($SkipPreflight) {
    Mark-StepSkipped -Name "00_preflight_safe" -Reason "switch SkipPreflight"
} else {
    $preflightEvidence = Join-Path $runDir "preflight"
    $cmdPreflight = "powershell -NoProfile -ExecutionPolicy Bypass -File RUN\\PREFLIGHT_SAFE.ps1 -Root `"$Root`" -Evidence `"$preflightEvidence`" -Loops $PreflightLoops -NoSync"
    Invoke-Step -Name "00_preflight_safe" -Command $cmdPreflight
}

if ($SkipOffline) {
    Mark-StepSkipped -Name "01_audit_offline" -Reason "switch SkipOffline"
} else {
    $offlineEvidence = Join-Path $runDir "offline"
    $cmdOffline = "powershell -NoProfile -ExecutionPolicy Bypass -File RUN\\AUDIT_OFFLINE.ps1 -Root `"$Root`" -Evidence `"$offlineEvidence`" -NoSync"
    Invoke-Step -Name "01_audit_offline" -Command $cmdOffline
}

if ($SkipTraining) {
    Mark-StepSkipped -Name "02_audit_training_offline" -Reason "switch SkipTraining"
} else {
    $trainingEvidence = Join-Path $runDir "training"
    $cmdTraining = "powershell -NoProfile -ExecutionPolicy Bypass -File RUN\\AUDIT_TRAINING_OFFLINE.ps1 -Root `"$Root`" -Evidence `"$trainingEvidence`" -NoSync"
    Invoke-Step -Name "02_audit_training_offline" -Command $cmdTraining
}

if ($SkipSecretsScan) {
    Mark-StepSkipped -Name "03_secrets_scan_repo_only" -Reason "switch SkipSecretsScan"
} else {
    $extrasDir = Join-Path $runDir "extras"
    New-Item -ItemType Directory -Force -Path $extrasDir | Out-Null
    $secretsReport = Join-Path $extrasDir "secrets_scan_report_repo_only.json"
    $cmdSecrets = "python TOOLS\\secrets_scan.py --root `"$Root`" --report `"$secretsReport`""
    Invoke-Step -Name "03_secrets_scan_repo_only" -Command $cmdSecrets
}

if ($SkipReport) {
    Mark-StepSkipped -Name "04_generate_report_v1_2" -Reason "switch SkipReport"
} else {
    $cmdReport = "powershell -NoProfile -ExecutionPolicy Bypass -File RUN\\GENERATE_AUDIT_REPORT_V1_2.ps1 -Root `"$Root`" -EvidenceRoot `"$EvidenceRoot`" -RunId `"$RunId`""
    Invoke-Step -Name "04_generate_report_v1_2" -Command $cmdReport
}

if ($NoSync) {
    Mark-StepSkipped -Name "05_sync_evidence" -Reason "switch NoSync"
} else {
    $syncScript = Join-Path $PSScriptRoot "SYNC_EVIDENCE.ps1"
    $syncSource = Join-Path $Root "EVIDENCE"
    if (-not (Test-Path $syncScript -PathType Leaf)) {
        $syncLogPath = Join-Path $runDir "pipeline_05_sync_evidence.txt"
        "SYNC_EVIDENCE script missing: $syncScript" | Set-Content -Encoding UTF8 $syncLogPath
        "EXIT_CODE: 91" | Add-Content -Encoding UTF8 $syncLogPath

        $stepMeta["05_sync_evidence"] = [ordered]@{
            exit_code = 91
            skipped = $false
            command = "SYNC_MISSING"
            log = (To-RelPath $syncLogPath)
        }
        Append-RunLog -Event "step_fail" -Fields @{ step = "05_sync_evidence"; exit_code = 91 }
        if ($overallExit -eq 0) { $overallExit = 91 }
    } else {
        $cmdSync = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$syncScript`" -SourceEvidence `"$syncSource`" -TargetEvidence `"$SyncTarget`""
        Invoke-Step -Name "05_sync_evidence" -Command $cmdSync
    }
}

$verdict = [ordered]@{
    run_id = $RunId
    run_dir = (To-RelPath $runDir)
    final_exit_code = $overallExit
    status = $(if ($overallExit -eq 0) { "PASS" } else { "FAIL" })
    finished_utc = (Get-Date).ToUniversalTime().ToString("o")
    steps = $stepMeta
}

$verdict | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $pipelineVerdictJson
"FINAL_EXIT_CODE=$overallExit" | Set-Content -Encoding UTF8 $pipelineVerdictTxt
"STATUS=$($verdict.status)" | Add-Content -Encoding UTF8 $pipelineVerdictTxt
"RUN_ID=$RunId" | Add-Content -Encoding UTF8 $pipelineVerdictTxt

Append-RunLog -Event "audit_v12_live_end" -Fields @{
    exit_code = $overallExit
    status = $verdict.status
}

Write-Host "[AUDIT_V12_LIVE] ExitCode=$overallExit"
exit $overallExit
