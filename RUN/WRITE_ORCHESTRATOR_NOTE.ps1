param(
    [string]$Title = "",
    [string]$Text = "",
    [string]$SourcePath = "",
    [switch]$FromClipboard,
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$Author = "codex",
    [string]$SourceRole = "local_agent",
    [string]$TargetActor = "",
    [string]$TargetBrigadeId = "",
    [string]$RequestOwnerActor = "",
    [string]$RequestOwnerBrigadeId = "",
    [string]$ReportToActor = "",
    [string]$ReportToBrigadeId = "",
    [string[]]$ObserverActors = @(),
    [ValidateSet("ALL_BRIGADES_READ", "TARGET_PLUS_OBSERVERS", "TARGET_ONLY")]
    [string]$Visibility = "ALL_BRIGADES_READ",
    [ValidateSet("INFO", "QUESTION", "ACTION_REQUEST", "AUDIT_REQUEST", "HANDOFF", "STATUS", "DECISION")]
    [string]$ExecutionIntent = "INFO",
    [ValidateSet("BROADCAST_READ_ONLY", "TARGET_ONLY_AFTER_REVIEW", "SHARED_REVIEW")]
    [string]$ExecutionPolicy = "",
    [ValidateSet("READ_ONLY", "READ_AND_ESCALATE_IF_NEEDED", "READ_AND_SUPPORT_IF_ASKED")]
    [string]$NonTargetPolicy = "READ_AND_ESCALATE_IF_NEEDED",
    [Nullable[bool]]$RequiresSafetyReview = $null,
    [string]$RelatedRequestId = "",
    [string[]]$Tags = @(),
    [string]$RegistryPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TextSha256 {
    param([string]$Body)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $hash = $sha.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $sha.Dispose()
    }
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        return $null
    }
}

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $value = $Object.$Name
        if ($null -ne $value) {
            return $value
        }
    }

    return $Default
}

function Resolve-BrigadeByActor {
    param(
        [object]$Registry,
        [string]$ActorId
    )

    if ($null -eq $Registry -or [string]::IsNullOrWhiteSpace($ActorId)) {
        return $null
    }

    return @($Registry.brigades | Where-Object { [string]$_.actor_id -eq $ActorId }) | Select-Object -First 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
}

if ($FromClipboard) {
    $Text = Get-Clipboard -Raw
}

if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Missing source file: $SourcePath"
    }
    $Text = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($Text)) {
    throw "Provide -Text, -SourcePath or use -FromClipboard."
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = if (-not [string]::IsNullOrWhiteSpace($SourcePath)) { [IO.Path]::GetFileNameWithoutExtension($SourcePath) } else { "Bridge note" }
}

$registry = Read-JsonFile -Path $RegistryPath
$policy = Get-OptionalValue -Object $registry -Name "message_handling_policy" -Default $null
$informationAdminActor = [string](Get-OptionalValue -Object $policy -Name "information_admin_actor_id" -Default "")
$informationAdminBrigadeId = [string](Get-OptionalValue -Object $policy -Name "information_admin_brigade_id" -Default "")
$effectiveRequestOwnerActor = if ([string]::IsNullOrWhiteSpace($RequestOwnerActor)) { $Author } else { $RequestOwnerActor }
$effectiveRequestOwnerBrigadeId = $RequestOwnerBrigadeId
$requestOwnerBrigade = $null
if ([string]::IsNullOrWhiteSpace($effectiveRequestOwnerBrigadeId)) {
    $requestOwnerBrigade = Resolve-BrigadeByActor -Registry $registry -ActorId $effectiveRequestOwnerActor
    if ($null -ne $requestOwnerBrigade) {
        $effectiveRequestOwnerBrigadeId = [string]$requestOwnerBrigade.brigade_id
    }
}
$effectiveTargetActor = $TargetActor
$effectiveTargetBrigadeId = $TargetBrigadeId
$effectiveReportToActor = $ReportToActor
$effectiveReportToBrigadeId = $ReportToBrigadeId
$policyDefaultReportToActor = [string](Get-OptionalValue -Object $policy -Name "default_report_to_actor" -Default "")
$policyDefaultReportToBrigadeId = [string](Get-OptionalValue -Object $policy -Name "default_report_to_brigade_id" -Default "")

if ([bool](Get-OptionalValue -Object $policy -Name "request_owner_must_be_declared" -Default $false) -and [string]::IsNullOrWhiteSpace($effectiveRequestOwnerActor)) {
    throw "Request owner actor is required by message policy. Pass -RequestOwnerActor or set -Author."
}

