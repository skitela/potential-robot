param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$ChecklistTimeoutHours = 18,
    [int]$PostUnlockMinutes = 30,
    [int]$PostUnlockPollSec = 5,
    [string]$DesktopPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RootPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $Path).Path
}

function Resolve-DesktopPath {
    param([string]$ExplicitPath)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return $ExplicitPath
    }
    try {
        return [Environment]::GetFolderPath("Desktop")
    } catch {
        return ""
    }
}

function Get-LatestByPattern {
    param(
        [string]$Dir,
        [string]$Pattern
    )
    if (-not (Test-Path $Dir)) { return $null }
    return (Get-ChildItem -Path $Dir -File -Filter $Pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Safe-ReadJson {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        return (Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        try { return (Get-Content -Path $Path -Raw -Encoding Unicode | ConvertFrom-Json) } catch { return $null }
    }
}

$runtimeRoot = Resolve-RootPath -Path $Root
$desktop = Resolve-DesktopPath -ExplicitPath $DesktopPath
$runDir = Join-Path $runtimeRoot "RUN"
$diagDir = Join-Path $runDir "DIAG_REPORTS"
$activeDir = Join-Path $runtimeRoot "EVIDENCE\ACTIVE_CHECKS"
$jobsDir = Join-Path $runDir "monitor_jobs"
New-Item -Path $jobsDir -ItemType Directory -Force | Out-Null

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$statusPath = Join-Path $jobsDir "fx_runtime_audit_status.json"
$runnerLog = Join-Path $jobsDir ("fx_runtime_audit_" + $stamp + ".log")

Start-Transcript -Path $runnerLog -Append | Out-Null

try {
    Write-Host "[FX_AUDIT] start runtimeRoot=$runtimeRoot"
    $status = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        stage = "STARTED"
        runtime_root = $runtimeRoot
        checklist_timeout_hours = $ChecklistTimeoutHours
        post_unlock_minutes = $PostUnlockMinutes
        post_unlock_poll_sec = $PostUnlockPollSec
        result = "RUNNING"
        details = @{}
    }
    $status | ConvertTo-Json -Depth 8 | Set-Content -Path $statusPath -Encoding UTF8

    $checklistScript = Join-Path $runtimeRoot "TOOLS\auto_active_checklist.ps1"
    if (-not (Test-Path $checklistScript)) {
        throw "Missing checklist script: $checklistScript"
    }

    Write-Host "[FX_AUDIT] waiting for next ACTIVE window (single-pass checklist)..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $checklistScript -Root $runtimeRoot -Mode single -PollSec 5 -TimeoutHours $ChecklistTimeoutHours
    $checkRc = $LASTEXITCODE
    if ($checkRc -ne 0) {
        throw "auto_active_checklist returned rc=$checkRc"
    }

    $activeJson = Get-LatestByPattern -Dir $activeDir -Pattern "active_checklist_*.json"
    $activeTxt = Get-LatestByPattern -Dir $activeDir -Pattern "active_checklist_*.txt"

    Write-Host "[FX_AUDIT] checklist pass captured; running post-unlock entry audit..."
    & python (Join-Path $runtimeRoot "TOOLS\post_unlock_entry_test.py") --minutes $PostUnlockMinutes --poll-sec $PostUnlockPollSec
    $postRc = $LASTEXITCODE
    if ($postRc -ne 0 -and $postRc -ne 4) {
        Write-Host "[FX_AUDIT] post_unlock_entry_test rc=$postRc (continuing with report)"
    }

    $postJson = Get-LatestByPattern -Dir $diagDir -Pattern "POST_UNLOCK_ENTRY_TEST_*.json"
    $postTxt = Get-LatestByPattern -Dir $diagDir -Pattern "POST_UNLOCK_ENTRY_TEST_*.txt"

    $noLivePath = Join-Path $runtimeRoot "EVIDENCE\no_live_drift_check.json"
    $preflightPath = Join-Path $runtimeRoot "EVIDENCE\asia_symbol_preflight.json"
    $symSelectPath = Join-Path $runtimeRoot "RUN\mt5_symbol_select_report.json"

    $activeObj = if ($activeJson) { Safe-ReadJson -Path $activeJson.FullName } else { $null }
    $postObj = if ($postJson) { Safe-ReadJson -Path $postJson.FullName } else { $null }
    $noLiveObj = Safe-ReadJson -Path $noLivePath

    $fxRows = @()
    if ($noLiveObj -and $noLiveObj.rows) {
        foreach($r in $noLiveObj.rows) {
            if ([string]$r.group -eq "FX") { $fxRows += $r }
        }
    }

    $reportLines = @()
    $reportLines += "===== FX_RUNTIME_AUDIT_NEXT_WINDOW ====="
    $reportLines += ("generated_utc: " + (Get-Date).ToUniversalTime().ToString("o"))
    $reportLines += ("runtime_root: " + $runtimeRoot)
    $reportLines += ""
    $reportLines += "[CHECKLIST]"
    $reportLines += ("active_checklist_json: " + $(if($activeJson){$activeJson.FullName}else{"MISSING"}))
    $reportLines += ("active_checklist_txt: " + $(if($activeTxt){$activeTxt.FullName}else{"MISSING"}))
    if ($activeObj) {
        $reportLines += ("window_id: " + [string]$activeObj.trigger.window_id)
        $reportLines += ("system_control_status_pass: " + [string]$activeObj.system_control_status_pass)
        $reportLines += ("verdict_light: " + [string]$activeObj.snapshot.verdict_light)
        $reportLines += ("learner_qa_light: " + [string]$activeObj.snapshot.learner_qa_light)
        $reportLines += ("latest_entry_signal: " + [string]$activeObj.snapshot.latest_entry_signal)
        $reportLines += ("latest_order: " + [string]$activeObj.snapshot.latest_order)
    }
    $reportLines += ""
    $reportLines += "[POST_UNLOCK_ENTRY_TEST]"
    $reportLines += ("post_unlock_json: " + $(if($postJson){$postJson.FullName}else{"MISSING"}))
    $reportLines += ("post_unlock_txt: " + $(if($postTxt){$postTxt.FullName}else{"MISSING"}))
    if ($postObj) {
        $reportLines += ("verdict: " + [string]$postObj.verdict)
        $reportLines += ("reason: " + [string]$postObj.reason)
        $reportLines += ("entry_signal: " + [string]$postObj.counts.entry_signal)
        $reportLines += ("dispatch: " + [string]$postObj.counts.dispatch)
        $reportLines += ("order_success: " + [string]$postObj.counts.order_success)
        $reportLines += ("order_failed: " + [string]$postObj.counts.order_failed)
    }
    $reportLines += ""
    $reportLines += "[LIVE_DRIFT_FX_ROWS]"
    $reportLines += ("no_live_drift_path: " + $noLivePath)
    foreach($r in $fxRows){
        $reportLines += ("- " + [string]$r.symbol_canonical + " | live=" + [string]$r.symbol_live_enabled + " | reason=" + [string]$r.reason_code + " | preflight_ok=" + [string]$r.preflight_ok)
    }
    if ($fxRows.Count -eq 0) {
        $reportLines += "- MISSING_OR_EMPTY"
    }
    $reportLines += ""
    $reportLines += "[ARTIFACTS]"
    $reportLines += ("preflight_path: " + $preflightPath)
    $reportLines += ("symbol_select_path: " + $symSelectPath)
    $reportLines += ("runner_log: " + $runnerLog)

    $reportName = "odpowiedź monitoring FX runtime.txt"
    $reportOut = if (-not [string]::IsNullOrWhiteSpace($desktop) -and (Test-Path $desktop)) {
        Join-Path $desktop $reportName
    } else {
        Join-Path $runtimeRoot $reportName
    }
    $reportLines -join [Environment]::NewLine | Set-Content -Path $reportOut -Encoding UTF8

    $status.stage = "DONE"
    $status.result = "PASS"
    $status.details = [ordered]@{
        active_checklist_json = $(if($activeJson){$activeJson.FullName}else{"MISSING"})
        post_unlock_json = $(if($postJson){$postJson.FullName}else{"MISSING"})
        report_out = $reportOut
    }
    $status | ConvertTo-Json -Depth 8 | Set-Content -Path $statusPath -Encoding UTF8

    Write-Host "[FX_AUDIT] done report=$reportOut"
}
catch {
    $err = $_.Exception.Message
    Write-Host "[FX_AUDIT] FAIL: $err"
    $fail = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        stage = "FAILED"
        result = "FAIL"
        error = $err
        runtime_root = $runtimeRoot
        runner_log = $runnerLog
    }
    $fail | ConvertTo-Json -Depth 8 | Set-Content -Path $statusPath -Encoding UTF8
    exit 2
}
finally {
    Stop-Transcript | Out-Null
}

exit 0
