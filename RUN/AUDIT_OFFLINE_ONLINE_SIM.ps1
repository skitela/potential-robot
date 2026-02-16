param(
    [string]$Root = "",
    [string]$EvidenceRoot = "",
    [string]$RunId = "",
    [string]$KeyLabel = "OANDAKEY_OFFLINE_SIM",
    [string]$Mt5Path = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [switch]$SkipUnitTests,
    [switch]$SkipLearner
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $Root "EVIDENCE\offline_online_sim"
} elseif (-not [System.IO.Path]::IsPathRooted($EvidenceRoot)) {
    $EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $Root $EvidenceRoot))
} else {
    $EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = Get-Date -Format "yyyyMMdd_HHmmss"
}

$runDir = Join-Path $EvidenceRoot $RunId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$runLogPath = Join-Path $runDir "runlog.jsonl"
$summaryJson = Join-Path $runDir "summary.json"
$summaryTxt = Join-Path $runDir "summary.txt"

$overallExit = 0
$steps = [ordered]@{}

function To-RelPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($Root.Length).TrimStart([char]'\', [char]'/') -replace '\\', '/'
    }
    return $full
}

function Append-Jsonl {
    param([string]$Path, [hashtable]$Record)
    ($Record | ConvertTo-Json -Compress -Depth 20) | Add-Content -Encoding UTF8 $Path
}

function Append-RunLog {
    param([string]$Event, [hashtable]$Fields = @{})
    $rec = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        event = $Event
        run_id = $RunId
    }
    foreach ($k in $Fields.Keys) { $rec[$k] = $Fields[$k] }
    Append-Jsonl -Path $runLogPath -Record $rec
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Command
    )
    $logPath = Join-Path $runDir ("step_{0}.txt" -f $Name)
    "COMMAND: $Command" | Set-Content -Encoding UTF8 $logPath
    Append-RunLog -Event "step_start" -Fields @{ step = $Name; command = $Command }

    $stdoutPath = Join-Path $env:TEMP ("offline_online_sim_{0}_{1}.stdout.tmp" -f $Name, ([guid]::NewGuid().ToString("N")))
    $stderrPath = Join-Path $env:TEMP ("offline_online_sim_{0}_{1}.stderr.tmp" -f $Name, ([guid]::NewGuid().ToString("N")))
    if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }
    if (Test-Path $stderrPath) { Remove-Item $stderrPath -Force }

    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/d", "/c", $Command `
        -WorkingDirectory $Root -Wait -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
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

    $steps[$Name] = [ordered]@{
        exit_code = $code
        command = $Command
        log = (To-RelPath $logPath)
    }

    if ($code -eq 0) {
        Append-RunLog -Event "step_ok" -Fields @{ step = $Name }
    } else {
        Append-RunLog -Event "step_fail" -Fields @{ step = $Name; exit_code = $code }
        if ($overallExit -eq 0) { $script:overallExit = $code }
    }
}

function Invoke-CleanupBytecode {
    $name = "00_cleanup_bytecode"
    $logPath = Join-Path $runDir ("step_{0}.txt" -f $name)
    Append-RunLog -Event "step_start" -Fields @{ step = $name; mode = "internal_powershell" }
    try {
        Get-ChildItem -Path $Root -Recurse -Directory -Filter __pycache__ -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $Root -Recurse -File -Include *.pyc,*.pyo -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue

        $dirsLeft = (Get-ChildItem -Path $Root -Recurse -Directory -Filter __pycache__ -ErrorAction SilentlyContinue | Measure-Object).Count
        $pycLeft = (Get-ChildItem -Path $Root -Recurse -File -Include *.pyc,*.pyo -ErrorAction SilentlyContinue | Measure-Object).Count

        "CLEANUP: completed" | Set-Content -Encoding UTF8 $logPath
        "DIRS_LEFT: $dirsLeft" | Add-Content -Encoding UTF8 $logPath
        "PYC_LEFT: $pycLeft" | Add-Content -Encoding UTF8 $logPath

        $steps[$name] = [ordered]@{
            exit_code = 0
            command = "internal_cleanup"
            log = (To-RelPath $logPath)
            dirs_left = [int]$dirsLeft
            pyc_left = [int]$pycLeft
        }
        Append-RunLog -Event "step_ok" -Fields @{ step = $name; dirs_left = [int]$dirsLeft; pyc_left = [int]$pycLeft }
    } catch {
        $msg = $_.Exception.Message
        "CLEANUP: exception" | Set-Content -Encoding UTF8 $logPath
        "ERROR: $msg" | Add-Content -Encoding UTF8 $logPath
        $steps[$name] = [ordered]@{
            exit_code = 1
            command = "internal_cleanup"
            log = (To-RelPath $logPath)
            error = $msg
        }
        Append-RunLog -Event "step_fail" -Fields @{ step = $name; exit_code = 1; error = $msg }
        if ($overallExit -eq 0) { $script:overallExit = 1 }
    }
}