if ([string]::IsNullOrWhiteSpace($effectiveReportToActor)) {
    $effectiveReportToActor = $policyDefaultReportToActor
}
if ([string]::IsNullOrWhiteSpace($effectiveReportToBrigadeId)) {
    $effectiveReportToBrigadeId = $policyDefaultReportToBrigadeId
}

if ([string]::IsNullOrWhiteSpace($effectiveReportToActor)) {
    $effectiveReportToActor = $effectiveRequestOwnerActor
}
if ([string]::IsNullOrWhiteSpace($effectiveReportToBrigadeId)) {
    $effectiveReportToBrigadeId = $effectiveRequestOwnerBrigadeId
}

$mustDeclareProcessingOwner = [bool](Get-OptionalValue -Object $policy -Name "processing_owner_must_be_declared" -Default $false)
if ($mustDeclareProcessingOwner -and [string]::IsNullOrWhiteSpace($effectiveTargetActor) -and [string]::IsNullOrWhiteSpace($effectiveTargetBrigadeId)) {
    $effectiveTargetActor = $informationAdminActor
    $effectiveTargetBrigadeId = $informationAdminBrigadeId
}

if ([string]::IsNullOrWhiteSpace($effectiveReportToActor) -and -not [string]::IsNullOrWhiteSpace($effectiveTargetActor)) {
    $effectiveReportToActor = $effectiveTargetActor
}
if ([string]::IsNullOrWhiteSpace($effectiveReportToBrigadeId) -and -not [string]::IsNullOrWhiteSpace($effectiveTargetBrigadeId)) {
    $effectiveReportToBrigadeId = $effectiveTargetBrigadeId
}

$hasProcessingTarget = -not [string]::IsNullOrWhiteSpace($effectiveTargetActor) -or -not [string]::IsNullOrWhiteSpace($effectiveTargetBrigadeId)

$effectiveExecutionPolicy = $ExecutionPolicy
if ([string]::IsNullOrWhiteSpace($effectiveExecutionPolicy)) {
    $effectiveExecutionPolicy = if ($hasProcessingTarget -and $ExecutionIntent -in @("ACTION_REQUEST", "AUDIT_REQUEST", "HANDOFF", "DECISION")) {
        "TARGET_ONLY_AFTER_REVIEW"
    }
    else {
        "BROADCAST_READ_ONLY"
    }
}

$effectiveSafetyReview = $RequiresSafetyReview
if ($null -eq $effectiveSafetyReview) {
    $effectiveSafetyReview = ($ExecutionIntent -in @("ACTION_REQUEST", "AUDIT_REQUEST", "HANDOFF", "DECISION"))
}

$notesInbox = Join-Path $MailboxDir "notes\inbox"
New-Item -ItemType Directory -Force -Path $notesInbox | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeAuthor = ($Author -replace '[^A-Za-z0-9._-]','_')
$safeTitle = ($Title -replace '[^A-Za-z0-9._-]','_')
$noteId = "{0}_{1}_{2}" -f $timestamp, $safeAuthor, $safeTitle
$notePath = Join-Path $notesInbox ("{0}.md" -f $noteId)
$metaPath = Join-Path $notesInbox ("{0}.json" -f $noteId)

Set-Content -LiteralPath $notePath -Value $Text -Encoding UTF8

$meta = [ordered]@{
    note_id = $noteId
    title = $Title
    author = $Author
    source = $SourceRole
    request_owner_actor = $effectiveRequestOwnerActor
    request_owner_brigade_id = $effectiveRequestOwnerBrigadeId
    target_actor = $effectiveTargetActor
    target_brigade_id = $effectiveTargetBrigadeId
    report_to_actor = $effectiveReportToActor
    report_to_brigade_id = $effectiveReportToBrigadeId
    information_admin_actor_id = $informationAdminActor
    information_admin_brigade_id = $informationAdminBrigadeId
    observer_actors = @($ObserverActors)
    visibility = $Visibility
    execution_intent = $ExecutionIntent
    execution_policy = $effectiveExecutionPolicy
    non_target_policy = $NonTargetPolicy
    requires_safety_review = [bool]$effectiveSafetyReview
    note_path = $notePath
    written_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    sha256 = Get-TextSha256 -Body $Text
}

if (-not [string]::IsNullOrWhiteSpace($RelatedRequestId)) {
    $meta["request_id"] = $RelatedRequestId
}
if (@($Tags).Count -gt 0) {
    $meta["tags"] = @($Tags)
}
if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
    $meta["source_path"] = $SourcePath
}

$meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metaPath -Encoding UTF8
Write-Output $notePath
