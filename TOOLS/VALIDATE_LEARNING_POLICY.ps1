$ErrorActionPreference = 'Stop'

$projectRoot = 'C:\MAKRO_I_MIKRO_BOT'
$checks = @()

function Add-Check {
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

$runtimeTypes = Get-Content "$projectRoot\MQL5\Include\Core\MbRuntimeTypes.mqh" -Raw
$closedDeal = Get-Content "$projectRoot\MQL5\Include\Core\MbClosedDealTracker.mqh" -Raw
$strategyCommon = Get-Content "$projectRoot\MQL5\Include\Strategies\Common\MbStrategyCommon.mqh" -Raw
$storage = Get-Content "$projectRoot\MQL5\Include\Core\MbStorage.mqh" -Raw

Add-Check 'learning_policy_include_exists' (Test-Path "$projectRoot\MQL5\Include\Core\MbLearningPolicy.mqh") 'Core learning policy helper file'
Add-Check 'runtime_has_learning_fields' (
    $runtimeTypes -match 'learning_sample_count' -and
    $runtimeTypes -match 'learning_confidence' -and
    $runtimeTypes -match 'learning_win_count'
) 'Runtime state carries learning counters and confidence'
Add-Check 'storage_persists_learning_fields' (
    $storage -match 'learning_sample_count' -and
    $storage -match 'learning_confidence' -and
    $storage -match 'learning_loss_count'
) 'Runtime storage persists learning policy state'
Add-Check 'closed_deal_has_min_sample_gate' (
    $closedDeal -match 'MbLearningMinSamplesForBias' -and
    $closedDeal -match 'MbLearningMinSamplesForRisk'
) 'Closed-deal adaptation requires minimum sample size'
Add-Check 'closed_deal_updates_learning_counts' (
    $closedDeal -match 'learning_sample_count\+\+' -and
    $closedDeal -match 'learning_win_count\+\+' -and
    $closedDeal -match 'learning_loss_count\+\+'
) 'Closed-deal tracker counts wins and losses'
Add-Check 'strategy_common_uses_confidence' (
    $strategyCommon -match 'learning_confidence'
) 'Adaptive risk effect is confidence-weighted'
Add-Check 'policy_doc_exists' (Test-Path "$projectRoot\DOCS\21_LEARNING_AND_ANTI_OVERFIT_POLICY.md") 'Learning and anti-overfit policy document exists'

$report = [pscustomobject]@{
    schema_version = '1.0'
    project_root = $projectRoot
    ok = ($checks.ok -notcontains $false)
    checks = $checks
}

$evidenceDir = "$projectRoot\EVIDENCE"
if(-not (Test-Path $evidenceDir)) {
    New-Item -ItemType Directory -Path $evidenceDir | Out-Null
}
$report | ConvertTo-Json -Depth 5 | Set-Content "$evidenceDir\learning_policy_validation_report.json" -Encoding UTF8
$report
