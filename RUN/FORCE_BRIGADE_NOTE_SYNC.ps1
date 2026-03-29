param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [int]$Limit = 10,
    [switch]$NoPublishToNotes,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $ProjectRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

$syncScriptPath = Join-Path $ProjectRoot "RUN\SYNC_ORCHESTRATOR_BRIGADE_NOTES.ps1"
if (-not (Test-Path -LiteralPath $syncScriptPath)) {
    throw "Missing sync script: $syncScriptPath"
}

$arguments = @{
    ProjectRoot = $ProjectRoot
    MailboxDir = $MailboxDir
    RegistryPath = $RegistryPath
    Limit = $Limit
}

if (-not $NoPublishToNotes) {
    $arguments.PublishToNotes = $true
}

$result = & $syncScriptPath @arguments
if ($AsJson) {
    $result | ConvertTo-Json -Depth 30
    return
}

$result
