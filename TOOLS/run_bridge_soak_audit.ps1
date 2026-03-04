param(
    [int]$DurationSec = 1800,
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only"
)

$ErrorActionPreference = "Stop"
Set-Location $Root

$utcNow = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$auditPath = Join-Path $Root "LOGS\audit_trail.jsonl"
$safetyPath = Join-Path $Root "LOGS\safetybot.log"

if (-not (Test-Path $auditPath)) {
    throw "Missing audit trail log: $auditPath"
}
if (-not (Test-Path $safetyPath)) {
    throw "Missing safetybot log: $safetyPath"
}

function Test-RuntimeHealthy {
    param([string]$RuntimeRoot)
    $statusPath = Join-Path $RuntimeRoot "RUN\system_control_last.json"
    if (-not (Test-Path $statusPath)) { return $false }
    try {
        $obj = Get-Content -Raw -Encoding UTF8 $statusPath | ConvertFrom-Json
    } catch {
        return $false
    }
    if (($obj.status -ne "PASS") -or ($obj.action -ne "status")) { return $false }
    if ($null -eq $obj.components) { return $false }
    foreach ($c in $obj.components) {
        if (-not [bool]$c.running) { return $false }
    }
    return $true
}

Write-Host "RUN_BRIDGE_SOAK_AUDIT start_utc=$utcNow duration_sec=$DurationSec profile=$Profile"
& powershell -File (Join-Path $Root "TOOLS\SYSTEM_CONTROL.ps1") -Action status -Profile $Profile | Out-Host
if (-not (Test-RuntimeHealthy -RuntimeRoot $Root)) {
    Write-Host "RUN_BRIDGE_SOAK_AUDIT runtime status FAIL -> attempting start profile=$Profile"
    & powershell -File (Join-Path $Root "TOOLS\SYSTEM_CONTROL.ps1") -Action start -Profile $Profile | Out-Host
    Start-Sleep -Seconds 3
    & powershell -File (Join-Path $Root "TOOLS\SYSTEM_CONTROL.ps1") -Action status -Profile $Profile | Out-Host
}
if (-not (Test-RuntimeHealthy -RuntimeRoot $Root)) {
    throw "Runtime is not healthy (status FAIL or component not running). Aborting soak to avoid report gaps."
}

$markerDir = Join-Path $Root "EVIDENCE\bridge_audit"
New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
$markerPath = Join-Path $markerDir ("bridge_soak_window_start_" + $utcNow + ".json")

$auditOffset = (Get-Item $auditPath).Length
$safetyOffset = (Get-Item $safetyPath).Length

$baselineBridge = Get-ChildItem (Join-Path $Root "EVIDENCE\bridge_audit") -Filter "bridge_decision_audit_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$baselineStage2 = Get-ChildItem (Join-Path $Root "EVIDENCE\latency_stage2") -Filter "latency_stage2_section_profile_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

$marker = [ordered]@{
    schema = "oanda_mt5.bridge_soak_window_start.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    workspace_root_path = $Root
    runtime_profile = $Profile
    markers = [ordered]@{
        audit_trail_jsonl_offset_bytes = [int64]$auditOffset
        safetybot_log_offset_bytes = [int64]$safetyOffset
    }
    baseline_inputs = [ordered]@{
        latest_bridge_audit = if ($baselineBridge) { $baselineBridge.FullName } else { "UNKNOWN" }
        latest_stage2_profile = if ($baselineStage2) { $baselineStage2.FullName } else { "UNKNOWN" }
    }
}
$marker | ConvertTo-Json -Depth 8 | Set-Content -Path $markerPath -Encoding UTF8
Write-Host "SOAK_MARKER=$markerPath"

Start-Sleep -Seconds $DurationSec

& python (Join-Path $Root "TOOLS\latency_stage2_section_profile.py") --per-section-sample-limit 5000 | Out-Host
& python (Join-Path $Root "TOOLS\bridge_soak_compare.py") --start-marker $markerPath | Out-Host

$latestCompare = Get-ChildItem (Join-Path $Root "EVIDENCE\bridge_audit") -Filter "bridge_soak_compare_*.json" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestCompare) {
    try {
        $cmp = Get-Content -Raw -Encoding UTF8 $latestCompare.FullName | ConvertFrom-Json
        $sent = [int]($cmp.after_soak_window.metrics.command_sent)
        $nWait = [int]($cmp.after_soak_window.metrics.bridge_wait.n)
        if ($sent -le 0 -or $nWait -le 0) {
            throw "No command samples in soak window (command_sent=$sent, bridge_wait.n=$nWait)."
        }
    } catch {
        throw "Invalid/empty soak comparison output: $($_.Exception.Message)"
    }
}

& powershell -File (Join-Path $Root "TOOLS\SYSTEM_CONTROL.ps1") -Action status -Profile $Profile | Out-Host
Write-Host "RUN_BRIDGE_SOAK_AUDIT done"
