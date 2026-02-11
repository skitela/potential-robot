param(
    [string]$Root = "",
    [string]$Evidence = "",
    [string]$SyncTarget = "C:\agentkotweight\EVIDENCE",
    [switch]$NoSync
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

if ([string]::IsNullOrWhiteSpace($Evidence)) {
    $runIdAuto = Get-Date -Format "yyyyMMdd_HHmmss"
    $Evidence = Join-Path $Root "EVIDENCE\training_audit\$runIdAuto"
} elseif (-not [System.IO.Path]::IsPathRooted($Evidence)) {
    $Evidence = [System.IO.Path]::GetFullPath((Join-Path $Root $Evidence))
} else {
    $Evidence = [System.IO.Path]::GetFullPath($Evidence)
}

New-Item -ItemType Directory -Force -Path $Evidence | Out-Null

$runId = Split-Path $Evidence -Leaf
$runLogPath = Join-Path $Evidence "runlog.jsonl"
$checkpointPath = Join-Path $Evidence "training_checkpoint.json"
$lineagePath = Join-Path $Evidence "lineage_manifest.jsonl"

$env:OANDA_RUN_MODE = "OFFLINE"
$env:OFFLINE_DETERMINISTIC = "1"
$env:SCUD_ALLOW_RSS = "0"
$env:INFOBOT_EMAIL_ENABLED = "0"
$env:INFOBOT_EMAIL_DAILY_ENABLED = "0"
$env:INFOBOT_EMAIL_WEEKLY_ENABLED = "0"
$env:INFOBOT_EMAIL_ALIVE_ENABLED = "0"
$env:REPAIR_AUTO_HOTFIX = "0"

$overallExit = 0

function Append-Jsonl {
    param([string]$Path, [hashtable]$Record)
    ($Record | ConvertTo-Json -Compress -Depth 12) | Add-Content -Encoding UTF8 $Path
}

function Append-RunLog {
    param(
        [string]$Event,
        [hashtable]$Fields = @{}
    )
    $record = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        event = $Event
        run_id = $runId
    }
    foreach ($k in $Fields.Keys) { $record[$k] = $Fields[$k] }
    Append-Jsonl -Path $runLogPath -Record $record
}

function New-CheckpointObject {
    return [ordered]@{
        run_id = $runId
        updated_utc = (Get-Date).ToUniversalTime().ToString("o")
        completed_steps = @()
        step_meta = @{}
    }
}

function Load-Checkpoint {
    if (-not (Test-Path $checkpointPath)) {
        return (New-CheckpointObject)
    }
    try {
        $raw = Get-Content $checkpointPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        $cp = New-CheckpointObject
        if ($raw.completed_steps) {
            $cp.completed_steps = @($raw.completed_steps)
        }
        if ($raw.step_meta) {
            foreach ($prop in $raw.step_meta.PSObject.Properties) {
                $cp.step_meta[$prop.Name] = [ordered]@{
                    exit_code = [int]$prop.Value.exit_code
                    completed_utc = [string]$prop.Value.completed_utc
                    command = [string]$prop.Value.command
                    log = [string]$prop.Value.log
                }
            }
        }
        return $cp
    } catch {
        return (New-CheckpointObject)
    }
}

function Save-Checkpoint {
    param([hashtable]$Checkpoint)
    $Checkpoint.updated_utc = (Get-Date).ToUniversalTime().ToString("o")
    $Checkpoint | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $checkpointPath
}

function Get-Sha256OrEmpty {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function To-RelPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($Root.Length).TrimStart([char]'\', [char]'/') -replace '\\','/'
    }
    return $full
}

function Append-Lineage {
    param(
        [string]$Step,
        [string]$Command,
        [int]$ExitCode,
        [string]$LogPath,
        [string[]]$Outputs = @(),
        [bool]$Skipped = $false
    )

    $outRecords = @()
    foreach ($item in $Outputs) {
        $candidate = $item
        if (-not [System.IO.Path]::IsPathRooted($candidate)) {
            $candidate = Join-Path $Root $candidate
        }
        $exists = Test-Path $candidate
        $rec = [ordered]@{
            path = (To-RelPath $candidate)
            exists = $exists
            sha256 = ""
            bytes = 0
        }
        if ($exists -and (Test-Path $candidate -PathType Leaf)) {
            $rec.sha256 = Get-Sha256OrEmpty $candidate
            $rec.bytes = [int64](Get-Item $candidate).Length
        }
        $outRecords += $rec
    }

    $record = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        run_id = $runId
        step = $Step
        command = $Command
        exit_code = $ExitCode
        skipped_from_checkpoint = $Skipped
        log_path = (To-RelPath $LogPath)
        log_sha256 = (Get-Sha256OrEmpty $LogPath)
        outputs = $outRecords
    }
    Append-Jsonl -Path $lineagePath -Record $record
}