Write-Host "[AUDIT_OFFLINE_ONLINE_SIM] Root=$Root"
Write-Host "[AUDIT_OFFLINE_ONLINE_SIM] EvidenceRoot=$EvidenceRoot"
Write-Host "[AUDIT_OFFLINE_ONLINE_SIM] RunId=$RunId"
Write-Host "[AUDIT_OFFLINE_ONLINE_SIM] RunDir=$runDir"

Append-RunLog -Event "pipeline_start" -Fields @{
    root = $Root
    evidence_root = $EvidenceRoot
    run_dir = (To-RelPath $runDir)
    key_label = $KeyLabel
    mt5_path = $Mt5Path
}

Invoke-CleanupBytecode
Invoke-Step -Name "01_gate_offline" -Command "python -B TOOLS\gate_v6.py --mode offline --key-label $KeyLabel"
Invoke-Step -Name "02_diag_bundle" -Command "python -B TOOLS\diag_bundle_v6.py"

if ($SkipUnitTests) {
    $steps["03_unittest"] = [ordered]@{
        exit_code = 0
        command = "SKIPPED"
        reason = "switch SkipUnitTests"
    }
    Append-RunLog -Event "step_skipped" -Fields @{ step = "03_unittest"; reason = "SkipUnitTests" }
} else {
    Invoke-Step -Name "03_unittest" -Command "python -B -m unittest discover -s tests -p ""test_*.py"" -v"
}

if ($SkipLearner) {
    $steps["04_learner_once"] = [ordered]@{
        exit_code = 0
        command = "SKIPPED"
        reason = "switch SkipLearner"
    }
    Append-RunLog -Event "step_skipped" -Fields @{ step = "04_learner_once"; reason = "SkipLearner" }
} else {
    Invoke-Step -Name "04_learner_once" -Command "python -B BIN\learner_offline.py once"
}

Invoke-Step -Name "05_prelive_go_nogo" -Command "python -B TOOLS\prelive_go_nogo.py --root ."
Invoke-Step -Name "06_gate_online_preflight" -Command "python -B TOOLS\gate_v6.py --mode online_preflight --key-label $KeyLabel"
Invoke-Step -Name "07_online_smoke_offline_sim" -Command "python -B TOOLS\online_smoke_mt5.py --mt5-path ""$Mt5Path"" --offline-sim"
Invoke-Step -Name "08_symbols_get_audit_offline_sim" -Command "python -B TOOLS\audit_symbols_get_mt5.py --mt5-path ""$Mt5Path"" --offline-sim"

$summary = [ordered]@{
    schema = "oanda_mt5.offline_online_sim.v1"
    run_id = $RunId
    root = $Root
    run_dir = (To-RelPath $runDir)
    key_label = $KeyLabel
    mt5_path = $Mt5Path
    status = $(if ($overallExit -eq 0) { "PASS" } else { "FAIL" })
    final_exit_code = [int]$overallExit
    finished_utc = (Get-Date).ToUniversalTime().ToString("o")
    steps = $steps
}

$summary | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $summaryJson
"STATUS=$($summary.status)" | Set-Content -Encoding UTF8 $summaryTxt
"FINAL_EXIT_CODE=$($summary.final_exit_code)" | Add-Content -Encoding UTF8 $summaryTxt
"RUN_ID=$RunId" | Add-Content -Encoding UTF8 $summaryTxt
"RUN_DIR=$(To-RelPath $runDir)" | Add-Content -Encoding UTF8 $summaryTxt

Append-RunLog -Event "pipeline_end" -Fields @{ status = $summary.status; exit_code = [int]$overallExit }

Write-Host "[AUDIT_OFFLINE_ONLINE_SIM] ExitCode=$overallExit"
Write-Host "[AUDIT_OFFLINE_ONLINE_SIM] Summary=$summaryJson"
exit $overallExit

