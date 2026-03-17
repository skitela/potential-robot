param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = 'Stop'

$registry = Get-Content (Join-Path $ProjectRoot "CONFIG\microbots_registry.json") -Raw | ConvertFrom-Json
$familyMap = @{}
foreach ($item in $registry.symbols) {
    $family = [string]$item.session_profile
    if (-not $familyMap.ContainsKey($family)) {
        $familyMap[$family] = @()
    }
    $familyMap[$family] += [string]$item.symbol
}

$families = @()
foreach ($family in $familyMap.Keys | Sort-Object) {
    $symbols = @($familyMap[$family])
    $rows = @()
    foreach ($symbol in $symbols) {
        $summaryPath = Join-Path $CommonFilesRoot ("state\{0}\execution_summary.json" -f $symbol)
        $policyPath = Join-Path $CommonFilesRoot ("state\{0}\informational_policy.json" -f $symbol)
        if ((Test-Path $summaryPath) -and (Test-Path $policyPath)) {
            $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
            $policy = Get-Content $policyPath -Raw | ConvertFrom-Json
            $learningConfidence = 0.0
            $learningSampleCount = 0
            if ($policy.PSObject.Properties.Name -contains 'learning_confidence') {
                $learningConfidence = [double]$policy.learning_confidence
            }
            if ($policy.PSObject.Properties.Name -contains 'learning_sample_count') {
                $learningSampleCount = [int]$policy.learning_sample_count
            }
            $rows += [pscustomobject]@{
                symbol = $symbol
                runtime_mode = [string]$summary.runtime_mode
                latency_ms_avg = [math]::Round(([double]$summary.local_latency_us_avg / 1000.0),4)
                latency_ms_max = [math]::Round(([double]$summary.local_latency_us_max / 1000.0),4)
                execution_pressure = [double]$summary.execution_pressure
                learning_confidence = $learningConfidence
                learning_sample_count = $learningSampleCount
                spread_points = [double]$summary.spread_points
            }
        }
    }

    $avgLatency = 0.0
    if ($rows.Count -gt 0) {
        $avgLatency = [math]::Round((($rows | Measure-Object -Property latency_ms_avg -Average).Average),4)
    }
    $families += [pscustomobject]@{
        family = $family
        symbol_count = $rows.Count
        avg_latency_ms = $avgLatency
        max_latency_ms = if($rows.Count -gt 0){ [math]::Round((($rows | Measure-Object -Property latency_ms_max -Maximum).Maximum),4)} else { 0.0 }
        avg_execution_pressure = if($rows.Count -gt 0){ [math]::Round((($rows | Measure-Object -Property execution_pressure -Average).Average),4)} else { 0.0 }
        avg_learning_confidence = if($rows.Count -gt 0){ [math]::Round((($rows | Measure-Object -Property learning_confidence -Average).Average),4)} else { 0.0 }
        rows = $rows
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    common_files_root = $CommonFilesRoot
    families = $families
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\family_operator_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\family_operator_report.txt"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @("FAMILY OPERATOR REPORT","")
foreach ($family in $families) {
    $lines += ("{0} | symbols={1} | avg_latency_ms={2} | max_latency_ms={3} | avg_execution_pressure={4} | avg_learning_confidence={5}" -f
        $family.family,$family.symbol_count,$family.avg_latency_ms,$family.max_latency_ms,$family.avg_execution_pressure,$family.avg_learning_confidence)
    foreach ($row in $family.rows) {
        $lines += ("  - {0} | mode={1} | latency_avg_ms={2} | latency_max_ms={3} | exec_pressure={4} | learning_confidence={5} | learning_samples={6} | spread={7}" -f
            $row.symbol,$row.runtime_mode,$row.latency_ms_avg,$row.latency_ms_max,$row.execution_pressure,$row.learning_confidence,$row.learning_sample_count,$row.spread_points)
    }
    $lines += ""
}
$lines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$report | ConvertTo-Json -Depth 8
