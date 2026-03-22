param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager",
    [string]$QdmSymbol = "AUDUSD",
    [string]$ExportName = "MB_AUDUSD_DUKA_M1_PILOT",
    [string]$Timeframe = "M1",
    [string]$DateFrom = "2026.03.12",
    [string]$DateTo = "2026.03.16",
    [string]$SpreadType = "points",
    [double]$SpreadValue = 2,
    [string]$OutputDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\QDM_PILOT",
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\QDM_PILOT\qdm_export_pilot_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$qdmCli = Join-Path $QdmRoot "qdmcli.exe"
if (-not (Test-Path -LiteralPath $qdmCli)) {
    throw "QDM CLI not found: $qdmCli"
}

$historyFile = Join-Path $QdmRoot ("user\data\History\{0}\{0}_TICK.dat" -f $QdmSymbol)
if (-not (Test-Path -LiteralPath $historyFile)) {
    throw "QDM history file not found: $historyFile"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$exportCsvPath = Join-Path $OutputDir ("{0}.csv" -f $ExportName)
if (Test-Path -LiteralPath $exportCsvPath) {
    Remove-Item -LiteralPath $exportCsvPath -Force
}

$arguments = @(
    "-data",
    "action=exportToMT5",
    "symbol=$QdmSymbol",
    "timeframe=$Timeframe",
    "datefrom=$DateFrom",
    "dateto=$DateTo",
    "outputdir=$OutputDir",
    "filename=$ExportName"
)

if ($Timeframe -ne "TICK") {
    $arguments += @(
        "spreadType=$SpreadType",
        "spreadValue=$SpreadValue"
    )
}

$stdoutPath = Join-Path $OutputDir ("{0}__stdout.log" -f $ExportName)
$stderrPath = Join-Path $OutputDir ("{0}__stderr.log" -f $ExportName)
if (Test-Path -LiteralPath $stdoutPath) { Remove-Item -LiteralPath $stdoutPath -Force }
if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force }

try {
    $process = Start-Process -FilePath $qdmCli `
        -ArgumentList $arguments `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -Wait `
        -PassThru `
        -NoNewWindow
    $qdmExitCode = $process.ExitCode
}
finally {
}

$outputLines = @()
foreach ($logPath in @($stdoutPath, $stderrPath)) {
    if (Test-Path -LiteralPath $logPath) {
        $outputLines += (Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue)
    }
}

$csvExists = Test-Path -LiteralPath $exportCsvPath
$rowCount = 0
if ($csvExists) {
    $rowCount = [Math]::Max(((Get-Content -LiteralPath $exportCsvPath | Measure-Object -Line).Lines), 0)
}

$result = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    qdm_symbol = $QdmSymbol
    export_name = $ExportName
    timeframe = $Timeframe
    date_from = $DateFrom
    date_to = $DateTo
    spread_type = $SpreadType
    spread_value = $SpreadValue
    history_file = $historyFile
    export_csv_path = $exportCsvPath
    csv_present = $csvExists
    row_count = $rowCount
    qdm_exit_code = $qdmExitCode
    output_dir = $OutputDir
    qdm_cli = $qdmCli
    stdout_log_path = $(if (Test-Path -LiteralPath $stdoutPath) { $stdoutPath } else { $null })
    stderr_log_path = $(if (Test-Path -LiteralPath $stderrPath) { $stderrPath } else { $null })
    raw_output = (($outputLines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    state = $(if ($csvExists -and $rowCount -gt 0 -and $qdmExitCode -eq 0) { "exported" } else { "failed" })
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
$result | ConvertTo-Json -Depth 5

if (-not $csvExists -or $rowCount -le 0) {
    exit 1
}
