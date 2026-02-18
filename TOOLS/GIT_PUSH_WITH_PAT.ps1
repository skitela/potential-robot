param(
    [string]$RepoRoot = "C:\OANDA_MT5_SYSTEM",
    [string]$Remote = "origin",
    [string]$Branch = "",
    [string]$PatEnvVar = "GITHUB_PAT",
    [string]$UserEnvVar = "GITHUB_USER",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function _Fail([string]$msg, [int]$code = 2) {
    Write-Host "GIT_PUSH_PAT_FAIL: $msg"
    exit $code
}

function _Get-CurrentBranch([string]$root) {
    $name = (git -C $root rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        return ""
    }
    return $name
}

function _Build-AuthUrl([string]$remoteUrl, [string]$user, [string]$pat) {
    if ($remoteUrl -notmatch '^https://([^/]+)/(.+)$') {
        _Fail "Remote URL must be HTTPS. Got: $remoteUrl" 3
    }
    $host = $Matches[1]
    $path = $Matches[2]
    $u = [System.Uri]::EscapeDataString($user)
    $p = [System.Uri]::EscapeDataString($pat)
    return "https://$u`:$p@$host/$path"
}

if (-not (Test-Path $RepoRoot)) {
    _Fail "Repo root not found: $RepoRoot" 3
}
if (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
    _Fail "Not a git repo: $RepoRoot" 3
}

if ([string]::IsNullOrWhiteSpace($Branch)) {
    $Branch = _Get-CurrentBranch -root $RepoRoot
}
if ([string]::IsNullOrWhiteSpace($Branch)) {
    _Fail "Cannot determine branch. Pass -Branch explicitly." 3
}

$pat = [Environment]::GetEnvironmentVariable($PatEnvVar)
if ([string]::IsNullOrWhiteSpace($pat)) {
    _Fail "Missing PAT in env var '$PatEnvVar'." 4
}

$remoteUrl = (git -C $RepoRoot remote get-url $Remote 2>$null).Trim()
if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
    _Fail "Cannot read remote URL for '$Remote'." 3
}

$user = [Environment]::GetEnvironmentVariable($UserEnvVar)
if ([string]::IsNullOrWhiteSpace($user)) {
    if ($remoteUrl -match '^https://github\.com/([^/]+)/.+$') {
        $user = $Matches[1]
    }
}
if ([string]::IsNullOrWhiteSpace($user)) {
    _Fail "Cannot infer GitHub user. Set env var '$UserEnvVar'." 4
}

$authUrl = _Build-AuthUrl -remoteUrl $remoteUrl -user $user -pat $pat

# Remove broken local proxy overrides for this process only.
foreach ($v in @("ALL_PROXY", "HTTP_PROXY", "HTTPS_PROXY", "GIT_HTTP_PROXY", "GIT_HTTPS_PROXY")) {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}

Write-Host "GIT_PUSH_PAT_START repo=$RepoRoot remote=$Remote branch=$Branch dry_run=$([int]$DryRun)"
try {
    $args = @(
        "-C", $RepoRoot,
        "-c", "credential.helper=",
        "-c", "http.sslbackend=openssl",
        "push"
    )
    if ($DryRun) { $args += "--dry-run" }
    $args += @($authUrl, $Branch)
    & git @args
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        _Fail "git push failed with code $rc" $rc
    }
    Write-Host "GIT_PUSH_PAT_OK branch=$Branch"
    exit 0
}
catch {
    _Fail ("Unhandled exception: " + $_.Exception.Message) 9
}
