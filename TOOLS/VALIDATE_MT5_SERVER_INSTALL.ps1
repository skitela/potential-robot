param(
    [string]$TargetTerminalDataDir,
    [string]$TargetCommonFilesDir = (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"),
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TargetTerminalDataDir)) {
    throw "TargetTerminalDataDir is required."
}

$issues = New-Object System.Collections.Generic.List[string]
$targetTerminal = $TargetTerminalDataDir
$targetCommon = Join-Path $TargetCommonFilesDir "MAKRO_I_MIKRO_BOT"
$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$planPath = Join-Path $ProjectRoot "CONFIG\scalping_universe_plan.json"

if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing registry: $registryPath"
}
if (-not (Test-Path -LiteralPath $planPath)) {
    throw "Missing scalping universe plan: $planPath"
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
$paperLiveSymbols = @($plan.paper_live_first_wave | ForEach-Object { [string]$_ })

$required = @(
    (Join-Path $targetTerminal "MQL5\Include\Core\MbRuntimeTypes.mqh"),
    (Join-Path $targetTerminal "MQL5\Include\Core\MbKillSwitchGuard.mqh"),
    (Join-Path $targetTerminal "MQL5\Include\Core\MbCandidateArbitration.mqh"),
    (Join-Path $targetTerminal "MQL5\Include\Core\MbVpsSpool.mqh"),
    (Join-Path $targetTerminal "MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json"),
    $targetCommon,
    (Join-Path $targetCommon "spool"),
    (Join-Path $targetCommon "spool\onnx_observations"),
    (Join-Path $targetCommon "spool\candidate_signals"),
    (Join-Path $targetCommon "spool\learning_observations_v2"),
    (Join-Path $targetCommon "spool\pretrade_truth"),
    (Join-Path $targetCommon "spool\execution_truth")
)

foreach ($item in $registry.symbols) {
    $expert = [string]$item.expert
    $preset = [string]$item.preset
    $symbol = [string]$item.symbol
    $activePreset = "{0}_ACTIVE.set" -f ([System.IO.Path]::GetFileNameWithoutExtension($preset))

    $required += @(
        (Join-Path $targetTerminal ("MQL5\Experts\MicroBots\{0}.mq5" -f $expert)),
        (Join-Path $targetTerminal ("MQL5\Presets\{0}" -f $preset)),
        (Join-Path $targetTerminal ("MQL5\Experts\MicroBots\{0}.ex5" -f $expert)),
        (Join-Path $targetCommon ("state\{0}\teacher_package_contract.csv" -f $symbol)),
        (Join-Path $targetCommon ("state\{0}\teacher_package_manifest_latest.json" -f $symbol))
    )

    if ($paperLiveSymbols -contains $symbol) {
        $required += (Join-Path $targetTerminal ("MQL5\Presets\ActiveLive\{0}" -f $activePreset))
    }
}

$required = $required | Sort-Object -Unique
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        $issues.Add("MISSING:" + $path)
    }
}

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    target_terminal_data_dir = $targetTerminal
    target_common_files_dir = $TargetCommonFilesDir
    ok = ($issues.Count -eq 0)
    issues = @($issues)
}

$jsonPath = Join-Path $projectRoot "EVIDENCE\validate_mt5_server_install_report.json"
$txtPath = Join-Path $projectRoot "EVIDENCE\validate_mt5_server_install_report.txt"

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $txtPath -Encoding ASCII
$result | ConvertTo-Json -Depth 6

if (-not $result.ok) {
    exit 1
}
