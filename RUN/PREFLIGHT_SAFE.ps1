param(
    [string]$Root = "",
    [string]$Evidence = "",
    [int]$Loops = 1,
    [string]$SyncTarget = "C:\agentkotweight\EVIDENCE",
    [switch]$NoSync
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

if ([string]::IsNullOrWhiteSpace($Evidence)) {
    $runId = Get-Date -Format "yyyyMMdd_HHmmss"
    $Evidence = Join-Path $Root "EVIDENCE\preflight_safe\$runId"
} elseif (-not [System.IO.Path]::IsPathRooted($Evidence)) {
    $Evidence = [System.IO.Path]::GetFullPath((Join-Path $Root $Evidence))
} else {
    $Evidence = [System.IO.Path]::GetFullPath($Evidence)
}

New-Item -ItemType Directory -Force -Path $Evidence | Out-Null

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Command,
        [string]$LogPath
    )

    "COMMAND: $Command" | Set-Content -Encoding UTF8 $LogPath
    $stdoutPath = Join-Path $env:TEMP ("preflight_{0}_{1}.stdout.tmp" -f $Name, ([guid]::NewGuid().ToString("N")))
    $stderrPath = Join-Path $env:TEMP ("preflight_{0}_{1}.stderr.tmp" -f $Name, ([guid]::NewGuid().ToString("N")))
    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/d", "/c", $Command -WorkingDirectory $Root -Wait -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $code = [int]$proc.ExitCode

    if (Test-Path $stdoutPath) {
        Get-Content $stdoutPath | Add-Content -Encoding UTF8 $LogPath
        Remove-Item $stdoutPath -Force
    }
    if (Test-Path $stderrPath) {
        Get-Content $stderrPath | Add-Content -Encoding UTF8 $LogPath
        Remove-Item $stderrPath -Force
    }

    "EXIT_CODE: $code" | Add-Content -Encoding UTF8 $LogPath
    if ($code -ne 0) {
        throw "Step failed: $Name"
    }
}

$summaryPath = Join-Path $Evidence "summary.txt"
"PREFLIGHT_SAFE" | Set-Content -Encoding UTF8 $summaryPath
"ROOT=$Root" | Add-Content -Encoding UTF8 $summaryPath
"LOOPS=$Loops" | Add-Content -Encoding UTF8 $summaryPath
"START_UTC=$((Get-Date).ToUniversalTime().ToString('o'))" | Add-Content -Encoding UTF8 $summaryPath

for ($i = 1; $i -le [Math]::Max(1, $Loops); $i++) {
    $iter = "iter_{0:D2}" -f $i
    $iterDir = Join-Path $Evidence $iter
    New-Item -ItemType Directory -Force -Path $iterDir | Out-Null

    $compileReport = Join-Path $iterDir "01_compile_report.json"
    Invoke-Step -Name "compile" -LogPath (Join-Path $iterDir "01_compile.txt") -Command "python TOOLS\\smoke_compile_v6_2.py --root `"$Root`" --out `"$compileReport`""
    Invoke-Step -Name "smoke" -LogPath (Join-Path $iterDir "02_smoke_dyrygent.txt") -Command "python test_dyrygent_external.py"
    Invoke-Step -Name "tests" -LogPath (Join-Path $iterDir "03_structural_contract_tests.txt") -Command "python -m unittest tests.test_structural_p0 tests.test_api_contracts tests.test_offline_network_guard tests.test_runtime_housekeeping -v"

    $auditEvidence = Join-Path $iterDir "audit_offline"
    Invoke-Step -Name "audit_offline" -LogPath (Join-Path $iterDir "04_audit_offline.txt") -Command "powershell -ExecutionPolicy Bypass -File RUN\\AUDIT_OFFLINE.ps1 -Root `"$Root`" -Evidence `"$auditEvidence`" -PrintSummary -NoSync"

    "$iter=PASS" | Add-Content -Encoding UTF8 $summaryPath
}

if (-not $NoSync) {
    $syncScript = Join-Path $PSScriptRoot "SYNC_EVIDENCE.ps1"
    if (Test-Path $syncScript) {
        powershell -ExecutionPolicy Bypass -File $syncScript -SourceEvidence (Join-Path $Root "EVIDENCE") -TargetEvidence $SyncTarget
        "SYNC_EXIT=$LASTEXITCODE" | Add-Content -Encoding UTF8 $summaryPath
    }
}

"STATUS=PASS" | Add-Content -Encoding UTF8 $summaryPath
"END_UTC=$((Get-Date).ToUniversalTime().ToString('o'))" | Add-Content -Encoding UTF8 $summaryPath
Write-Host "[PREFLIGHT_SAFE] PASS"
exit 0
