param(
  [string]$TargetRoot = "",
  [string]$OutJson = "",
  [string]$OutMd = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\")).Path

if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
  if (Test-Path "C:\GLOBALNY HANDEL VER1") {
    $TargetRoot = "C:\GLOBALNY HANDEL VER1"
  } else {
    $TargetRoot = $Root
  }
}

$cmd = @("python", "-B", (Join-Path $Root "TOOLS\ranking_benchmark_v1.py"), "--target-root", $TargetRoot)
if (-not [string]::IsNullOrWhiteSpace($OutJson)) { $cmd += @("--out-json", $OutJson) }
if (-not [string]::IsNullOrWhiteSpace($OutMd)) { $cmd += @("--out-md", $OutMd) }

& $cmd[0] $cmd[1..($cmd.Length-1)]
exit $LASTEXITCODE
