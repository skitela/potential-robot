param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [int]$ChromeDebugPort = 9222,
    [string]$ChatUrl = "https://chatgpt.com/c/69c63027-795c-8390-9a23-d033b2e319cb"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$statusDir = Join-Path $MailboxDir "status"
$responsesReady = Join-Path $MailboxDir "responses\ready"
$responsesConsumed = Join-Path $MailboxDir "responses\consumed"
$requestsPending = Join-Path $MailboxDir "requests\pending"
$requestsInProgress = Join-Path $MailboxDir "requests\in_progress"
$requestsFailed = Join-Path $MailboxDir "requests\failed"

function Load-StatusJson {
    param([string]$Name)
    $path = Join-Path $statusDir ("{0}.json" -f $Name)
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        return $null
    }
}

$lastRequest = Load-StatusJson -Name "codex_last_request"
$lastResponse = Load-StatusJson -Name "gpt_last_response"
$lastError = Load-StatusJson -Name "orchestrator_error"
$launcher = Load-StatusJson -Name "launcher_latest"

$pendingMd = Get-ChildItem -LiteralPath $requestsPending -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$inProgressMd = Get-ChildItem -LiteralPath $requestsInProgress -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$failedMd = Get-ChildItem -LiteralPath $requestsFailed -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$readyMd = Get-ChildItem -LiteralPath $responsesReady -Filter *.md -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$consumedDirs = Get-ChildItem -LiteralPath $responsesConsumed -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

$summary = [pscustomobject]@{
    pending_requests = @($pendingMd).Count
    in_progress_requests = @($inProgressMd).Count
    failed_requests = @($failedMd).Count
    ready_responses = @($readyMd).Count
    consumed_responses = @($consumedDirs).Count
    last_request_file = if ($lastRequest) { [string]$lastRequest.path } else { "" }
    last_response_file = if ($lastResponse) { [string]$lastResponse.response_path } else { "" }
    chrome_debug_port = $ChromeDebugPort
    chat_url = if ($launcher -and $launcher.chat_url) { [string]$launcher.chat_url } else { $ChatUrl }
    last_error_summary = if ($lastError) { [string]$lastError.error } else { "" }
    mailbox_dir = $MailboxDir
}

$summary | Format-List
