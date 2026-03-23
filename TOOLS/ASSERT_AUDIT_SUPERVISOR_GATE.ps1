param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [ValidateSet("ROLLOUT", "LIVE")]
    [string]$GateType = "ROLLOUT",
    [int]$MaxAgeMinutes = 20,
    [switch]$AllowStale,
    [switch]$AllowBlocked
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$reportPath = Join-Path $ProjectRoot "EVIDENCE\OPS\audit_supervisor_latest.json"
if (-not (Test-Path -LiteralPath $reportPath)) {
    throw "Brak raportu superwizora audytu: $reportPath"
}

$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$overall = $report.overall
if ($null -eq $overall) {
    throw "Raport superwizora nie zawiera sekcji overall."
}

$reportItem = Get-Item -LiteralPath $reportPath
$ageMinutes = [math]::Round(((Get-Date) - $reportItem.LastWriteTime).TotalMinutes, 2)
$isFresh = ($ageMinutes -le $MaxAgeMinutes)

if (-not $isFresh -and -not $AllowStale) {
    throw ("Raport superwizora jest zbyt stary ({0} min > {1} min)." -f $ageMinutes, $MaxAgeMinutes)
}

$gateValue = switch ($GateType) {
    "ROLLOUT" { [string]$overall.rollout_gate }
    "LIVE" { [string]$overall.live_gate }
}

if ($gateValue -eq "BLOCKED" -and -not $AllowBlocked) {
    throw ("Superwizor audytu blokuje {0}. Szczegoly w: {1}" -f $GateType.ToLowerInvariant(), $reportPath)
}

$result = [ordered]@{
    schema_version = "1.0"
    gate_type = $GateType
    gate_value = $gateValue
    overall_gate = [string]$overall.gate
    generated_at_local = [string]$report.generated_at_local
    report_path = $reportPath
    report_age_minutes = $ageMinutes
    report_fresh = $isFresh
    allowed = ($gateValue -ne "BLOCKED" -or [bool]$AllowBlocked)
}

$result | ConvertTo-Json -Depth 4
