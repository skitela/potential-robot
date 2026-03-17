param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$PackageRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\PACKAGE",
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
    [string]$RemoteCommonFilesDir,
    [switch]$RunPrepareRollout,
    [switch]$SkipPackageExport,
    [switch]$SkipRemoteInstall,
    [switch]$SkipRemoteValidate,
    [switch]$PruneStaleManagedFiles,
    [bool]$CreateRuntimeFolders = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $base.EndsWith("\")) {
        $base += "\"
    }

    $baseUri = New-Object System.Uri($base)
    $fullUri = New-Object System.Uri([System.IO.Path]::GetFullPath($FullPath))
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fullUri).ToString()).Replace("/","\")
}

function Get-ManagedLocalFiles {
    param(
        [string]$ResolvedProjectRoot,
        [string]$ResolvedPackageRoot
    )

    $fullPaths = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path -LiteralPath $ResolvedPackageRoot)) {
        throw "PackageRoot not found: $ResolvedPackageRoot"
    }

    Get-ChildItem -LiteralPath $ResolvedPackageRoot -Recurse -File | ForEach-Object {
        $fullPaths.Add($_.FullName)
    }

    Get-ChildItem -LiteralPath (Join-Path $ResolvedProjectRoot "CONFIG") -Filter *.json -File | ForEach-Object {
        $fullPaths.Add($_.FullName)
    }

    foreach ($toolName in @(
        "INSTALL_MT5_SERVER_PACKAGE.ps1",
        "VALIDATE_MT5_SERVER_INSTALL.ps1"
    )) {
        $toolPath = Join-Path $ResolvedProjectRoot ("TOOLS\" + $toolName)
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Required tool missing: $toolPath"
        }
        $fullPaths.Add($toolPath)
    }

    $items = foreach ($fullPath in ($fullPaths | Sort-Object -Unique)) {
        $file = Get-Item -LiteralPath $fullPath
        [pscustomobject]@{
            relative_path = ConvertTo-RelativePath -BasePath $ResolvedProjectRoot -FullPath $file.FullName
            full_path = $file.FullName
            length = [int64]$file.Length
            sha256 = [string](Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }

    return @($items)
}

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
    if ($null -eq $config.targets) {
        throw "Remote target config has no targets section: $ConfigPath"
    }

    $target = $config.targets | Where-Object { $_.name -eq $SelectedTargetName } | Select-Object -First 1
    if ($null -eq $target) {
        throw "Target '$SelectedTargetName' not found in $ConfigPath"
    }

    return $target
}

function Resolve-EffectiveTarget {
    param(
        [object]$ConfiguredTarget
    )

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

    if ([string]::IsNullOrWhiteSpace([string]$target.remote_terminal_data_dir)) {
        throw "Remote terminal data dir is required. Fill remote_deployment_targets.json or pass -RemoteTerminalDataDir."
    }
    if ([string]::IsNullOrWhiteSpace([string]$target.remote_common_files_dir)) {
        throw "Remote common files dir is required. Fill remote_deployment_targets.json or pass -RemoteCommonFilesDir."
    }
    if ([string]::IsNullOrWhiteSpace([string]$target.connection_uri) -and [string]::IsNullOrWhiteSpace([string]$target.computer_name)) {
        throw "Remote computer name or connection URI is required."
    }

    return [pscustomobject]$target
}

