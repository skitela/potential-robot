param(
    [string]$MailboxDir = "C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox",
    [switch]$LatestOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$holdDir = Join-Path $MailboxDir "requests\hold"
$pendingDir = Join-Path $MailboxDir "requests\pending"
New-Item -ItemType Directory -Force -Path $pendingDir | Out-Null

if (-not (Test-Path -LiteralPath $holdDir)) {
    Write-Output "No hold directory."
    exit 0
}

$heldMd = Get-ChildItem -LiteralPath $holdDir -Filter *.md -File | Sort-Object LastWriteTime
if ($LatestOnly) {
    $heldMd = @($heldMd | Select-Object -Last 1)
}

foreach ($md in $heldMd) {
    $targetMd = Join-Path $pendingDir $md.Name
    Move-Item -LiteralPath $md.FullName -Destination $targetMd -Force
    $sidecar = [IO.Path]::ChangeExtension($md.FullName, ".json")
    if (Test-Path -LiteralPath $sidecar) {
        Move-Item -LiteralPath $sidecar -Destination (Join-Path $pendingDir ([IO.Path]::GetFileName($sidecar))) -Force
    }
    Write-Output $targetMd
}
