param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_LAB_DATA",
    [switch]$SkipProfileSweep,
    [double]$ProfileSweepMinIntervalHours = 6.0
)

$ErrorActionPreference = "Stop"
Set-Location -Path $Root

$pyVersionArgs = @()
try {
    & py -3.12 -c "import sys; print(sys.version)" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $pyVersionArgs = @("-3.12")
    }
} catch {
    $pyVersionArgs = @()
}

$argsList = @(
    "-B",
    "TOOLS\lab_insights_digest.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot
)

if (-not $SkipProfileSweep) {
    try {
        $sweepArgs = @(
            "-B",
            "TOOLS\lab_strategy_profile_sweep.py",
            "--root", $Root,
            "--lab-data-root", $LabDataRoot,
            "--min-interval-hours", [string]$ProfileSweepMinIntervalHours
        )
        py @($pyVersionArgs + $sweepArgs) | Out-Null
    } catch {
        # Digest ma przejść nawet gdy sweep się nie uda.
    }
}

py @($pyVersionArgs + $argsList)
