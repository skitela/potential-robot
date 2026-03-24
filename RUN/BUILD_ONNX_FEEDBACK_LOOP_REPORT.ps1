param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$DbPath = "C:\TRADING_DATA\RESEARCH\microbot_research.duckdb",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$OutcomeHorizonSec = 21600,
    [double]$ScoreThreshold = 0.5,
    [int]$RetryCount = 6,
    [int]$RetryDelaySeconds = 10,
    [int]$FreshReportThresholdSeconds = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pythonExe = Join-Path $EnvRoot "Scripts\python.exe"
$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_ONNX_FEEDBACK_LOOP_REPORT.py"

if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Research python not found: $pythonExe"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "ONNX feedback report script not found: $scriptPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$latestReportPath = Join-Path $OutputRoot "onnx_feedback_loop_latest.json"

function Get-FeedbackPythonProcessCount {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "python.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*BUILD_ONNX_FEEDBACK_LOOP_REPORT.py*"
            }
    ).Count
}

function Get-FileAgeSecondsOrMax {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int]::MaxValue
    }

    return [int][math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds)
}

$attempt = 0
while ($true) {
    $attempt++
    $activeFeedbackProcesses = Get-FeedbackPythonProcessCount
    if ($activeFeedbackProcesses -gt 0) {
        $reportAgeSeconds = Get-FileAgeSecondsOrMax -Path $latestReportPath
        if ($reportAgeSeconds -le [Math]::Max(60, $FreshReportThresholdSeconds)) {
            Write-Host "ONNX feedback already refreshed by another runner; skipping duplicate cycle."
            return
        }

        if ($attempt -lt [Math]::Max(1, $RetryCount)) {
            Start-Sleep -Seconds ([Math]::Max(1, $RetryDelaySeconds))
            continue
        }

        throw "onnx_feedback_runner_already_active_and_report_is_stale"
    }

    try {
        $output = & $pythonExe $scriptPath `
            --research-root $ResearchRoot `
            --db-path $DbPath `
            --output-root $OutputRoot `
            --outcome-horizon-sec $OutcomeHorizonSec `
            --score-threshold $ScoreThreshold 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $compact = (($output -replace '\s+', ' ').Trim())
            throw "python_exit_code=$LASTEXITCODE output=$compact"
        }
        break
    }
    catch {
        $message = $_.Exception.Message
        $isTransientLock = (
            $message -like "*used by another process*" -or
            $message -like "*already open*" -or
            $message -like "*odmowa dostepu*" -or
            $message -like "*uzywany przez inny proces*" -or
            $message -like "*IOException*"
        )

        if ($isTransientLock -and $attempt -lt [Math]::Max(1, $RetryCount)) {
            Start-Sleep -Seconds ([Math]::Max(1, $RetryDelaySeconds))
            continue
        }

        throw
    }
}