function New-RemoteDeploySession {
    param(
        [object]$Target
    )

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

function Get-RemoteFileMetadata {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [string]$RemoteRoot,
        [string[]]$RelativePaths
    )

    $remoteItems = Invoke-Command -Session $Session -ScriptBlock {
        param(
            [string]$ResolvedRemoteRoot,
            [string[]]$RequestedRelativePaths
        )

        foreach ($relativePath in $RequestedRelativePaths) {
            $absolutePath = Join-Path $ResolvedRemoteRoot $relativePath
            if (Test-Path -LiteralPath $absolutePath) {
                $item = Get-Item -LiteralPath $absolutePath
                [pscustomobject]@{
                    relative_path = $relativePath
                    exists = $true
                    length = [int64]$item.Length
                    sha256 = [string](Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash
                }
            } else {
                [pscustomobject]@{
                    relative_path = $relativePath
                    exists = $false
                    length = 0
                    sha256 = ""
                }
            }
        }
    } -ArgumentList $RemoteRoot, $RelativePaths

    return @($remoteItems)
}

function Read-RemoteManagedManifest {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [string]$RemoteRoot
    )

    $json = Invoke-Command -Session $Session -ScriptBlock {
        param([string]$ResolvedRemoteRoot)
        $manifestPath = Join-Path $ResolvedRemoteRoot "RUN\remote_deploy_manifest_v1.json"
        if (Test-Path -LiteralPath $manifestPath) {
            Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        }
    } -ArgumentList $RemoteRoot

    if ([string]::IsNullOrWhiteSpace(($json -join ""))) {
        return $null
    }

    return (($json -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Write-RemoteManagedManifest {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [string]$RemoteRoot,
        [string[]]$ManagedFiles
    )

    $manifest = [ordered]@{
        schema_version = "1.0"
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        managed_files = @($ManagedFiles | Sort-Object -Unique)
    }

    $manifestJson = $manifest | ConvertTo-Json -Depth 5
    Invoke-Command -Session $Session -ScriptBlock {
        param(
            [string]$ResolvedRemoteRoot,
            [string]$ManifestJson
        )
        $runDir = Join-Path $ResolvedRemoteRoot "RUN"
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        $manifestPath = Join-Path $runDir "remote_deploy_manifest_v1.json"
        $ManifestJson | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    } -ArgumentList $RemoteRoot, $manifestJson | Out-Null
}

function Write-DeployReport {
    param(
        [string]$ResolvedProjectRoot,
        [hashtable]$DeployReport
    )

    $evidenceDir = Join-Path $ResolvedProjectRoot "EVIDENCE"
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $jsonPath = Join-Path $evidenceDir ("deploy_mt5_package_to_remote_{0}.json" -f $stamp)
    $txtPath = Join-Path $evidenceDir ("deploy_mt5_package_to_remote_{0}.txt" -f $stamp)
    $latestJsonPath = Join-Path $evidenceDir "deploy_mt5_package_to_remote_latest.json"
    $latestTxtPath = Join-Path $evidenceDir "deploy_mt5_package_to_remote_latest.txt"

    $DeployReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $DeployReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

    $txt = New-Object System.Collections.Generic.List[string]
    $txt.Add("DEPLOY MT5 PACKAGE TO REMOTE")
    $txt.Add(("OK={0}" -f $DeployReport.ok))
    $txt.Add(("TARGET={0}" -f $DeployReport.target_name))
    $txt.Add(("CHANGED={0}" -f $DeployReport.changed_file_count))
    $txt.Add(("PRUNED={0}" -f $DeployReport.pruned_file_count))
    if (-not [string]::IsNullOrWhiteSpace([string]$DeployReport.error)) {
        $txt.Add(("ERROR={0}" -f $DeployReport.error))
    }
    $txt | Set-Content -LiteralPath $txtPath -Encoding ASCII
    $txt | Set-Content -LiteralPath $latestTxtPath -Encoding ASCII
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $resolvedProjectRoot
    package_root = $PackageRoot
    targets_config_path = $TargetsConfigPath
    target_name = $TargetName
    ok = $false
    stage = "init"
    prepare_rollout_run = $false
    package_export_run = $false
    local_managed_file_count = 0
    changed_file_count = 0
    unchanged_file_count = 0
    copied_files = @()
    pruned_files = @()
    remote_install = $null
    remote_validate = $null
    error = $null
}

$session = $null

try {
    if ($RunPrepareRollout) {
        & (Join-Path $resolvedProjectRoot "TOOLS\PREPARE_MT5_ROLLOUT.ps1") -ProjectRoot $resolvedProjectRoot | Out-Null
        $report.prepare_rollout_run = $true
    }

    if (-not $SkipPackageExport) {
        & (Join-Path $resolvedProjectRoot "TOOLS\EXPORT_MT5_SERVER_PROFILE.ps1") -ProjectRoot $resolvedProjectRoot -ProfileRoot $PackageRoot | Out-Null
        $report.package_export_run = $true
    }

    $resolvedPackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path

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
        connection_mode = $target.connection_mode
        computer_name = $target.computer_name
        connection_uri = $target.connection_uri
        port = $target.port
        use_ssl = [bool]$target.use_ssl
        configuration_name = $target.configuration_name
        authentication = $target.authentication
        remote_project_root = $target.remote_project_root
        remote_terminal_data_dir = $target.remote_terminal_data_dir
        remote_common_files_dir = $target.remote_common_files_dir
    }

    $report.stage = "open_session"
    $session = New-RemoteDeploySession -Target $target

    $localManagedFiles = Get-ManagedLocalFiles -ResolvedProjectRoot $resolvedProjectRoot -ResolvedPackageRoot $resolvedPackageRoot
    $report.local_managed_file_count = @($localManagedFiles).Count

    $remoteProjectRoot = [string]$target.remote_project_root
    $relativePaths = @($localManagedFiles | ForEach-Object { [string]$_.relative_path })

    Invoke-Command -Session $session -ScriptBlock {
        param([string]$ResolvedRemoteRoot)
        foreach ($dir in @(
            $ResolvedRemoteRoot,
            (Join-Path $ResolvedRemoteRoot "CONFIG"),
            (Join-Path $ResolvedRemoteRoot "TOOLS"),
            (Join-Path $ResolvedRemoteRoot "SERVER_PROFILE"),
            (Join-Path $ResolvedRemoteRoot "SERVER_PROFILE\PACKAGE"),
            (Join-Path $ResolvedRemoteRoot "EVIDENCE"),
            (Join-Path $ResolvedRemoteRoot "RUN")
        )) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    } -ArgumentList $remoteProjectRoot | Out-Null

    $remoteFiles = Get-RemoteFileMetadata -Session $session -RemoteRoot $remoteProjectRoot -RelativePaths $relativePaths
    $remoteLookup = @{}
    foreach ($remoteFile in $remoteFiles) {
        $remoteLookup[[string]$remoteFile.relative_path] = $remoteFile
    }

    $changed = New-Object System.Collections.Generic.List[object]
    foreach ($localFile in $localManagedFiles) {
        $currentRemote = $remoteLookup[[string]$localFile.relative_path]
        if ($null -eq $currentRemote -or -not [bool]$currentRemote.exists -or [string]$currentRemote.sha256 -ne [string]$localFile.sha256) {
            $changed.Add($localFile)
        }
    }

    $report.changed_file_count = $changed.Count
    $report.unchanged_file_count = $report.local_managed_file_count - $report.changed_file_count

    foreach ($file in $changed) {
        $remoteDestination = Join-Path $remoteProjectRoot $file.relative_path
        Invoke-Command -Session $session -ScriptBlock {
            param([string]$DestinationPath)
            $parent = Split-Path -Parent $DestinationPath
            if (-not [string]::IsNullOrWhiteSpace($parent)) {
                New-Item -ItemType Directory -Force -Path $parent | Out-Null
            }
        } -ArgumentList $remoteDestination | Out-Null

        Copy-Item -LiteralPath $file.full_path -Destination $remoteDestination -ToSession $session -Force
        $report.copied_files += [string]$file.relative_path
    }

    if ($PruneStaleManagedFiles) {
        $previousManifest = Read-RemoteManagedManifest -Session $session -RemoteRoot $remoteProjectRoot
        if ($null -ne $previousManifest -and $null -ne $previousManifest.managed_files) {
            $currentSet = @{}
            foreach ($relativePath in $relativePaths) {
                $currentSet[[string]$relativePath] = $true
            }

            $staleFiles = @($previousManifest.managed_files | Where-Object { -not $currentSet.ContainsKey([string]$_) })
            if ($staleFiles.Count -gt 0) {
                Invoke-Command -Session $session -ScriptBlock {
                    param(
                        [string]$ResolvedRemoteRoot,
                        [string[]]$StaleRelativePaths
                    )
                    foreach ($relativePath in $StaleRelativePaths) {
                        $absolutePath = Join-Path $ResolvedRemoteRoot $relativePath
                        if (Test-Path -LiteralPath $absolutePath) {
                            Remove-Item -LiteralPath $absolutePath -Force
                        }
                    }
                } -ArgumentList $remoteProjectRoot, $staleFiles | Out-Null

                $report.pruned_files = @($staleFiles)
            }
        }
    }

    Write-RemoteManagedManifest -Session $session -RemoteRoot $remoteProjectRoot -ManagedFiles $relativePaths

    if (-not $SkipRemoteInstall) {
        $report.stage = "remote_install"
        $installRaw = Invoke-Command -Session $session -ScriptBlock {
            param(
                [string]$ResolvedRemoteRoot,
                [string]$ResolvedRemoteTerminalDataDir,
                [string]$ResolvedRemoteCommonFilesDir,
                [bool]$ShouldCreateRuntimeFolders
            )

            $scriptPath = Join-Path $ResolvedRemoteRoot "TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1"
            & $scriptPath `
                -ProjectRoot $ResolvedRemoteRoot `
                -PackageRoot (Join-Path $ResolvedRemoteRoot "SERVER_PROFILE\PACKAGE") `
                -TargetTerminalDataDir $ResolvedRemoteTerminalDataDir `
                -TargetCommonFilesDir $ResolvedRemoteCommonFilesDir `
                -CreateRuntimeFolders:$ShouldCreateRuntimeFolders
        } -ArgumentList $remoteProjectRoot, $target.remote_terminal_data_dir, $target.remote_common_files_dir, $CreateRuntimeFolders

        $installText = ($installRaw -join [Environment]::NewLine).Trim()
        if (-not [string]::IsNullOrWhiteSpace($installText)) {
            $report.remote_install = $installText | ConvertFrom-Json
        }
    }

    if (-not $SkipRemoteValidate) {
        $report.stage = "remote_validate"
        $validateRaw = Invoke-Command -Session $session -ScriptBlock {
            param(
                [string]$ResolvedRemoteRoot,
                [string]$ResolvedRemoteTerminalDataDir,
                [string]$ResolvedRemoteCommonFilesDir
            )

            $scriptPath = Join-Path $ResolvedRemoteRoot "TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1"
            & $scriptPath `
                -ProjectRoot $ResolvedRemoteRoot `
                -TargetTerminalDataDir $ResolvedRemoteTerminalDataDir `
                -TargetCommonFilesDir $ResolvedRemoteCommonFilesDir
        } -ArgumentList $remoteProjectRoot, $target.remote_terminal_data_dir, $target.remote_common_files_dir

        $validateText = ($validateRaw -join [Environment]::NewLine).Trim()
        if (-not [string]::IsNullOrWhiteSpace($validateText)) {
            $report.remote_validate = $validateText | ConvertFrom-Json
        }
    }

    $report.pruned_file_count = @($report.pruned_files).Count
    $report.ok = $true
    $report.stage = "done"
}
catch {
    $report.ok = $false
    $report.error = $_.Exception.Message
    $report.stage = "failed"
    $report.pruned_file_count = @($report.pruned_files).Count
}
finally {
    if ($null -ne $session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }

    Write-DeployReport -ResolvedProjectRoot $resolvedProjectRoot -DeployReport $report
}

$report | ConvertTo-Json -Depth 8

if (-not $report.ok) {
    exit 1
}
