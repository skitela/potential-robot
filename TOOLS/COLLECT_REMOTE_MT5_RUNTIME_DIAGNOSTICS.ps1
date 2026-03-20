param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TargetsConfigPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\remote_deployment_targets.json",
    [string]$TargetName = "VPS_PRIMARY",
    [string]$ComputerName,
    [string]$ConnectionUri,
    [int]$Port = 0,
    [switch]$UseSSL,
    [string]$ConfigurationName,
    [string]$Authentication,
    [System.Management.Automation.PSCredential]$Credential,
    [string]$RemoteProjectRoot,
    [string]$RemoteTerminalDataDir,
    [string]$RemoteCommonFilesDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Read-RemoteTargetConfig {
    param(
        [string]$ConfigPath,
        [string]$SelectedTargetName
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $examplePath = [System.IO.Path]::ChangeExtension($ConfigPath, ".example.json")
        if (Test-Path -LiteralPath $examplePath) {
            throw "Remote target config missing: $ConfigPath. Create it from $examplePath."
        }
        throw "Remote target config missing: $ConfigPath"
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $target = $config.targets | Where-Object { $_.name -eq $SelectedTargetName } | Select-Object -First 1
    if ($null -eq $target) {
        throw "Target '$SelectedTargetName' not found in $ConfigPath"
    }
    return $target
}

function Resolve-EffectiveTarget {
    param([object]$ConfiguredTarget)

    $target = [ordered]@{
        name = $TargetName
        connection_mode = "psremoting"
        computer_name = $null
        connection_uri = $null
        port = 5985
        use_ssl = $false
        configuration_name = "Microsoft.PowerShell"
        authentication = "Default"
        remote_project_root = "C:\MAKRO_I_MIKRO_BOT"
        remote_terminal_data_dir = $null
        remote_common_files_dir = $null
    }

    if ($null -ne $ConfiguredTarget) {
        foreach ($property in $ConfiguredTarget.PSObject.Properties) {
            $target[$property.Name] = $property.Value
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
        $target.computer_name = $ComputerName
    }
    if (-not [string]::IsNullOrWhiteSpace($ConnectionUri)) {
        $target.connection_uri = $ConnectionUri
    }
    if ($Port -gt 0) {
        $target.port = $Port
    }
    if ($UseSSL.IsPresent) {
        $target.use_ssl = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($ConfigurationName)) {
        $target.configuration_name = $ConfigurationName
    }
    if (-not [string]::IsNullOrWhiteSpace($Authentication)) {
        $target.authentication = $Authentication
    }
    if (-not [string]::IsNullOrWhiteSpace($RemoteProjectRoot)) {
        $target.remote_project_root = $RemoteProjectRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($RemoteTerminalDataDir)) {
        $target.remote_terminal_data_dir = $RemoteTerminalDataDir
    }
    if (-not [string]::IsNullOrWhiteSpace($RemoteCommonFilesDir)) {
        $target.remote_common_files_dir = $RemoteCommonFilesDir
    }

    if ([string]::IsNullOrWhiteSpace([string]$target.remote_common_files_dir)) {
        throw "Remote common files dir is required."
    }
    if ([string]::IsNullOrWhiteSpace([string]$target.connection_uri) -and [string]::IsNullOrWhiteSpace([string]$target.computer_name)) {
        throw "Remote computer name or connection URI is required."
    }

    return [pscustomobject]$target
}

function New-RemoteDiagnosticsSession {
    param([object]$Target)

    $sessionParams = @{
        ErrorAction = "Stop"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Target.configuration_name)) {
        $sessionParams["ConfigurationName"] = [string]$Target.configuration_name
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Target.authentication)) {
        $sessionParams["Authentication"] = [string]$Target.authentication
    }
    if ($null -ne $Credential) {
        $sessionParams["Credential"] = $Credential
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Target.connection_uri)) {
        $sessionParams["ConnectionUri"] = [uri][string]$Target.connection_uri
    } else {
        $sessionParams["ComputerName"] = [string]$Target.computer_name
        if ($Target.port -gt 0) {
            $sessionParams["Port"] = [int]$Target.port
        }
        if ([bool]$Target.use_ssl) {
            $sessionParams["UseSSL"] = $true
        }
    }

    return New-PSSession @sessionParams
}

function Get-SymbolAliases {
    param([string]$RegistryPath)

    $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $aliases = New-Object System.Collections.Generic.List[string]

    foreach ($item in $registry.symbols) {
        foreach ($candidate in @(Get-RegistrySymbolCandidates -RegistryItem $item)) {
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $aliases.Add($candidate)
            }
        }
    }

    return @($aliases | Sort-Object -Unique)
}

