param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$DurationMin = 20,
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "full",
    [int]$ProbeIntervalSec = 15,
    [int]$ProbeMaxPerRun = 120,
    [string]$ProbeSymbol = "__TRADE_PROBE_INVALID__",
    [ValidateSet("BUY", "SELL")]
    [string]$ProbeSignal = "BUY",
    [string]$ProbeGroup = "FX",
    [double]$ProbeVolume = 0.01
)

$ErrorActionPreference = "Stop"

function Set-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Object
    )
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $tmp = "$Path.tmp"
    $json = ($Object | ConvertTo-Json -Depth 100)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $json, $utf8NoBom)
    Move-Item -Path $tmp -Destination $Path -Force
}

$runtimeRoot = (Resolve-Path $Root).Path
$strategyPath = Join-Path $runtimeRoot "CONFIG\strategy.json"
$runDir = Join-Path $runtimeRoot "RUN"
$backupPath = Join-Path $runDir ("strategy_trade_probe_backup_{0}.json" -f (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ"))
$systemControl = Join-Path $runtimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
$latencyAudit = Join-Path $runtimeRoot "TOOLS\run_runtime_latency_audit.ps1"

if (-not (Test-Path $strategyPath)) {
    throw "Brak pliku konfiguracyjnego: $strategyPath"
}

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
Copy-Item -Path $strategyPath -Destination $backupPath -Force
Write-Host "TRADE_PROBE_SOAK backup_saved=$backupPath"

$restoreDone = $false
try {
    $cfg = Get-Content $strategyPath -Raw | ConvertFrom-Json
    $cfg.bridge_trade_probe_enabled = $true
    $cfg.bridge_trade_probe_interval_sec = [int]([Math]::Max(5, $ProbeIntervalSec))
    $cfg.bridge_trade_probe_max_per_run = [int]([Math]::Max(1, $ProbeMaxPerRun))
    $cfg.bridge_trade_probe_signal = [string]$ProbeSignal
    $cfg.bridge_trade_probe_symbol = [string]$ProbeSymbol
    $cfg.bridge_trade_probe_group = [string]$ProbeGroup
    $cfg.bridge_trade_probe_volume = [double]([Math]::Max(0.0, $ProbeVolume))
    $cfg.bridge_trade_probe_deviation_points = 10
    $cfg.bridge_trade_probe_comment = "TRADE_PROBE_SAFE_NO_LIVE"
    Set-JsonFile -Path $strategyPath -Object $cfg

    Write-Host ("TRADE_PROBE_SOAK probe_enabled=1 interval_sec={0} max_per_run={1} symbol={2} signal={3}" -f `
        [int]$cfg.bridge_trade_probe_interval_sec, [int]$cfg.bridge_trade_probe_max_per_run, [string]$cfg.bridge_trade_probe_symbol, [string]$cfg.bridge_trade_probe_signal)

    & powershell -ExecutionPolicy Bypass -File $systemControl -Action stop -Root $runtimeRoot -Profile $Profile | Out-Host
    & powershell -ExecutionPolicy Bypass -File $systemControl -Action start -Root $runtimeRoot -Profile $Profile | Out-Host
    & powershell -ExecutionPolicy Bypass -File $latencyAudit -Root $runtimeRoot -DurationMin $DurationMin -Profile $Profile | Out-Host

    $report = Get-ChildItem (Join-Path $runtimeRoot "EVIDENCE\bridge_audit") -Filter "bridge_soak_compare_*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($null -ne $report) {
        $j = Get-Content $report.FullName -Raw | ConvertFrom-Json
        $cmdCounts = $j.after_soak_window.metrics.command_counts_by_type
        $tradeSent = 0
        $tradeWaitN = 0
        if ($null -ne $cmdCounts) {
            try { $tradeSent = [int]($cmdCounts.TRADE) } catch { $tradeSent = 0 }
        }
        try { $tradeWaitN = [int]($j.after_soak_window.metrics.bridge_wait_trade_path.n) } catch { $tradeWaitN = 0 }
        Write-Host ("TRADE_PROBE_SOAK_RESULT report={0}" -f $report.FullName)
        Write-Host ("TRADE_PROBE_SOAK_RESULT trade_commands_sent={0} trade_wait_samples={1} verdict={2}" -f `
            [int]$tradeSent, [int]$tradeWaitN, [string]$j.verdict.status)
    } else {
        Write-Host "TRADE_PROBE_SOAK_RESULT report_not_found"
    }
}
finally {
    if (Test-Path $backupPath) {
        Copy-Item -Path $backupPath -Destination $strategyPath -Force
        $restoreDone = $true
    }
    Write-Host ("TRADE_PROBE_SOAK restore_config={0}" -f $(if ($restoreDone) { "OK" } else { "FAIL" }))
    & powershell -ExecutionPolicy Bypass -File $systemControl -Action stop -Root $runtimeRoot -Profile $Profile | Out-Host
    & powershell -ExecutionPolicy Bypass -File $systemControl -Action start -Root $runtimeRoot -Profile $Profile | Out-Host
}
