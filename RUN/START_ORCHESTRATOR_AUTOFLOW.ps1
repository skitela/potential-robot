param(
    [string]$RepoRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$orchestratorStart = Join-Path $RepoRoot "RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1"
$watcherStart = Join-Path $RepoRoot "RUN\START_ORCHESTRATOR_RESPONSE_WATCH.ps1"
$opsJson = Join-Path $RepoRoot "EVIDENCE\OPS\orchestrator_autoflow_latest.json"

function Find-ExistingProcess {
    param([string]$Needle)
    Get-CimInstance Win32_Process |
        Where-Object { $_.Name -match 'powershell|pwsh' -and $_.CommandLine -like "*$Needle*" } |
        Select-Object -First 1
}

$orchProc = Find-ExistingProcess -Needle "START_CHATGPT_CODEX_ORCHESTRATOR.ps1 -Mode run"
if ($null -eq $orchProc) {
    $orch = Start-Process -FilePath "pwsh" -ArgumentList @("-File", $orchestratorStart, "-Mode", "run") -WorkingDirectory $RepoRoot -WindowStyle Hidden -PassThru
    $orchPid = $orch.Id
}
else {
    $orchPid = $orchProc.ProcessId
}

$watchProc = Find-ExistingProcess -Needle "START_ORCHESTRATOR_RESPONSE_WATCH.ps1 -Mode run"
if ($null -eq $watchProc) {
    $watch = Start-Process -FilePath "pwsh" -ArgumentList @("-File", $watcherStart, "-Mode", "run") -WorkingDirectory $RepoRoot -WindowStyle Hidden -PassThru
    $watchPid = $watch.Id
}
else {
    $watchPid = $watchProc.ProcessId
}

$payload = [ordered]@{
    repo_root = $RepoRoot
    orchestrator_pid = $orchPid
    response_watch_pid = $watchPid
    started_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($opsJson)) | Out-Null
$payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $opsJson -Encoding UTF8
$payload | Format-List