function Write-CollectReport {
    param(
        [string]$ResolvedProjectRoot,
        [hashtable]$CollectReport
    )

    $evidenceDir = Join-Path $ResolvedProjectRoot "EVIDENCE"
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $jsonPath = Join-Path $evidenceDir ("collect_remote_mt5_runtime_diagnostics_{0}.json" -f $stamp)
    $txtPath = Join-Path $evidenceDir ("collect_remote_mt5_runtime_diagnostics_{0}.txt" -f $stamp)
    $latestJsonPath = Join-Path $evidenceDir "collect_remote_mt5_runtime_diagnostics_latest.json"
    $latestTxtPath = Join-Path $evidenceDir "collect_remote_mt5_runtime_diagnostics_latest.txt"

    $CollectReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $CollectReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

    $txt = New-Object System.Collections.Generic.List[string]
    $txt.Add("COLLECT REMOTE MT5 RUNTIME DIAGNOSTICS")
    $txt.Add(("OK={0}" -f $CollectReport.ok))
    $txt.Add(("TARGET={0}" -f $CollectReport.target_name))
    $txt.Add(("FOUND={0}" -f $CollectReport.found_file_count))
    $txt.Add(("COPIED={0}" -f $CollectReport.copied_file_count))
    $txt.Add(("SNAPSHOT={0}" -f $CollectReport.snapshot_root))
    if (-not [string]::IsNullOrWhiteSpace([string]$CollectReport.error)) {
        $txt.Add(("ERROR={0}" -f $CollectReport.error))
    }
    $txt | Set-Content -LiteralPath $txtPath -Encoding ASCII
    $txt | Set-Content -LiteralPath $latestTxtPath -Encoding ASCII
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $resolvedProjectRoot
    targets_config_path = $TargetsConfigPath
    target_name = $TargetName
    ok = $false
    stage = "init"
    found_file_count = 0
    copied_file_count = 0
    snapshot_root = $null
    copied_files = @()
    missing_files = @()
    error = $null
}

$session = $null

