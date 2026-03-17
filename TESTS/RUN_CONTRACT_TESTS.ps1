param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = 'Stop'

$tests = @()

function Invoke-TestStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $started = (Get-Date).ToUniversalTime().ToString("o")
    & $Action
    $script:tests += [pscustomobject]@{
        name = $Name
        started_utc = $started
        finished_utc = (Get-Date).ToUniversalTime().ToString("o")
        status = "OK"
    }
}

Invoke-TestStep -Name "validate_project_layout" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_PROJECT_LAYOUT.ps1") | Out-Null
}

Invoke-TestStep -Name "validate_symbol_policy_consistency" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1") | Out-Null
}

Invoke-TestStep -Name "validate_family_policy_bounds" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_FAMILY_POLICY_BOUNDS.ps1") | Out-Null
}

Invoke-TestStep -Name "validate_family_reference_registry" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_FAMILY_REFERENCE_REGISTRY.ps1") | Out-Null
}

Invoke-TestStep -Name "validate_preset_safety" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_PRESET_SAFETY.ps1") | Out-Null
}

Invoke-TestStep -Name "validate_learning_policy" -Action {
    & (Join-Path $ProjectRoot "TOOLS\VALIDATE_LEARNING_POLICY.ps1") | Out-Null
}

Invoke-TestStep -Name "run_family_scenario_tests" -Action {
    & (Join-Path $ProjectRoot "TESTS\RUN_FAMILY_SCENARIO_TESTS.ps1") | Out-Null
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    ok = $true
    tests = $tests
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\contract_test_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\contract_test_report.txt"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @(
    "CONTRACT TEST REPORT",
    "OK=True",
    ""
)
foreach ($test in $tests) {
    $lines += ("{0} | {1} -> {2} | {3}" -f $test.name,$test.started_utc,$test.finished_utc,$test.status)
}
$lines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$report | ConvertTo-Json -Depth 6
