param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$StateRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state",
    [int]$MaxHeartbeatAgeSec = 180,
    [int]$RestartCooldownSec = 180,
    [switch]$NoRepair
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Read-JsonOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Read-TextOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Trim() } catch { return $null }
}

function Get-UnixNow {
    return [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Get-HeartbeatAgeSec {
    param([string]$HeartbeatPath, [object]$RuntimeStatus)
    $now = Get-UnixNow
    $hb = Read-TextOrNull -Path $HeartbeatPath
    if (-not [string]::IsNullOrWhiteSpace([string]$hb) -and [string]$hb -match '^\d+$') {
        $age = [int]($now - [int64]$hb)
        if ($age -lt 0) {
            if ([Math]::Abs($age) -le 7200) { return 0 }
            return [Math]::Abs($age)
        }
        return $age
    }
    if ($null -ne $RuntimeStatus -and $null -ne $RuntimeStatus.heartbeat_utc) {
        try {
            $age = [int]($now - [int64]$RuntimeStatus.heartbeat_utc)
            if ($age -lt 0) {
                if ([Math]::Abs($age) -le 7200) { return 0 }
                return [Math]::Abs($age)
            }
            return $age
        } catch { return $null }
    }
    return $null
}

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$registry = Read-JsonOrNull -Path $registryPath
if ($null -eq $registry) {
    throw "Brak lub uszkodzony rejestr mikro-botow: $registryPath"
}

$evidenceDir = Join-Path $ProjectRoot "EVIDENCE"
$runDir = Join-Path $ProjectRoot "RUN"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$commonFilesRootResolved = Split-Path -Parent $StateRoot

$statusJsonPath = Join-Path $evidenceDir "runtime_watchdog_status.json"
$statusTxtPath = Join-Path $evidenceDir "runtime_watchdog_status.txt"
$statePath = Join-Path $runDir "runtime_watchdog_state.json"
$latestState = Read-JsonOrNull -Path $statePath

$terminalProcesses = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
$terminalRunning = (@($terminalProcesses).Count -gt 0)
$nowUtc = [DateTime]::UtcNow.ToString("o")

$symbolRows = @()
$staleSymbols = @()
$missingSymbols = @()

foreach ($item in @($registry.symbols)) {
    $symbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $stateAlias = Resolve-RegistryStateAlias -RegistryItem $item -CommonFilesRoot $commonFilesRootResolved
    $family = [string]$item.session_profile
    $symbolDir = Join-Path $StateRoot $stateAlias
    $runtimeStatusPath = Join-Path $symbolDir "runtime_status.json"
    $runtimeStatePath = Join-Path $symbolDir "runtime_state.csv"
    $heartbeatPath = Join-Path $symbolDir "heartbeat.txt"
    $executionSummaryPath = Join-Path $symbolDir "execution_summary.json"

    $runtimeStatus = Read-JsonOrNull -Path $runtimeStatusPath
    $heartbeatAgeSec = Get-HeartbeatAgeSec -HeartbeatPath $heartbeatPath -RuntimeStatus $runtimeStatus
    $hasState = (Test-Path -LiteralPath $runtimeStatePath)
    $hasExecution = (Test-Path -LiteralPath $executionSummaryPath)
    $isMissing = (-not (Test-Path -LiteralPath $symbolDir)) -or (-not $hasState) -or (-not $hasExecution)
    $isStale = ($null -eq $heartbeatAgeSec) -or ($heartbeatAgeSec -gt $MaxHeartbeatAgeSec)

    if ($isMissing) { $missingSymbols += $symbol }
    if ($isStale) { $staleSymbols += $symbol }

    $rowStatus = "OK"
    if ($isMissing) {
        $rowStatus = "BRAK_STANU"
    } elseif ($isStale) {
        $rowStatus = "STALE_HEARTBEAT"
    }

    $symbolRows += [pscustomobject]@{
        symbol = $symbol
        state_alias = $stateAlias
        family = $family
        status = $rowStatus
        heartbeat_age_sec = $heartbeatAgeSec
        runtime_mode = $(if ($runtimeStatus) { [string]$runtimeStatus.runtime_mode } else { "" })
        reason_code = $(if ($runtimeStatus) { [string]$runtimeStatus.reason_code } else { "" })
        has_runtime_state = [bool]$hasState
        has_execution_summary = [bool]$hasExecution
    }
}

$repairNeeded = (-not $terminalRunning) -or (@($staleSymbols).Count -gt 0) -or (@($missingSymbols).Count -gt 0)
$repairAttempted = $false
$repairPerformed = $false
$repairBlockedByCooldown = $false
$repairError = ""
$repairAction = "NONE"
$repairAllowed = (-not $NoRepair)
$lastRepairUtc = ""
$cooldownLeftSec = 0

if ($null -ne $latestState -and -not [string]::IsNullOrWhiteSpace([string]$latestState.last_repair_utc)) {
    $lastRepairUtc = [string]$latestState.last_repair_utc
    try {
        $lastRepairDt = [DateTime]::Parse($lastRepairUtc).ToUniversalTime()
        $elapsed = [int]([DateTime]::UtcNow - $lastRepairDt).TotalSeconds
        $cooldownLeftSec = [Math]::Max(0, $RestartCooldownSec - $elapsed)
    } catch {
        $cooldownLeftSec = 0
    }
}

if ($repairNeeded -and $repairAllowed) {
    if ($cooldownLeftSec -gt 0) {
        $repairBlockedByCooldown = $true
        $repairAction = "COOLDOWN"
    } else {
        $repairAttempted = $true
        $repairAction = "RESTART_MT5"
        try {
            & (Join-Path $ProjectRoot "RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1") | Out-Null
            Start-Sleep -Seconds 10
            $terminalProcessesAfter = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
            if (@($terminalProcessesAfter).Count -gt 0) {
                $repairPerformed = $true
                $lastRepairUtc = [DateTime]::UtcNow.ToString("o")
            } else {
                $repairError = "Terminal MT5 nie podniosl sie po restarcie."
            }
        } catch {
            $repairError = $_.Exception.Message
        }
    }
}

$statusValue = "ZDROWY"
if ($repairNeeded -and $repairAttempted -and $repairPerformed) {
    $statusValue = "NAPRAWIONY"
} elseif ($repairNeeded -and $repairBlockedByCooldown) {
    $statusValue = "OSTRZEZENIE"
} elseif ($repairNeeded) {
    $statusValue = "WYMAGA_NAPRAWY"
}

$statePayload = [ordered]@{
    schema_version = "1.0"
    ts_utc = $nowUtc
    last_repair_utc = $lastRepairUtc
}
$statePayload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8

$payload = [ordered]@{
    schema_version = "1.0"
    ts_utc = $nowUtc
    project_root = $ProjectRoot
    state_root = $StateRoot
    max_heartbeat_age_sec = $MaxHeartbeatAgeSec
    restart_cooldown_sec = $RestartCooldownSec
    status = $statusValue
    terminal_running = [bool]$terminalRunning
    repair_needed = [bool]$repairNeeded
    repair_allowed = [bool]$repairAllowed
    repair_attempted = [bool]$repairAttempted
    repair_performed = [bool]$repairPerformed
    repair_blocked_by_cooldown = [bool]$repairBlockedByCooldown
    repair_action = $repairAction
    repair_error = $repairError
    stale_symbols = @($staleSymbols)
    missing_symbols = @($missingSymbols)
    cooldown_left_sec = [int]$cooldownLeftSec
    symbols = @($symbolRows)
}

$payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusJsonPath -Encoding UTF8

$txt = @()
$txt += "WATCHDOG RUNTIME MAKRO I MIKRO BOT"
$txt += ("status={0}" -f $statusValue)
$txt += ("terminal_running={0}" -f [int]$terminalRunning)
$txt += ("repair_needed={0}" -f [int]$repairNeeded)
$txt += ("repair_attempted={0}" -f [int]$repairAttempted)
$txt += ("repair_performed={0}" -f [int]$repairPerformed)
$txt += ("repair_action={0}" -f $repairAction)
$txt += ("repair_error={0}" -f $repairError)
$txt += ("cooldown_left_sec={0}" -f [int]$cooldownLeftSec)
$txt += ""
foreach ($row in $symbolRows) {
    $txt += ("{0} | {1} | {2} | hb_age={3}s | mode={4} | reason={5}" -f
        $row.symbol, $row.family, $row.status, $row.heartbeat_age_sec, $row.runtime_mode, $row.reason_code)
}
$txt | Set-Content -LiteralPath $statusTxtPath -Encoding ASCII

$payload | ConvertTo-Json -Depth 6