$checkpoint = Load-Checkpoint

function Is-StepCompleted {
    param([string]$Name)
    if (-not $checkpoint.step_meta.ContainsKey($Name)) { return $false }
    return ([int]$checkpoint.step_meta[$Name].exit_code -eq 0)
}

function Mark-StepCompleted {
    param(
        [string]$Name,
        [string]$Command,
        [string]$LogPath,
        [int]$ExitCode
    )

    $checkpoint.step_meta[$Name] = [ordered]@{
        exit_code = $ExitCode
        completed_utc = (Get-Date).ToUniversalTime().ToString("o")
        command = $Command
        log = (To-RelPath $LogPath)
    }

    if ($checkpoint.completed_steps -notcontains $Name) {
        $checkpoint.completed_steps += $Name
    }

    Save-Checkpoint -Checkpoint $checkpoint
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Command,
        [switch]$Optional,
        [string[]]$Outputs = @()
    )

    $log = Join-Path $Evidence "$Name.txt"
    if (Is-StepCompleted -Name $Name) {
        "COMMAND: $Command" | Set-Content -Encoding UTF8 $log
        "SKIPPED_FROM_CHECKPOINT: true" | Add-Content -Encoding UTF8 $log
        "EXIT_CODE: 0" | Add-Content -Encoding UTF8 $log
        Append-RunLog -Event "step_skipped" -Fields @{ step = $Name; command = $Command }
        Append-Lineage -Step $Name -Command $Command -ExitCode 0 -LogPath $log -Outputs $Outputs -Skipped $true
        return
    }

    "COMMAND: $Command" | Set-Content -Encoding UTF8 $log
    Append-RunLog -Event "step_start" -Fields @{ step = $Name; command = $Command }

    $stdoutPath = Join-Path $env:TEMP ("audit_training_{0}_{1}.stdout.tmp" -f $Name, ([guid]::NewGuid().ToString("N")))
    $stderrPath = Join-Path $env:TEMP ("audit_training_{0}_{1}.stderr.tmp" -f $Name, ([guid]::NewGuid().ToString("N")))

    if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }
    if (Test-Path $stderrPath) { Remove-Item $stderrPath -Force }

    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/d", "/c", $Command -WorkingDirectory $Root -Wait -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $code = [int]$proc.ExitCode

    if (Test-Path $stdoutPath) {
        Get-Content $stdoutPath | Add-Content -Encoding UTF8 $log
        Remove-Item $stdoutPath -Force
    }
    if (Test-Path $stderrPath) {
        Get-Content $stderrPath | Add-Content -Encoding UTF8 $log
        Remove-Item $stderrPath -Force
    }

    "EXIT_CODE: $code" | Add-Content -Encoding UTF8 $log
    Append-Lineage -Step $Name -Command $Command -ExitCode $code -LogPath $log -Outputs $Outputs

    if ($Optional -and $code -ne 0) {
        "OPTIONAL_STEP_FAILED: true" | Add-Content -Encoding UTF8 $log
        Append-RunLog -Event "step_optional_failed" -Fields @{ step = $Name; exit_code = $code }
        return
    }

    if ($code -eq 0) {
        Mark-StepCompleted -Name $Name -Command $Command -LogPath $log -ExitCode $code
        Append-RunLog -Event "step_ok" -Fields @{ step = $Name }
    } else {
        Append-RunLog -Event "step_fail" -Fields @{ step = $Name; exit_code = $code }
    }

    if ($code -ne 0 -and $script:overallExit -eq 0) {
        $script:overallExit = $code
    }
}

Write-Host "[AUDIT_TRAINING_OFFLINE] Root=$Root"
Write-Host "[AUDIT_TRAINING_OFFLINE] Evidence=$Evidence"
Append-RunLog -Event "audit_training_start" -Fields @{ root = $Root; evidence = $Evidence }

