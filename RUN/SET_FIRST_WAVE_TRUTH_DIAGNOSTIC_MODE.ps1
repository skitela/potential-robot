param(
    [ValidateSet("Enable","Disable")]
    [string]$Mode = "Enable",
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$DurationMinutes = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$configPath = Join-Path $projectPath "CONFIG\session_capital_coordinator_v1.json"
$backupRoot = Join-Path $projectPath "CONFIG\backups"
$applyRuntimeScript = Join-Path $projectPath "RUN\APPLY_FIRST_WAVE_BROKER_PARITY_RUNTIME.ps1"
$validateScript = Join-Path $projectPath "TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1"
$targetDomains = @("FX","INDICES")
$commonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
$diagnosticDir = Join-Path $commonRoot "run"
$diagnosticPath = Join-Path $diagnosticDir "first_wave_truth_diagnostic.csv"

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing config: $configPath"
}
if (-not (Test-Path -LiteralPath $applyRuntimeScript)) {
    throw "Missing runtime apply script: $applyRuntimeScript"
}
if (-not (Test-Path -LiteralPath $validateScript)) {
    throw "Missing validation script: $validateScript"
}

New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $backupRoot ("session_capital_coordinator_v1_{0}.json" -f $stamp)
Copy-Item -LiteralPath $configPath -Destination $backupPath -Force

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $config.domains) {
    throw "Invalid coordinator config: domains missing"
}

$updated = New-Object System.Collections.Generic.List[object]
foreach ($domain in $config.domains) {
    $domainName = [string]$domain.domain
    if ($targetDomains -contains $domainName) {
        $domain.manual_override = if ($Mode -eq "Enable") { "PAPER_ONLY" } else { "AUTO" }
    }
    $updated.Add([pscustomobject]@{
        domain = $domainName
        manual_override = [string]$domain.manual_override
        targeted = ($targetDomains -contains $domainName)
    }) | Out-Null
}

$json = $config | ConvertTo-Json -Depth 20
$json | Set-Content -LiteralPath $configPath -Encoding UTF8

New-Item -ItemType Directory -Force -Path $diagnosticDir | Out-Null
if ($Mode -eq "Enable") {
    $maxAgeSeconds = [Math]::Max(300, $DurationMinutes * 60)
    $generatedAtUtc = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    @(
        "key,value"
        "enabled,1"
        "generated_at_utc,$generatedAtUtc"
        "max_age_sec,$maxAgeSeconds"
        "allow_symbol_daily_loss_hard,1"
        "allow_central_state_stale,1"
        "allow_low_conversion_ratio,1"
        "allow_forefield_dirty,1"
        "allow_bootstrap_low_sample,1"
        "allow_bootstrap_empty_buckets,1"
        "relax_symbol_cost_gates,1"
        "force_scan_interval_sec,90"
        "breakout_gate_abs,0.14"
        "trend_gate_abs,0.14"
        "range_gate_abs,0.10"
        "rejection_gate_abs,0.10"
    ) | Set-Content -LiteralPath $diagnosticPath -Encoding ASCII
}
elseif (Test-Path -LiteralPath $diagnosticPath) {
    Remove-Item -LiteralPath $diagnosticPath -Force
}

$applyResult = & $applyRuntimeScript
$validation = & $validateScript | ConvertFrom-Json
$updatedArray = @($updated.ToArray())
$validationIssues = @($validation.issues)
$runtimeApplyText = (@($applyResult) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine

[pscustomobject]@{
    schema_version = "1.0"
    ts_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    project_root = $projectPath
    mode = $Mode
    target_domains = $targetDomains
    backup_path = $backupPath
    config_path = $configPath
    diagnostic_file_path = $diagnosticPath
    diagnostic_file_exists = (Test-Path -LiteralPath $diagnosticPath)
    updated_domains = $updatedArray
    runtime_apply_invoked = $true
    validation_ok = [bool]$validation.ok
    validation_issues = $validationIssues
    runtime_apply_result = $runtimeApplyText
} | ConvertTo-Json -Depth 10
