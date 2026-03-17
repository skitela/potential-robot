param(
    [int]$MaxWaitMinutes = 30,
    [int]$PostStartObserveMinutes = 15
)

$ErrorActionPreference = "Stop"

$commonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
$expPath = Join-Path $commonRoot "logs\EURUSD\tuning_experiments.csv"
$candPath = Join-Path $commonRoot "logs\EURUSD\candidate_signals.csv"
$latPath = Join-Path $commonRoot "logs\EURUSD\latency_profile.csv"
$statePath = Join-Path $commonRoot "state\EURUSD\runtime_state.csv"
$evidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE"

$obsStart = Get-Date
$obsStartUnix = ([DateTimeOffset]$obsStart).ToUnixTimeSeconds()
$maxWaitUntil = $obsStart.AddMinutes($MaxWaitMinutes)
$watchUntil = $null
$experimentStart = $null
$stamp = $obsStart.ToString("yyyyMMdd_HHmmss")
$outJson = Join-Path $evidenceDir "EURUSD_EXPERIMENT_WATCH_$stamp.json"
$outJsonl = Join-Path $evidenceDir "EURUSD_EXPERIMENT_WATCH_$stamp.jsonl"

if(Test-Path $outJsonl)
{
    Remove-Item $outJsonl -Force
}

$latHeaders = @(
    "ts","window_started_at","sample_count","avg_local_latency_us","max_local_latency_us",
    "avg_order_send_ms","max_order_send_ms","last_local_latency_us","last_order_send_ms",
    "execution_attempt_count","execution_ok_count","execution_retry_sum",
    "execution_slippage_sum","execution_slippage_max"
)

function Get-ExpRows {
    if(Test-Path $expPath)
    {
        return @(Import-Csv -Delimiter "`t" $expPath)
    }
    return @()
}

function Get-CandRows {
    if(Test-Path $candPath)
    {
        return @(Import-Csv -Delimiter "`t" $candPath)
    }
    return @()
}

function Get-LatRows {
    if(Test-Path $latPath)
    {
        return @(Import-Csv -Delimiter "`t" -Header $latHeaders $latPath | Select-Object -Skip 1)
    }
    return @()
}

function Get-LatSummary {
    param([object[]]$Rows)

    if(-not $Rows -or $Rows.Count -eq 0)
    {
        return [pscustomobject]@{
            weighted_avg_us = 0
            max_us = 0
            samples = 0
            windows = 0
        }
    }

    $sum = 0.0
    $count = 0
    $max = 0
    foreach($r in $Rows)
    {
        $sc = [int]$r.sample_count
        $avg = [double]$r.avg_local_latency_us
        $mx = [int]$r.max_local_latency_us
        $weight = [Math]::Max(1,$sc)
        $sum += ($avg * $weight)
        $count += $weight
        if($mx -gt $max)
        {
            $max = $mx
        }
    }

    return [pscustomobject]@{
        weighted_avg_us = [Math]::Round(($sum / [Math]::Max(1,$count)),2)
        max_us = $max
        samples = $count
        windows = $Rows.Count
    }
}

while((Get-Date) -lt $maxWaitUntil)
{
    $now = Get-Date
    $expRows = Get-ExpRows

    if(-not $experimentStart)
    {
        $newStart = $expRows |
            Where-Object { [long]$_.ts -ge $obsStartUnix -and $_.phase -eq "START" } |
            Sort-Object { [long]$_.ts } |
            Select-Object -First 1

        if($newStart)
        {
            $experimentStart = [DateTimeOffset]::FromUnixTimeSeconds([long]$newStart.ts).ToLocalTime().DateTime
            $watchUntil = $experimentStart.AddMinutes($PostStartObserveMinutes)
        }
    }

    $candRows = Get-CandRows
    $recentOpens = @($candRows | Where-Object { $_.stage -eq "PAPER_OPEN" } | Select-Object -Last 5)
    $latRows = Get-LatRows
    $lastLat = $latRows | Select-Object -Last 1
    $stateLines = if(Test-Path $statePath) { @(Get-Content $statePath -Tail 12) } else { @() }

    $snapshot = [pscustomobject]@{
        ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
        experiment_started = [bool]$experimentStart
        experiment_start = if($experimentStart) { $experimentStart.ToString("yyyy-MM-dd HH:mm:ss zzz") } else { "" }
        recent_paper_open_count = $recentOpens.Count
        recent_paper_open_sides = (@($recentOpens | ForEach-Object { $_.side })) -join ","
        last_latency_avg_us = if($lastLat) { [int]$lastLat.avg_local_latency_us } else { -1 }
        last_latency_max_us = if($lastLat) { [int]$lastLat.max_local_latency_us } else { -1 }
        runtime_state_tail = @($stateLines | Select-Object -First 4)
    }

    $snapshot | ConvertTo-Json -Depth 6 -Compress | Add-Content -Path $outJsonl

    if($experimentStart -and (Get-Date) -ge $watchUntil)
    {
        break
    }

    Start-Sleep -Seconds 60
}