$housekeepingJson = Join-Path $Evidence "housekeeping_report.json"
$cmdHousekeeping = "python TOOLS\\runtime_housekeeping.py --root `"$Root`" --evidence `"$housekeepingJson`" --apply --keep-runs 40 --max-single-log-mb 8"
Invoke-Step -Name "00_housekeeping" -Command $cmdHousekeeping -Outputs @($housekeepingJson)

$compileJson = Join-Path $Evidence "smoke_compile_report.json"
$cmdCompile = "python TOOLS\\smoke_compile_v6_2.py --root `"$Root`" --out `"$compileJson`""
Invoke-Step -Name "01_compile" -Command $cmdCompile -Outputs @($compileJson)

$apiContractsJson = Join-Path $Evidence "api_contracts_report.json"
$cmdApiContracts = "python TOOLS\\verify_api_contracts.py --root `"$Root`" --schema SCHEMAS\\api_contracts_v1.json --evidence `"$apiContractsJson`""
Invoke-Step -Name "01b_api_contracts" -Command $cmdApiContracts -Outputs @($apiContractsJson)

$cmdTestsCore = "python -m unittest tests.test_training_quality tests.test_risk_policy_defaults tests.test_oanda_limits_guard tests.test_contract_run_v2 tests.test_runtime_mines_vF tests.test_api_contracts tests.test_offline_network_guard tests.test_runtime_housekeeping -v"
Invoke-Step -Name "02_tests_training" -Command $cmdTestsCore

$cmdTestsOpt = "python -m unittest tests.test_oanda_limits_integration -v"
Invoke-Step -Name "02b_tests_oanda_limits_integration" -Command $cmdTestsOpt -Optional

$dependencyJson = Join-Path $Evidence "dependency_hygiene.json"
$cmdDeps = "python TOOLS\\dependency_hygiene.py --root `"$Root`" --out `"$dependencyJson`""
Invoke-Step -Name "02c_dependency_hygiene" -Command $cmdDeps -Outputs @($dependencyJson)

$env:TRAINING_EVID_DIR = (Join-Path $Evidence "learner")
Invoke-Step -Name "03_learner_once" -Command "python BIN\\learner_offline.py once" -Outputs @($env:TRAINING_EVID_DIR)
Invoke-Step -Name "04_scud_once" -Command "python BIN\\scudfab02.py once"
Invoke-Step -Name "05_import_infobot_repair" -Command "python -c `"import BIN.infobot, BIN.repair_agent; print('IMPORT_OK')`""
Invoke-Step -Name "06_gate_offline" -Command "python TOOLS\\gate_v6.py --mode offline" -Optional
Invoke-Step -Name "07_diag_bundle" -Command "python TOOLS\\diag_bundle_v6.py"

if (-not $NoSync) {
    $syncScript = Join-Path $PSScriptRoot "SYNC_EVIDENCE.ps1"
    $syncSource = Join-Path $Root "EVIDENCE"
    if (Test-Path $syncScript) {
        $cmdSync = "powershell -ExecutionPolicy Bypass -File `"$syncScript`" -SourceEvidence `"$syncSource`" -TargetEvidence `"$SyncTarget`""
        Invoke-Step -Name "08_sync_evidence" -Command $cmdSync
    } else {
        $syncLog = Join-Path $Evidence "08_sync_evidence.txt"
        "SYNC_EVIDENCE script missing: $syncScript" | Set-Content -Encoding UTF8 $syncLog
        Append-Lineage -Step "08_sync_evidence" -Command "SYNC_MISSING" -ExitCode 91 -LogPath $syncLog
        if ($overallExit -eq 0) {
            $overallExit = 91
        }
    }
}

$verdictData = [ordered]@{
    run_id = $runId
    final_exit_code = $overallExit
    status = $(if ($overallExit -eq 0) { "PASS" } else { "FAIL" })
    checkpoint = (To-RelPath $checkpointPath)
    lineage = (To-RelPath $lineagePath)
    finished_utc = (Get-Date).ToUniversalTime().ToString("o")
}
$verdictData | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $Evidence "verdict.json")
"FINAL_EXIT_CODE=$overallExit" | Set-Content -Encoding UTF8 (Join-Path $Evidence "verdict.txt")
Append-RunLog -Event "audit_training_end" -Fields @{ exit_code = $overallExit; status = $verdictData.status }

Write-Host "[AUDIT_TRAINING_OFFLINE] ExitCode=$overallExit"
exit $overallExit

