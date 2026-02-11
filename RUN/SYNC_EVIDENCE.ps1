param(
    [Parameter(Mandatory = $true)]
    [string]$SourceEvidence,
    [string]$TargetEvidence = "C:\agentkotweight\EVIDENCE",
    [switch]$Mirror
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SourceEvidence)) {
    Write-Error "Source evidence directory not found: $SourceEvidence"
}

$sourceResolved = (Resolve-Path $SourceEvidence).Path
if (-not (Test-Path $TargetEvidence)) {
    New-Item -ItemType Directory -Force -Path $TargetEvidence | Out-Null
}
$targetResolved = (Resolve-Path $TargetEvidence).Path

$args = @("/R:2", "/W:1", "/NP")
if ($Mirror) {
    $args += "/MIR"
} else {
    $args += "/E"
}

Write-Host "[SYNC_EVIDENCE] Source=$sourceResolved"
Write-Host "[SYNC_EVIDENCE] Target=$targetResolved"
Write-Host "[SYNC_EVIDENCE] Mode=$([string]::Join(' ', $args))"

& robocopy $sourceResolved $targetResolved @args
$rc = $LASTEXITCODE

if ($rc -le 7) {
    Write-Host "[SYNC_EVIDENCE] Result=PASS Code=$rc"
    exit 0
}

Write-Error "[SYNC_EVIDENCE] Result=FAIL Code=$rc"
