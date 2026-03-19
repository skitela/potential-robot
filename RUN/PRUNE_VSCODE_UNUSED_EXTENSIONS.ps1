param(
    [string]$CodeCmd = "C:\Users\skite\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd",
    [string]$ExtensionsRoot = "C:\Users\skite\.vscode\extensions"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CodeCmd)) {
    throw "VS Code CLI not found: $CodeCmd"
}
if (-not (Test-Path -LiteralPath $ExtensionsRoot)) {
    throw "Extensions root not found: $ExtensionsRoot"
}

$safeUninstall = @(
    "continue.continue",
    "github.codespaces",
    "github.remotehub",
    "ms-azuretools.vscode-containers",
    "ms-vscode.azure-repos",
    "ms-vscode.remote-repositories",
    "ms-vscode.vscode-copilot-vision",
    "ms-vscode.cmake-tools",
    "ms-vscode.cpp-devtools",
    "sixth.sixth-ai"
) | ForEach-Object { $_.ToLowerInvariant() }

$staleAiIds = @(
    "aaronduino.gemini",
    "acebunny00.gemini-cli-launcher",
    "bini.vscode-gemini-assistant",
    "floopy-potato.gemini-commit-message",
    "galacticgit.gemini-chat",
    "google.gemini-cli-vscode-ide-companion",
    "google.geminicodeassist",
    "lpyedge.gemini-cli-mcp",
    "printfn.gemini-improved",
    "saoudrizwan.claude-dev",
    "shishirregmi.generate-code-gemini"
) | ForEach-Object { $_.ToLowerInvariant() }

function Get-ExtensionIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath
    )

    $packageJsonPath = Join-Path $FolderPath "package.json"
    if (Test-Path -LiteralPath $packageJsonPath) {
        try {
            $package = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
            if ($package.publisher -and $package.name) {
                return ("{0}.{1}" -f $package.publisher, $package.name).ToLowerInvariant()
            }
        }
        catch {
        }
    }

    $vsixManifestPath = Join-Path $FolderPath ".vsixmanifest"
    if (Test-Path -LiteralPath $vsixManifestPath) {
        try {
            [xml]$manifest = Get-Content -LiteralPath $vsixManifestPath -Raw
            $identity = $manifest.PackageManifest.Metadata.Identity
            if ($identity.Publisher -and $identity.Id) {
                return ("{0}.{1}" -f $identity.Publisher, $identity.Id).ToLowerInvariant()
            }
        }
        catch {
        }
    }

    return $null
}

$installed = @(& $CodeCmd --list-extensions) | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }
$results = New-Object System.Collections.Generic.List[object]

foreach ($extensionId in $safeUninstall) {
    if ($installed -contains $extensionId) {
        & $CodeCmd --uninstall-extension $extensionId | Out-Null
        $results.Add([pscustomobject]@{
            item = $extensionId
            action = "extension_removed"
        })
    }
    else {
        $results.Add([pscustomobject]@{
            item = $extensionId
            action = "extension_not_installed"
        })
    }
}

$stalePatterns = @(
    "github.codespaces-*",
    "github.remotehub-*",
    "aaronduino.gemini-*",
    "acebunny00.gemini-cli-launcher-*",
    "bini.vscode-gemini-assistant-*",
    "floopy-potato.gemini-commit-message-*",
    "galacticgit.gemini-chat-*",
    "google.gemini-cli-vscode-ide-companion-*",
    "google.geminicodeassist-*",
    "lpyedge.gemini-cli-mcp-*",
    "ms-azuretools.vscode-containers-*",
    "ms-vscode.azure-repos-*",
    "ms-vscode.cmake-tools-*",
    "ms-vscode.cpp-devtools-*",
    "ms-vscode.remote-repositories-*",
    "ms-vscode.vscode-copilot-vision-*",
    "printfn.gemini-improved-*",
    "saoudrizwan.claude-dev-*",
    "shishirregmi.generate-code-gemini-*",
    "sixth.sixth-ai-*",
    "continue.continue-*"
)

foreach ($pattern in $stalePatterns) {
    Get-ChildItem -LiteralPath $ExtensionsRoot -Directory -Filter $pattern -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $results.Add([pscustomobject]@{
                item = $_.FullName
                action = "stale_folder_removed"
            })
        }
}

$extensionDirs = Get-ChildItem -LiteralPath $ExtensionsRoot -Force -Directory -ErrorAction SilentlyContinue
$visibleFoldersById = @{}

foreach ($dir in $extensionDirs | Where-Object { $_.Name -notlike ".*" }) {
    $identity = Get-ExtensionIdentity -FolderPath $dir.FullName
    if (-not $identity) {
        continue
    }

    if (-not $visibleFoldersById.ContainsKey($identity)) {
        $visibleFoldersById[$identity] = New-Object System.Collections.Generic.List[string]
    }
    $visibleFoldersById[$identity].Add($dir.FullName)
}

foreach ($dir in $extensionDirs | Where-Object { $_.Name -like ".*" }) {
    $identity = Get-ExtensionIdentity -FolderPath $dir.FullName
    if (-not $identity) {
        $results.Add([pscustomobject]@{
            item = $dir.FullName
            action = "hidden_folder_skipped_unknown_identity"
        })
        continue
    }

    $hasVisibleCurrentFolder = $visibleFoldersById.ContainsKey($identity)
    $canRemoveHiddenFolder =
        ($safeUninstall -contains $identity) -or
        ($staleAiIds -contains $identity) -or
        $hasVisibleCurrentFolder

    if ($canRemoveHiddenFolder) {
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        $results.Add([pscustomobject]@{
            item = $dir.FullName
            action = "hidden_stale_folder_removed"
            identity = $identity
        })
    }
    else {
        $results.Add([pscustomobject]@{
            item = $dir.FullName
            action = "hidden_folder_kept"
            identity = $identity
        })
    }
}

$results
