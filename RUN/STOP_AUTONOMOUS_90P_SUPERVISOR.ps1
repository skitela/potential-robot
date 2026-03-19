Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$stopped = @()
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
        $_.CommandLine -like "*autonomous_90p_supervisor_wrapper_*"
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $stopped += [pscustomobject]@{
            process_id = $_.ProcessId
            command_line = $_.CommandLine
        }
    }

$stopped | ConvertTo-Json -Depth 4
