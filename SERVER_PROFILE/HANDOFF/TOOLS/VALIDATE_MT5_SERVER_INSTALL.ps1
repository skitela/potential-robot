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
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json

$required = @(
    (Join-Path $targetTerminal "MQL5\Include\Core\MbRuntimeTypes.mqh"),
    (Join-Path $targetTerminal "MQL5\Include\Core\MbKillSwitchGuard.mqh"),
    (Join-Path $targetTerminal "MQL5\Include\Core\MbCandidateArbitration.mqh"),
    (Join-Path $targetTerminal "MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json"),
    $targetCommon
)

foreach ($item in $registry.symbols) {
    $expert = [string]$item.expert
    $preset = [string]$item.preset
    $codeSymbol = if ($item.PSObject.Properties.Name -contains 'code_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$item.code_symbol)) {
        [string]$item.code_symbol
    } else {
        [string]$expert.Replace("MicroBot_","")
    }
    $activePreset = "{0}_ACTIVE.set" -f ([System.IO.Path]::GetFileNameWithoutExtension($preset))

    $required += @(
        (Join-Path $targetTerminal ("MQL5\Experts\MicroBots\{0}.mq5" -f $expert)),
        (Join-Path $targetTerminal ("MQL5\Presets\{0}" -f $preset)),
        (Join-Path $targetTerminal ("MQL5\Presets\ActiveLive\{0}" -f $activePreset)),
        (Join-Path $targetTerminal ("MQL5\Experts\MicroBots\{0}.ex5" -f $expert))
    )
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
