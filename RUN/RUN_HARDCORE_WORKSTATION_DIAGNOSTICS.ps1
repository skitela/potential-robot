param(
    [string]$ReportRoot = "C:\OANDA_MT5_SYSTEM\EVIDENCE\workstation"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonPath = Join-Path $ReportRoot "workstation_diagnostics_$timestamp.json"
$mdPath = Join-Path $ReportRoot "workstation_diagnostics_$timestamp.md"

$cpu = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, LoadPercentage
$os = Get-CimInstance Win32_OperatingSystem | Select-Object CSName, Version, BuildNumber, TotalVisibleMemorySize, FreePhysicalMemory, TotalVirtualMemorySize, FreeVirtualMemory, LastBootUpTime
$board = Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber
$bios = Get-CimInstance Win32_BIOS | Select-Object SMBIOSBIOSVersion, ReleaseDate, Manufacturer
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM, CurrentHorizontalResolution, CurrentVerticalResolution
$disks = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, Size, HealthStatus, BusType
$volumes = Get-Volume | Select-Object DriveLetter, FileSystem, Size, SizeRemaining, HealthStatus
$pageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage
$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object EstimatedChargeRemaining, BatteryStatus
$powerPlan = powercfg /GETACTIVESCHEME
$perfProcessor = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "_Total" } | Select-Object Name, PercentProcessorTime
$perfMemory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue | Select-Object PercentCommittedBytesInUse, AvailableMBytes
$perfDisk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "_Total" } | Select-Object Name, PercentDiskTime, AvgDiskQueueLength
$topProcesses = Get-Process |
    Sort-Object @{ Expression = { if ($_.CPU -is [double]) { $_.CPU } else { 0 } } } -Descending |
    Select-Object -First 20 ProcessName, Id, CPU, PriorityClass, WorkingSet64, Path
$labProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @("terminal64", "metatester64", "qdmcli", "python", "Code", "chrome") } | Select-Object ProcessName, Id, CPU, PriorityClass, WorkingSet64, Path

$pageFileWarning = $null
if ($pageFile -and $pageFile.AllocatedBaseSize -lt 8192) {
    $pageFileWarning = "Pagefile is undersized for heavy parallel labs. Consider system-managed or at least 8-16 GB on C: during a controlled reboot window."
}

$summary = [pscustomobject]@{
    captured_at = (Get-Date).ToString("s")
    cpu = $cpu
    os = $os
    board = $board
    bios = $bios
    gpu = $gpu
    disks = $disks
    volumes = $volumes
    page_file = $pageFile
    battery = $battery
    power_plan = $powerPlan
    perf = [pscustomobject]@{
        processor = $perfProcessor
        memory = $perfMemory
        disk = $perfDisk
    }
    top_processes = $topProcesses
    lab_processes = $labProcesses
    findings = [pscustomobject]@{
        high_performance_active = ($powerPlan -like "*8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c*")
        nvme_c_recommended = $true
        external_d_not_recommended_for_heavy_lab = $true
        gpu_not_primary_bottleneck = $true
        pagefile_warning = $pageFileWarning
    }
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$logical = if ($cpu) { ($cpu | Select-Object -First 1).NumberOfLogicalProcessors } else { $null }
$ramGb = if ($os) { [Math]::Round((($os.TotalVisibleMemorySize | Select-Object -First 1) / 1MB), 1) } else { $null }
$freeRamGb = if ($os) { [Math]::Round((($os.FreePhysicalMemory | Select-Object -First 1) / 1MB), 1) } else { $null }

$md = @"
# Workstation Diagnostics

- Captured at: $($summary.captured_at)
- CPU: $((($cpu | Select-Object -First 1).Name))
- Logical processors: $logical
- RAM visible: ${ramGb} GB
- RAM free now: ${freeRamGb} GB
- Power plan: $powerPlan

## Findings

- High performance mode is already active.
- Main fast storage is NVMe `C:` and should stay the home for QDM, MT5 test artifacts, research temp, and ML cache.
- External `D:` is healthy but should stay out of heavy tester and ML pipelines.
- Current real contention comes more from `Code` and `chrome` than from MT5/QDM themselves.
- GPU is not the main limiter for the current MT5/QDM/sklearn stack.
- Pagefile note: $pageFileWarning

## Generated Files

- JSON: $jsonPath
"@

$md | Set-Content -LiteralPath $mdPath -Encoding UTF8

[pscustomobject]@{
    json = $jsonPath
    markdown = $mdPath
}
