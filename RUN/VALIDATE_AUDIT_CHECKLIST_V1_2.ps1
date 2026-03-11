param(
    [string]$Root = "",
    [string]$Report = "",
    [string]$Out = "",
    [string]$EvidenceRoot = ""
)

$ErrorActionPreference = "Stop"

function Resolve-PythonExe {
    param([string]$RuntimeRoot)
    $candidates = @(
        (Join-Path $RuntimeRoot ".venv\Scripts\python.exe"),
        "C:\OANDA_VENV\.venv\Scripts\python.exe",
        "C:\Program Files\Python312\python.exe"
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
    }
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
        return $cmd.Source
    }
    throw "Python executable not found for VALIDATE_AUDIT_CHECKLIST_V1_2."
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}
$pythonExe = Resolve-PythonExe -RuntimeRoot $Root

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $preferred = Join-Path $Root "EVIDENCE\audit_v12_live"
    $legacy = Join-Path $Root "EVIDENCE\audit_checklist_v1_2"
    if (Test-Path $preferred -PathType Container) {
        $EvidenceRoot = $preferred
    } elseif (Test-Path $legacy -PathType Container) {
        $EvidenceRoot = $legacy
    } else {
        $EvidenceRoot = $preferred
    }
} elseif (-not [System.IO.Path]::IsPathRooted($EvidenceRoot)) {
    $EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $Root $EvidenceRoot))
} else {
    $EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
}

$validator = Join-Path $Root "TOOLS\validate_audit_checklist_v1_2.py"
if (-not (Test-Path $validator -PathType Leaf)) {
    Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] ERROR: missing validator: $validator"
    exit 2
}

if ([string]::IsNullOrWhiteSpace($Report)) {
    if (-not (Test-Path $EvidenceRoot -PathType Container)) {
        Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] ERROR: missing evidence root: $EvidenceRoot"
        exit 2
    }
    $latest = Get-ChildItem -Path $EvidenceRoot -Recurse -File -Filter "AUDIT_REPORT_V1_2*.md" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] ERROR: no report found under $EvidenceRoot"
        exit 2
    }
    $Report = $latest.FullName
} elseif (-not [System.IO.Path]::IsPathRooted($Report)) {
    $Report = [System.IO.Path]::GetFullPath((Join-Path $Root $Report))
} else {
    $Report = [System.IO.Path]::GetFullPath($Report)
}

if (-not (Test-Path $Report -PathType Leaf)) {
    Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] ERROR: report not found: $Report"
    exit 2
}

if ([string]::IsNullOrWhiteSpace($Out)) {
    $Out = Join-Path (Split-Path $Report -Parent) "validate_latest.json"
} elseif (-not [System.IO.Path]::IsPathRooted($Out)) {
    $Out = [System.IO.Path]::GetFullPath((Join-Path $Root $Out))
} else {
    $Out = [System.IO.Path]::GetFullPath($Out)
}

$outDir = Split-Path $Out -Parent
if (-not [string]::IsNullOrWhiteSpace($outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] Root=$Root"
Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] Report=$Report"
Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] Out=$Out"
Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] Python=$pythonExe"

& $pythonExe $validator --report $Report --out $Out
$rc = [int]$LASTEXITCODE

Write-Host "[VALIDATE_AUDIT_CHECKLIST_V1_2] ExitCode=$rc"
exit $rc
