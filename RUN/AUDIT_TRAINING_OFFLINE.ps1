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
    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $Evidence = Join-Path $Root "EVIDENCE\training_audit\$runId"
} elseif (-not [System.IO.Path]::IsPathRooted($Evidence)) {
    $Evidence = [System.IO.Path]::GetFullPath((Join-Path $Root $Evidence))
} else {
    $Evidence = [System.IO.Path]::GetFullPath($Evidence)
}

New-Item -ItemType Directory -Force -Path $Evidence | Out-Null

$env:OANDA_RUN_MODE = "OFFLINE"
$env:OFFLINE_DETERMINISTIC = "1"
$env:SCUD_ALLOW_RSS = "0"
$env:INFOBOT_EMAIL_ENABLED = "0"
$env:INFOBOT_EMAIL_DAILY_ENABLED = "0"
$env:INFOBOT_EMAIL_WEEKLY_ENABLED = "0"
$env:INFOBOT_EMAIL_ALIVE_ENABLED = "0"
$env:REPAIR_AUTO_HOTFIX = "0"

$overallExit = 0

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Command,
        [switch]$Optional
    )

    $log = Join-Path $Evidence "$Name.txt"
    "COMMAND: $Command" | Set-Content -Encoding UTF8 $log

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

    if ($Optional -and $code -ne 0) {
        "OPTIONAL_STEP_FAILED: true" | Add-Content -Encoding UTF8 $log
        return
    }

    if ($code -ne 0 -and $script:overallExit -eq 0) {
        $script:overallExit = $code
    }
}

Write-Host "[AUDIT_TRAINING_OFFLINE] Root=$Root"
Write-Host "[AUDIT_TRAINING_OFFLINE] Evidence=$Evidence"

$compileJson = Join-Path $Evidence "smoke_compile_report.json"
$cmdCompile = "python TOOLS\\smoke_compile_v6_2.py --root `"$Root`" --out `"$compileJson`""
Invoke-Step -Name "01_compile" -Command $cmdCompile

$cmdTestsCore = "python -m unittest tests.test_training_quality tests.test_risk_policy_defaults tests.test_oanda_limits_guard tests.test_contract_run_v2 tests.test_runtime_mines_vF -v"
Invoke-Step -Name "02_tests_training" -Command $cmdTestsCore

$cmdTestsOpt = "python -m unittest tests.test_oanda_limits_integration -v"
Invoke-Step -Name "02b_tests_oanda_limits_integration" -Command $cmdTestsOpt -Optional

$env:TRAINING_EVID_DIR = (Join-Path $Evidence "learner")
Invoke-Step -Name "03_learner_once" -Command "python BIN\\learner_offline.py once"
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
        if ($overallExit -eq 0) {
            $overallExit = 91
        }
    }
}

"FINAL_EXIT_CODE=$overallExit" | Set-Content -Encoding UTF8 (Join-Path $Evidence "verdict.txt")
Write-Host "[AUDIT_TRAINING_OFFLINE] ExitCode=$overallExit"
exit $overallExit
