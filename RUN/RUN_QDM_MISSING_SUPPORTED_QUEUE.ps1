param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RunnerPath = "C:\MAKRO_I_MIKRO_BOT\RUN\RUN_QDM_MISSING_SUPPORTED_SYNC.ps1",
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_supported_sync_latest.json",
    [int]$MaxIterations = 12,
    [int]$PauseSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-QueueStatus {
    param(
        [string]$Path,
        [string]$QueueState,
        [int]$Iteration,
        [int]$MaxIterations
    )

    $payload = Read-JsonSafe -Path $Path
    if ($null -eq $payload) {
        return
    }

    $payload | Add-Member -NotePropertyName queue_state -NotePropertyValue $QueueState -Force
    $payload | Add-Member -NotePropertyName queue_iteration -NotePropertyValue $Iteration -Force
    $payload | Add-Member -NotePropertyName queue_max_iterations -NotePropertyValue $MaxIterations -Force
    $payload | Add-Member -NotePropertyName queue_generated_at_utc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o")) -Force
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $RunnerPath)) {
    throw "Missing runner script: $RunnerPath"
}

for ($iteration = 1; $iteration -le [Math]::Max(1, $MaxIterations); $iteration++) {
    Write-Host ("[QDM-QUEUE] Iteracja {0}/{1}" -f $iteration, $MaxIterations)
    $result = & $RunnerPath | ConvertFrom-Json
    $state = [string]$result.state
    $pendingCount = [int]$result.qdm_missing_count + [int]$result.qdm_refresh_required_count

    if ($pendingCount -le 0 -or $state -eq "completed") {
        Write-QueueStatus -Path $LatestStatusPath -QueueState "queue_completed" -Iteration $iteration -MaxIterations $MaxIterations
        break
    }

    if ($state -in @("failed", "blocked_no_batch", "export_in_progress")) {
        Write-QueueStatus -Path $LatestStatusPath -QueueState "queue_blocked" -Iteration $iteration -MaxIterations $MaxIterations
        break
    }

    if ($iteration -ge $MaxIterations) {
        Write-QueueStatus -Path $LatestStatusPath -QueueState "queue_reached_iteration_limit" -Iteration $iteration -MaxIterations $MaxIterations
        break
    }

    Write-QueueStatus -Path $LatestStatusPath -QueueState "queue_waiting_next_batch" -Iteration $iteration -MaxIterations $MaxIterations
    Start-Sleep -Seconds ([Math]::Max(5, $PauseSeconds))
}
