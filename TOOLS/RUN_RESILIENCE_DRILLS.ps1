param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = 'Stop'

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registry = Get-Content (Join-Path $ProjectRoot "CONFIG\microbots_registry.json") -Raw | ConvertFrom-Json
$symbols = @($registry.symbols)
$checks = @()

function Add-Drill {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail
    )
    $script:checks += [pscustomobject]@{
        name = $Name
        ok = $Ok
        detail = $Detail
    }
}

$stateOk = $true
foreach ($symbol in $symbols) {
    $stateAlias = Resolve-RegistryStateAlias -RegistryItem $symbol -CommonFilesRoot $CommonFilesRoot -RequiredFiles @("runtime_state.csv")
    $statePath = Join-Path $CommonFilesRoot ("state\{0}\runtime_state.csv" -f $stateAlias)
    if (-not (Test-Path $statePath)) {
        $stateOk = $false
    }
}
Add-Drill 'runtime_state_presence' $stateOk 'Every symbol should have runtime_state.csv in Common Files'

$tokenOk = $true
foreach ($symbol in $symbols) {
    $canonicalSymbol = Get-RegistryCanonicalSymbol -RegistryItem $symbol
    $tokenDir = Join-Path $CommonFilesRoot ("key\{0}" -f $canonicalSymbol)
    if (-not (Test-Path $tokenDir)) {
        $tokenOk = $false
    }
}
Add-Drill 'kill_switch_token_dirs_present' $tokenOk 'Every symbol should have a key directory for token continuity'

$packageOk = (Test-Path (Join-Path $ProjectRoot "SERVER_PROFILE\PACKAGE\server_profile_manifest.json"))
$handoffOk = (Test-Path (Join-Path $ProjectRoot "SERVER_PROFILE\HANDOFF\handoff_manifest.json"))
$backupOk = @(Get-ChildItem (Join-Path $ProjectRoot "BACKUP") -Filter "MAKRO_I_MIKRO_BOT_*.zip" -ErrorAction SilentlyContinue).Count -gt 0
Add-Drill 'recovery_artifacts_present' ($packageOk -and $handoffOk -and $backupOk) 'Package, handoff, and backup ZIP must all exist'

$logPath = Join-Path $TerminalDataDir ("logs\" + (Get-Date -Format 'yyyyMMdd') + ".log")
$expertLoads = @()
if (Test-Path $logPath) {
    $expertLoads = Select-String -Path $logPath -Pattern 'expert MicroBot_.* loaded successfully' | ForEach-Object { $_.Line }
}
$loadOk = $expertLoads.Count -ge $symbols.Count
Add-Drill 'post_restart_expert_loads' $loadOk 'MT5 log should show successful expert loads after restart'

$runtimeSummaryOk = $true
foreach ($symbol in $symbols) {
    $stateAlias = Resolve-RegistryStateAlias -RegistryItem $symbol -CommonFilesRoot $CommonFilesRoot -RequiredFiles @("execution_summary.json")
    $summaryPath = Join-Path $CommonFilesRoot ("state\{0}\execution_summary.json" -f $stateAlias)
    if (-not (Test-Path $summaryPath)) {
        $runtimeSummaryOk = $false
        continue
    }
    $payload = Get-Content $summaryPath -Raw
    if ($payload -notmatch '"runtime_mode"' -or $payload -notmatch '"execution_pressure"') {
        $runtimeSummaryOk = $false
    }
}
Add-Drill 'runtime_summary_presence' $runtimeSummaryOk 'Every symbol should expose execution_summary.json with core runtime fields'

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    terminal_data_dir = $TerminalDataDir
    common_files_root = $CommonFilesRoot
    ok = ($checks.ok -notcontains $false)
    drills = $checks
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\resilience_drill_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\resilience_drill_report.txt"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @(
    "RESILIENCE DRILL REPORT",
    ("OK={0}" -f $report.ok),
    ""
)
foreach ($drill in $checks) {
    $lines += ("{0} | {1} | {2}" -f $drill.name,$drill.ok,$drill.detail)
}
$lines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$report | ConvertTo-Json -Depth 6
