param(
    [string]$DesktopAgentDir = "C:\Users\skite\Desktop\strojenie agenta",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$ChatUrl = "https://chatgpt.com/c/69c63027-795c-8390-9a23-d033b2e319cb"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$queueScript = "C:\MAKRO_I_MIKRO_BOT\RUN\QUEUE_FILE_FOR_GPT54_PRO.ps1"
$startScript = "C:\MAKRO_I_MIKRO_BOT\RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1"
$importScript = "C:\MAKRO_I_MIKRO_BOT\RUN\IMPORT_GPT54_READY_RESPONSE.ps1"
$evidenceJson = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\orchestrator_smoke_latest.json"
$evidenceMd = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\orchestrator_smoke_latest.md"
$promptPath = Join-Path $DesktopAgentDir "PROMPT_GPT54_PRO_ORCHESTRATOR_SMOKE_TEST_v1.md"
$expectedToken = @(
    "RECEIVED: YES",
    "TOKEN: ORCH_SMOKE_OK_20260328",
    "MODE: REVIEWER",
    "TOPIC: MAKRO_I_MIKRO_BOT",
    "NEXT_STEP: READY_FOR_NEXT_REQUEST"
) -join [Environment]::NewLine

New-Item -ItemType Directory -Force -Path $DesktopAgentDir | Out-Null
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($evidenceJson)) | Out-Null

if (-not (Test-Path -LiteralPath $promptPath)) {
    @"
Odpowiedz dokladnie i tylko tym tekstem, bez komentarza przed ani po:

RECEIVED: YES
TOKEN: ORCH_SMOKE_OK_20260328
MODE: REVIEWER
TOPIC: MAKRO_I_MIKRO_BOT
NEXT_STEP: READY_FOR_NEXT_REQUEST
"@ | Set-Content -LiteralPath $promptPath -Encoding UTF8
}

$requestPath = & $queueScript -SourcePath $promptPath -Title "Orchestrator smoke test"
$requestFile = [string]$requestPath
$requestQueued = Test-Path -LiteralPath $requestFile
$requestId = [IO.Path]::GetFileNameWithoutExtension($requestFile)

$responseJson = Join-Path (Join-Path $MailboxDir "responses\ready") ("{0}_response.json" -f $requestId)
$responseMd = Join-Path (Join-Path $MailboxDir "responses\ready") ("{0}_response.md" -f $requestId)

$errorMessage = ""
$responseReady = $false
$responseImported = $false
$tokenMatch = $false

try {
    & $startScript -Mode process-once | Out-Null

    $deadline = (Get-Date).AddMinutes(20)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $responseJson) -and (Test-Path -LiteralPath $responseMd)) {
            $responseReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }

    if (-not $responseReady) {
        throw "Smoke test nie doczekal sie odpowiedzi GPT w limicie czasu."
    }

    & $importScript -ResponsePath $responseJson | Out-Null
    $responseImported = $true

    $content = Get-Content -LiteralPath $responseMd -Raw -Encoding UTF8
    $tokenMatch = ($content.Trim() -eq $expectedToken.Trim())
    if (-not $tokenMatch) {
        throw "Odpowiedz GPT nie zawiera dokladnego tokenu sukcesu."
    }
}
catch {
    $errorMessage = $_.Exception.Message
}

$smokeOk = $requestQueued -and $responseReady -and $responseImported -and $tokenMatch -and [string]::IsNullOrWhiteSpace($errorMessage)
$chromeProfile = ""
$launcherStatusPath = Join-Path (Join-Path $MailboxDir "status") "launcher_latest.json"
if (Test-Path -LiteralPath $launcherStatusPath) {
    try {
        $launcher = Get-Content -LiteralPath $launcherStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        $chromeProfile = [string]$launcher.chrome_profile
    }
    catch {
        $chromeProfile = ""
    }
}

$payload = [ordered]@{
    smoke_ok = $smokeOk
    request_queued = $requestQueued
    response_ready = $responseReady
    response_imported = $responseImported
    token_match = $tokenMatch
    chat_url = $ChatUrl
    chrome_profile = $chromeProfile
    mailbox_root = $MailboxDir
    request_file = $requestFile
    response_file = $responseMd
    error_message = $errorMessage
    completed_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidenceJson -Encoding UTF8

$md = @(
    "# Orchestrator Smoke Test"
    ""
    "- smoke_ok: $($payload.smoke_ok)"
    "- request_queued: $($payload.request_queued)"
    "- response_ready: $($payload.response_ready)"
    "- response_imported: $($payload.response_imported)"
    "- token_match: $($payload.token_match)"
    "- chat_url: $($payload.chat_url)"
    "- chrome_profile: $($payload.chrome_profile)"
    "- mailbox_root: $($payload.mailbox_root)"
    "- request_file: $($payload.request_file)"
    "- response_file: $($payload.response_file)"
    "- error_message: $($payload.error_message)"
    "- completed_at_local: $($payload.completed_at_local)"
) -join [Environment]::NewLine

$md | Set-Content -LiteralPath $evidenceMd -Encoding UTF8
$payload | Format-List
