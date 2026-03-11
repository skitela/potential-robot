param(
    [string]$Root = "",
    [string]$EvidenceRoot = "",
    [string]$RunId = "",
    [string]$Out = "",
    [switch]$NoValidate
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
    throw "Python executable not found for GENERATE_AUDIT_REPORT_V1_2."
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}
$pythonExe = Resolve-PythonExe -RuntimeRoot $Root

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $Root "EVIDENCE\audit_v12_live"
} elseif (-not [System.IO.Path]::IsPathRooted($EvidenceRoot)) {
    $EvidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $Root $EvidenceRoot))
} else {
    $EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
}

if (-not [string]::IsNullOrWhiteSpace($Out)) {
    if (-not [System.IO.Path]::IsPathRooted($Out)) {
        $Out = [System.IO.Path]::GetFullPath((Join-Path $Root $Out))
    } else {
        $Out = [System.IO.Path]::GetFullPath($Out)
    }
}

$generator = Join-Path $Root "TOOLS\generate_audit_report_v1_2.py"
if (-not (Test-Path $generator -PathType Leaf)) {
    Write-Host "[GENERATE_AUDIT_REPORT_V1_2] ERROR: missing generator: $generator"
    exit 2
}

$argsList = @(
    $generator,
    "--root", $Root,
    "--evidence-root", $EvidenceRoot
)

if (-not [string]::IsNullOrWhiteSpace($RunId)) {
    $argsList += @("--run-id", $RunId.Trim())
}

if (-not [string]::IsNullOrWhiteSpace($Out)) {
    $argsList += @("--out", $Out)
}

if (-not $NoValidate) {
    $argsList += "--validate"
}

Write-Host "[GENERATE_AUDIT_REPORT_V1_2] Root=$Root"
Write-Host "[GENERATE_AUDIT_REPORT_V1_2] EvidenceRoot=$EvidenceRoot"
Write-Host "[GENERATE_AUDIT_REPORT_V1_2] Python=$pythonExe"
if (-not [string]::IsNullOrWhiteSpace($RunId)) {
    Write-Host "[GENERATE_AUDIT_REPORT_V1_2] RunId=$RunId"
}
if (-not [string]::IsNullOrWhiteSpace($Out)) {
    Write-Host "[GENERATE_AUDIT_REPORT_V1_2] Out=$Out"
}
Write-Host "[GENERATE_AUDIT_REPORT_V1_2] Validate=$([bool](-not $NoValidate))"

& $pythonExe @argsList
$rc = [int]$LASTEXITCODE

Write-Host "[GENERATE_AUDIT_REPORT_V1_2] ExitCode=$rc"
exit $rc
