param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [string]$OutputRoot = "",
    [switch]$SkipBridgeDelivery,
    [switch]$SkipDailyStatus,
    [switch]$SkipSyncManifest,
    [string]$NoteAuthor = "codex",
    [string]$NoteSourceRole = "local_agent"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $ProjectRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
}

$bridgeDeliveryScriptPath = Join-Path $ProjectRoot "RUN\SYNC_ORCHESTRATOR_BRIGADE_NOTES.ps1"
$dailyScriptPath = Join-Path $ProjectRoot "RUN\BUILD_BRIGADE_DAILY_STATUS.ps1"
$manifestScriptPath = Join-Path $ProjectRoot "RUN\BUILD_BRIGADE_SYNC_MANIFEST.ps1"

if (-not $SkipBridgeDelivery -and -not (Test-Path -LiteralPath $bridgeDeliveryScriptPath)) {
    throw "Missing bridge delivery script: $bridgeDeliveryScriptPath"
}

if (-not $SkipDailyStatus -and -not (Test-Path -LiteralPath $dailyScriptPath)) {
    throw "Missing daily status script: $dailyScriptPath"
}

if (-not $SkipSyncManifest -and -not (Test-Path -LiteralPath $manifestScriptPath)) {
    throw "Missing sync manifest script: $manifestScriptPath"
}

if (-not $SkipBridgeDelivery) {
    & $bridgeDeliveryScriptPath -ProjectRoot $ProjectRoot -MailboxDir $MailboxDir -RegistryPath $RegistryPath -OutputRoot $OutputRoot -PublishToNotes -NoteAuthor $NoteAuthor -NoteSourceRole $NoteSourceRole -NoteTags @("brigady", "most", "delivery", "auto") | Out-Null
}

if (-not $SkipDailyStatus) {
    & $dailyScriptPath -ProjectRoot $ProjectRoot -MailboxDir $MailboxDir -RegistryPath $RegistryPath -OutputRoot $OutputRoot -PublishToNotes -NoteAuthor $NoteAuthor -NoteSourceRole $NoteSourceRole -NoteTags @("brigady", "status_dzienny", "watch", "auto") | Out-Null
}

if (-not $SkipSyncManifest) {
    & $manifestScriptPath -ProjectRoot $ProjectRoot -MailboxDir $MailboxDir -RegistryPath $RegistryPath -OutputRoot $OutputRoot -PublishToNotes -NoteAuthor $NoteAuthor -NoteSourceRole $NoteSourceRole -NoteTags @("brigady", "sync_manifest", "auto") | Out-Null
}

$bridgeJsonPath = Join-Path $OutputRoot "bridge_note_delivery_latest.json"
$dailyJsonPath = Join-Path $OutputRoot "brigade_daily_status_latest.json"
$manifestJsonPath = Join-Path $OutputRoot "brigade_sync_manifest_latest.json"

$bridgePayload = if ((-not $SkipBridgeDelivery) -and (Test-Path -LiteralPath $bridgeJsonPath)) { Get-Content -LiteralPath $bridgeJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50 } else { $null }
$dailyPayload = if ((-not $SkipDailyStatus) -and (Test-Path -LiteralPath $dailyJsonPath)) { Get-Content -LiteralPath $dailyJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50 } else { $null }
$manifestPayload = if ((-not $SkipSyncManifest) -and (Test-Path -LiteralPath $manifestJsonPath)) { Get-Content -LiteralPath $manifestJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50 } else { $null }

[pscustomobject]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    bridge_delivery_note_title = if ($null -ne $bridgePayload) { [string]$bridgePayload.published_note_title } else { "" }
    bridge_delivery_note_path = if ($null -ne $bridgePayload) { [string]$bridgePayload.published_note_path } else { "" }
    bridge_delivery_verdict = if ($null -ne $bridgePayload) { [string]$bridgePayload.overall_verdict } else { "" }
    daily_status_note_title = if ($null -ne $dailyPayload) { [string]$dailyPayload.published_note_title } else { "" }
    daily_status_note_path = if ($null -ne $dailyPayload) { [string]$dailyPayload.published_note_path } else { "" }
    daily_status_verdict = if ($null -ne $dailyPayload) { [string]$dailyPayload.overall_verdict } else { "" }
    sync_manifest_note_title = if ($null -ne $manifestPayload) { [string]$manifestPayload.published_note_title } else { "" }
    sync_manifest_note_path = if ($null -ne $manifestPayload) { [string]$manifestPayload.published_note_path } else { "" }
    sync_manifest_verdict = if ($null -ne $manifestPayload) { [string]$manifestPayload.overall_verdict } else { "" }
    bridge_delivery_json = if ($null -ne $bridgePayload) { $bridgeJsonPath } else { "" }
    daily_status_json = if ($null -ne $dailyPayload) { $dailyJsonPath } else { "" }
    sync_manifest_json = if ($null -ne $manifestPayload) { $manifestJsonPath } else { "" }
} | Format-List