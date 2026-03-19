param(
    [string]$CodeCmd = "C:\Users\skite\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CodeCmd)) {
    throw "VS Code CLI not found: $CodeCmd"
}

$extensionsToRemove = @(
    "aaronduino.gemini",
    "acebunny00.gemini-cli-launcher",
    "bini.vscode-gemini-assistant",
    "floopy-potato.gemini-commit-message",
    "galacticgit.gemini-chat",
    "google.gemini-cli-vscode-ide-companion",
    "google.geminicodeassist",
    "lpyedge.gemini-cli-mcp",
    "printfn.gemini-improved",
    "shishirregmi.generate-code-gemini",
    "saoudrizwan.claude-dev"
)

$installed = @(& $CodeCmd --list-extensions)
$results = foreach ($extensionId in $extensionsToRemove) {
    if ($installed -contains $extensionId) {
        & $CodeCmd --uninstall-extension $extensionId | Out-Null
        [pscustomobject]@{
            extension = $extensionId
            action = "removed"
        }
    }
    else {
        [pscustomobject]@{
            extension = $extensionId
            action = "not_installed"
        }
    }
}

$results
