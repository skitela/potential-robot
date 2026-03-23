param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [switch]$AllowBlockedAuditGate
)

$ErrorActionPreference = 'Stop'

$steps = @()

function Invoke-GateStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $started = (Get-Date).ToUniversalTime().ToString("o")
    & $Action
    $script:steps += [pscustomobject]@{
        step = $Name
        started_utc = $started
        finished_utc = (Get-Date).ToUniversalTime().ToString("o")
        status = "PASS"
    }
}

Invoke-GateStep -Name "assert_audit_live_gate" -Action {
    & (Join-Path $ProjectRoot "TOOLS\ASSERT_AUDIT_SUPERVISOR_GATE.ps1") `
        -ProjectRoot $ProjectRoot `
        -GateType LIVE `
        -AllowBlocked:$AllowBlockedAuditGate | Out-Null
}

Invoke-GateStep -Name "contract_tests" -Action {
    & (Join-Path $ProjectRoot "TESTS\RUN_CONTRACT_TESTS.ps1") | Out-Null
}

Invoke-GateStep -Name "session_state_machine" -Action {
    $json = & (Join-Path $ProjectRoot "TOOLS\VALIDATE_SESSION_STATE_MACHINE.ps1")
    $parsed = $json | ConvertFrom-Json
    if (-not $parsed.ok) {
        throw "Session state machine validator reported ok=false."
    }
}

Invoke-GateStep -Name "deployment_readiness" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_DEPLOYMENT_READINESS.ps1") | Out-Null
}

Invoke-GateStep -Name "transfer_package" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_TRANSFER_PACKAGE.ps1") | Out-Null
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    go = $true
    decision = "GO_PRELIVE"
    steps = $steps
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\prelive_gonogo_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\prelive_gonogo_report.txt"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @(
    "PRELIVE GO NO-GO REPORT",
    "GO=True",
    "DECISION=GO_PRELIVE",
    ""
)
foreach ($step in $steps) {
    $lines += ("{0} | {1} -> {2} | {3}" -f $step.step,$step.started_utc,$step.finished_utc,$step.status)
}
$lines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$report | ConvertTo-Json -Depth 6
