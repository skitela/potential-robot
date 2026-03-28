param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox"
)

$statusDir = Join-Path $MailboxDir "status"
$responsesReady = Join-Path $MailboxDir "responses\ready"
$responsesConsumed = Join-Path $MailboxDir "responses\consumed"
$requestsPending = Join-Path $MailboxDir "requests\pending"

[pscustomobject]@{
    pending_requests = (Get-ChildItem -LiteralPath $requestsPending -Filter *.md -ErrorAction SilentlyContinue | Measure-Object).Count
    ready_responses = (Get-ChildItem -LiteralPath $responsesReady -Filter *.md -ErrorAction SilentlyContinue | Measure-Object).Count
    consumed_responses = (Get-ChildItem -LiteralPath $responsesConsumed -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
    mailbox_dir = $MailboxDir
} | Format-List

Get-ChildItem -LiteralPath $statusDir -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object Name, LastWriteTime, Length |
    Format-Table -AutoSize
