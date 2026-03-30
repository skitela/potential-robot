param(
    [ValidateSet("Enable","Disable")]
    [string]$Mode = "Enable",
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$configPath = Join-Path $projectPath "CONFIG\session_capital_coordinator_v1.json"
$backupRoot = Join-Path $projectPath "CONFIG\backups"
$applyRuntimeScript = Join-Path $projectPath "RUN\APPLY_FIRST_WAVE_BROKER_PARITY_RUNTIME.ps1"
$validateScript = Join-Path $projectPath "TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1"
$targetDomains = @("FX","INDICES")

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
    updated_domains = $updatedArray
    runtime_apply_invoked = $true
    validation_ok = [bool]$validation.ok
    validation_issues = $validationIssues
    runtime_apply_result = $runtimeApplyText
} | ConvertTo-Json -Depth 10