$obsEnd = Get-Date
$expRows = Get-ExpRows
$candRows = Get-CandRows
$latRows = Get-LatRows

$anchor = if($experimentStart) { $experimentStart } else { $obsStart }
$preStart = $anchor.AddMinutes(-15)
$preEnd = $anchor
$postStart = $anchor
$postEnd = if($experimentStart) { $experimentStart.AddMinutes($PostStartObserveMinutes) } else { $obsEnd }
if($obsEnd -lt $postEnd)
{
    $postEnd = $obsEnd
}

$preStartUnix = ([DateTimeOffset]$preStart).ToUnixTimeSeconds()
$preEndUnix = ([DateTimeOffset]$preEnd).ToUnixTimeSeconds()
$postStartUnix = ([DateTimeOffset]$postStart).ToUnixTimeSeconds()
$postEndUnix = ([DateTimeOffset]$postEnd).ToUnixTimeSeconds()

$preCand = @($candRows | Where-Object {
    [long]$_.ts -ge $preStartUnix -and [long]$_.ts -lt $preEndUnix -and $_.stage -eq "PAPER_OPEN"
})
$postCand = @($candRows | Where-Object {
    [long]$_.ts -ge $postStartUnix -and [long]$_.ts -lt $postEndUnix -and $_.stage -eq "PAPER_OPEN"
})

$preLat = @($latRows | Where-Object { [long]$_.ts -ge $preStartUnix -and [long]$_.ts -lt $preEndUnix })
$postLat = @($latRows | Where-Object { [long]$_.ts -ge $postStartUnix -and [long]$_.ts -lt $postEndUnix })

$expWindowRows = if($experimentStart) {
    @($expRows | Where-Object { [long]$_.ts -ge $postStartUnix -and [long]$_.ts -lt $postEndUnix })
} else {
    @()
}

$result = [pscustomobject]@{
    observed_started_at = $obsStart.ToString("yyyy-MM-dd HH:mm:ss zzz")
    observed_finished_at = $obsEnd.ToString("yyyy-MM-dd HH:mm:ss zzz")
    experiment_started = [bool]$experimentStart
    experiment_started_at = if($experimentStart) { $experimentStart.ToString("yyyy-MM-dd HH:mm:ss zzz") } else { $null }
    pre_window = [pscustomobject]@{
        from = $preStart.ToString("yyyy-MM-dd HH:mm:ss zzz")
        to = $preEnd.ToString("yyyy-MM-dd HH:mm:ss zzz")
        paper_buy = @($preCand | Where-Object { $_.side -eq "BUY" }).Count
        paper_sell = @($preCand | Where-Object { $_.side -eq "SELL" }).Count
        paper_total = $preCand.Count
        latency = Get-LatSummary -Rows $preLat
    }
    post_window = [pscustomobject]@{
        from = $postStart.ToString("yyyy-MM-dd HH:mm:ss zzz")
        to = $postEnd.ToString("yyyy-MM-dd HH:mm:ss zzz")
        paper_buy = @($postCand | Where-Object { $_.side -eq "BUY" }).Count
        paper_sell = @($postCand | Where-Object { $_.side -eq "SELL" }).Count
        paper_total = $postCand.Count
        latency = Get-LatSummary -Rows $postLat
    }
    experiment_phases = @($expWindowRows | Select-Object ts,phase,experiment_status,experiment_revision,experiment_action_code,experiment_focus_setup_type,experiment_focus_market_regime,delta_samples,delta_wins,delta_losses,delta_paper_open_rows,delta_realized_pnl_lifetime,detail)
    snapshots_jsonl = $outJsonl
}

$result | ConvertTo-Json -Depth 8 | Set-Content -Path $outJson
Write-Output $outJson
