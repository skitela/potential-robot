param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$DbPath = "C:\TRADING_DATA\RESEARCH\microbot_research.duckdb",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$OutcomeHorizonSec = 21600,
    [double]$ScoreThreshold = 0.5,
    [int]$RetryCount = 6,
    [int]$RetryDelaySeconds = 10
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

$attempt = 0
while ($true) {
    $attempt++
    try {
        & $pythonExe $scriptPath `
            --db-path $DbPath `
            --output-root $OutputRoot `
            --outcome-horizon-sec $OutcomeHorizonSec `
            --score-threshold $ScoreThreshold
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
