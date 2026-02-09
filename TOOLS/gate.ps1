param(
  [ValidateSet('dev','release')]
  [string]$Mode = 'release',
  [string]$Zip = ''
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Zip)) {
  python "$PSScriptRoot\gate.py" --mode $Mode
} else {
  python "$PSScriptRoot\gate.py" --mode $Mode --zip $Zip
}
exit $LASTEXITCODE
