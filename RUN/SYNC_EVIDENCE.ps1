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

$robocopyOut = & robocopy $sourceResolved $targetResolved @args 2>&1
$robocopyOut | ForEach-Object { $_ }
$rc = $LASTEXITCODE
$robocopyText = ($robocopyOut | Out-String)
$fatalByLog = $false
if ($robocopyText -match "ERROR 5") { $fatalByLog = $true }
if ($robocopyText -match "RETRY LIMIT EXCEEDED") { $fatalByLog = $true }
if ($robocopyText -match "Accessing Destination Directory") { $fatalByLog = $true }

if ($rc -le 7 -and -not $fatalByLog) {
    Write-Host "[SYNC_EVIDENCE] Result=PASS Code=$rc"
    exit 0
}

Write-Error "[SYNC_EVIDENCE] Result=FAIL Code=$rc FatalByLog=$fatalByLog"
