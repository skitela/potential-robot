param(
    [int]$DurationSec = 1800,
    [string]$Root = "C:\OANDA_MT5_SYSTEM"
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

Write-Host "RUN_BRIDGE_SOAK_AUDIT start_utc=$utcNow duration_sec=$DurationSec"
& powershell -File (Join-Path $Root "TOOLS\SYSTEM_CONTROL.ps1") -Action status -Profile safety_only | Out-Host

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
    runtime_profile = "safety_only"
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

& powershell -File (Join-Path $Root "TOOLS\SYSTEM_CONTROL.ps1") -Action status -Profile safety_only | Out-Host
Write-Host "RUN_BRIDGE_SOAK_AUDIT done"