try {
    $configuredTarget = $null
    if (
        [string]::IsNullOrWhiteSpace($ComputerName) -and
        [string]::IsNullOrWhiteSpace($ConnectionUri) -and
        [string]::IsNullOrWhiteSpace($RemoteProjectRoot) -and
        [string]::IsNullOrWhiteSpace($RemoteTerminalDataDir) -and
        [string]::IsNullOrWhiteSpace($RemoteCommonFilesDir) -and
        -not $UseSSL.IsPresent -and
        $Port -le 0 -and
        [string]::IsNullOrWhiteSpace($ConfigurationName) -and
        [string]::IsNullOrWhiteSpace($Authentication)
    ) {
        $configuredTarget = Read-RemoteTargetConfig -ConfigPath $TargetsConfigPath -SelectedTargetName $TargetName
    } elseif (Test-Path -LiteralPath $TargetsConfigPath) {
        $configuredTarget = Read-RemoteTargetConfig -ConfigPath $TargetsConfigPath -SelectedTargetName $TargetName
    }

    $target = Resolve-EffectiveTarget -ConfiguredTarget $configuredTarget
    $report.target = [ordered]@{
        computer_name = $target.computer_name
        connection_uri = $target.connection_uri
        remote_project_root = $target.remote_project_root
        remote_common_files_dir = $target.remote_common_files_dir
    }

    $report.stage = "open_session"
    $session = New-RemoteDiagnosticsSession -Target $target

    $registryPath = Join-Path $resolvedProjectRoot "CONFIG\microbots_registry.json"
    $aliases = Get-SymbolAliases -RegistryPath $registryPath

    $projectCandidates = @(
        "EVIDENCE\install_mt5_server_package_report.json",
        "EVIDENCE\install_mt5_server_package_report.txt",
        "EVIDENCE\validate_mt5_server_install_report.json",
        "EVIDENCE\validate_mt5_server_install_report.txt"
    )

    $commonCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($globalCandidate in @(
        "state\_global\session_capital_coordinator.csv",
        "state\_global\runtime_control.csv",
        "state\_global\runtime_control.json"
    )) {
        $commonCandidates.Add($globalCandidate)
    }

    foreach ($alias in $aliases) {
        foreach ($relativePath in @(
            ("state\{0}\broker_profile.json" -f $alias),
            ("state\{0}\execution_summary.json" -f $alias),
            ("state\{0}\informational_policy.json" -f $alias),
            ("state\{0}\paper_position.csv" -f $alias),
            ("logs\{0}\tuning_experiments.csv" -f $alias),
            ("logs\{0}\tuning_reasoning.csv" -f $alias),
            ("logs\{0}\tuning_deckhand.csv" -f $alias),
            ("logs\{0}\decision_events.csv" -f $alias),
            ("logs\{0}\latency_profile.csv" -f $alias)
        )) {
            $commonCandidates.Add($relativePath)
        }
    }

    $report.stage = "scan_remote"
    $scanResults = Invoke-Command -Session $session -ScriptBlock {
        param(
            [string]$ResolvedRemoteProjectRoot,
            [string]$ResolvedRemoteCommonFilesDir,
            [string[]]$RequestedProjectPaths,
            [string[]]$RequestedCommonPaths
        )

        $remoteCommonRoot = Join-Path $ResolvedRemoteCommonFilesDir "MAKRO_I_MIKRO_BOT"
        $results = New-Object System.Collections.Generic.List[object]

        foreach ($relativePath in $RequestedProjectPaths) {
            $absolutePath = Join-Path $ResolvedRemoteProjectRoot $relativePath
            if (Test-Path -LiteralPath $absolutePath) {
                $item = Get-Item -LiteralPath $absolutePath
                $results.Add([pscustomobject]@{
                    scope = "project"
                    relative_path = $relativePath
                    absolute_path = $absolutePath
                    length = [int64]$item.Length
                    last_write_time_utc = $item.LastWriteTimeUtc.ToString("o")
                })
            }
        }

        foreach ($relativePath in $RequestedCommonPaths) {
            $absolutePath = Join-Path $remoteCommonRoot $relativePath
            if (Test-Path -LiteralPath $absolutePath) {
                $item = Get-Item -LiteralPath $absolutePath
                $results.Add([pscustomobject]@{
                    scope = "common"
                    relative_path = $relativePath
                    absolute_path = $absolutePath
                    length = [int64]$item.Length
                    last_write_time_utc = $item.LastWriteTimeUtc.ToString("o")
                })
            }
        }

        return $results
    } -ArgumentList $target.remote_project_root, $target.remote_common_files_dir, $projectCandidates, @($commonCandidates | Sort-Object -Unique)

    $remoteFiles = @($scanResults)
    $report.found_file_count = $remoteFiles.Count

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $snapshotRoot = Join-Path $resolvedProjectRoot ("EVIDENCE\REMOTE_RUNTIME_SNAPSHOTS\{0}\{1}" -f $TargetName, $stamp)
    New-Item -ItemType Directory -Force -Path $snapshotRoot | Out-Null
    $report.snapshot_root = $snapshotRoot

    foreach ($remoteFile in $remoteFiles) {
        $scopeRoot = Join-Path $snapshotRoot $remoteFile.scope
        $destinationPath = Join-Path $scopeRoot $remoteFile.relative_path
        $destinationDir = Split-Path -Parent $destinationPath
        if (-not [string]::IsNullOrWhiteSpace($destinationDir)) {
            New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
        }

        Copy-Item -FromSession $session -LiteralPath $remoteFile.absolute_path -Destination $destinationPath -Force
        $report.copied_files += [pscustomobject]@{
            scope = $remoteFile.scope
            relative_path = $remoteFile.relative_path
            destination = $destinationPath
            length = $remoteFile.length
            last_write_time_utc = $remoteFile.last_write_time_utc
        }
    }

    $requestedSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($path in $projectCandidates) {
        [void]$requestedSet.Add(("project|" + $path))
    }
    foreach ($path in ($commonCandidates | Sort-Object -Unique)) {
        [void]$requestedSet.Add(("common|" + $path))
    }

    $foundSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($item in $remoteFiles) {
        [void]$foundSet.Add(($item.scope + "|" + $item.relative_path))
    }

    foreach ($entry in $requestedSet) {
        if (-not $foundSet.Contains($entry)) {
            $parts = $entry.Split("|",2)
            $report.missing_files += [pscustomobject]@{
                scope = $parts[0]
                relative_path = $parts[1]
            }
        }
    }

    $report.copied_file_count = @($report.copied_files).Count
    $report.ok = $true
    $report.stage = "done"
}
catch {
    $report.ok = $false
    $report.error = $_.Exception.Message
    $report.stage = "failed"
}
finally {
    if ($null -ne $session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }

    Write-CollectReport -ResolvedProjectRoot $resolvedProjectRoot -CollectReport $report
}

$report | ConvertTo-Json -Depth 8

if (-not $report.ok) {
    exit 1
}
