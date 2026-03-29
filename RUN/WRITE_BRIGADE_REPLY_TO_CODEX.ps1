param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [string]$BrigadeId = "",
    [string]$Actor = "",
    [ValidateSet("COMPLETED", "BLOCKED", "DELEGATED", "CANCELLED", "STATUS")]
    [string]$Outcome = "STATUS",
    [Parameter(Mandatory = $true)]
    [string]$Summary,
    [string[]]$Checked = @(),
    [string[]]$Confirmed = @(),
    [string[]]$Blockers = @(),
    [string[]]$ChangedFiles = @(),
    [string[]]$OutputArtifacts = @(),
    [string]$SaveStatus = "",
    [string[]]$DelegateWork = @(),
    [string]$CodexAction = "",
    [string]$NextAction = "",
    [string]$ReportPath = "",
    [string[]]$ScopePaths = @(),
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [string]$RegistryPath = "",
    [string[]]$Tags = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $repoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
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

if ([string]::IsNullOrWhiteSpace($Actor)) {
    if ([string]::IsNullOrWhiteSpace($BrigadeId)) {
        throw "Pass -Actor or -BrigadeId."
    }

    $registry = Read-JsonFile -Path $RegistryPath
    if ($null -eq $registry) {
        throw "Cannot read brigade registry: $RegistryPath"
    }

    $brigade = @($registry.brigades | Where-Object {
        [string]$_.brigade_id -eq $BrigadeId -or [string]$_.actor_id -eq $BrigadeId
    }) | Select-Object -First 1

    if ($null -eq $brigade) {
        throw "Unknown brigade: $BrigadeId"
    }

    $Actor = [string]$brigade.actor_id
}

$writerScriptPath = Join-Path $repoRoot "RUN\WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1"
if (-not (Test-Path -LiteralPath $writerScriptPath)) {
    throw "Missing execution result script: $writerScriptPath"
}

& $writerScriptPath `
    -TaskId $TaskId `
    -Actor $Actor `
    -Outcome $Outcome `
    -Summary $Summary `
    -Checked $Checked `
    -Confirmed $Confirmed `
    -Blockers $Blockers `
    -ChangedFiles $ChangedFiles `
    -OutputArtifacts $OutputArtifacts `
    -SaveStatus $SaveStatus `
    -DelegateWork $DelegateWork `
    -CodexAction $CodexAction `
    -NextAction $NextAction `
    -ReportPath $ReportPath `
    -ScopePaths $ScopePaths `
    -MailboxDir $MailboxDir `
    -RegistryPath $RegistryPath `
    -Tags $Tags
