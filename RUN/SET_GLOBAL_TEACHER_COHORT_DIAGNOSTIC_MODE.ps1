param(
    [ValidateSet("Enable","Disable")]
    [string]$Mode = "Enable",
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$DurationMinutes = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$commonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
$diagnosticDir = Join-Path $commonRoot "run"
$diagnosticPath = Join-Path $diagnosticDir "global_teacher_cohort_diagnostic.csv"

New-Item -ItemType Directory -Force -Path $diagnosticDir | Out-Null

if ($Mode -eq "Enable") {
    $maxAgeSeconds = [Math]::Max(1800, $DurationMinutes * 60)
    $generatedAtUtc = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    @(
        "key,value"
        "enabled,1"
        "generated_at_utc,$generatedAtUtc"
        "max_age_sec,$maxAgeSeconds"
        "force_scan_interval_sec,60"
        "allow_low_conversion_ratio,1"
        "allow_forefield_dirty,1"
        "allow_portfolio_heat,1"
        "allow_family_freeze_relief,1"
        "allow_fleet_freeze_relief,1"
        "relax_tuning_gates,1"
        "relax_cost_gates,1"
        "breakout_gate_abs,0.16"
        "trend_gate_abs,0.14"
        "range_gate_abs,0.10"
        "rejection_gate_abs,0.10"
    ) | Set-Content -LiteralPath $diagnosticPath -Encoding ASCII
}
elseif (Test-Path -LiteralPath $diagnosticPath) {
    Remove-Item -LiteralPath $diagnosticPath -Force
}

[pscustomobject]@{
    schema_version = "1.0"
    ts_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    project_root = $projectPath
    mode = $Mode
    duration_minutes = $DurationMinutes
    diagnostic_file_path = $diagnosticPath
    diagnostic_file_exists = (Test-Path -LiteralPath $diagnosticPath)
} | ConvertTo-Json -Depth 5
