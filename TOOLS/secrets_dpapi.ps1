Set-StrictMode -Version Latest

function Get-LlmSecretRoot {
    param([string]$SecretRoot = "")
    if ($SecretRoot) {
        return $SecretRoot
    }
    if ($env:LLM_SECRET_ROOT) {
        return [string]$env:LLM_SECRET_ROOT
    }
    $local = [string]$env:LOCALAPPDATA
    if (-not $local) {
        $local = Join-Path ([Environment]::GetFolderPath("UserProfile")) "AppData\Local"
    }
    return (Join-Path $local "OANDA_MT5_SYSTEM\LLM_SECRETS_DPAPI")
}

function Get-LlmSecretPaths {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("openai", "gemini")]
        [string]$Provider,
        [string]$SecretRoot = ""
    )
    $root = Get-LlmSecretRoot -SecretRoot $SecretRoot
    $providerDir = Join-Path $root $Provider
    return @{
        Provider = $Provider
        SecretRoot = $root
        SecretDir = $providerDir
        CipherPath = (Join-Path $providerDir "api_key.dpapi")
        MetaPath = (Join-Path $providerDir "metadata.json")
    }
}

function Set-LlmSecretStoreAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Directory
    )
    if (-not (Test-Path $Path)) {
        throw "Path not found: $Path"
    }
    $identity = if ($env:USERDOMAIN) {
        "$($env:USERDOMAIN)\$($env:USERNAME)"
    } else {
        [string]$env:USERNAME
    }
    try {
        $acl = Get-Acl -Path $Path
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) {
            [void]$acl.RemoveAccessRule($rule)
        }

        $inheritFlags = if ($Directory) {
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else {
            [System.Security.AccessControl.InheritanceFlags]::None
        }
        $propFlags = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        $full = [System.Security.AccessControl.FileSystemRights]::FullControl

        $r1 = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $full, $inheritFlags, $propFlags, $allow)
        $r2 = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", $full, $inheritFlags, $propFlags, $allow)
        $acl.AddAccessRule($r1) | Out-Null
        $acl.AddAccessRule($r2) | Out-Null
        Set-Acl -Path $Path -AclObject $acl
    } catch {
        $inheritArg = "/inheritance:r"
        if ($Directory) {
            & icacls.exe $Path $inheritArg "/grant:r" "${identity}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" | Out-Null
        } else {
            & icacls.exe $Path $inheritArg "/grant:r" "${identity}:(F)" "SYSTEM:(F)" | Out-Null
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set ACL for: $Path"
        }
    }
}

function Get-LlmApiKeySecure {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("openai", "gemini")]
        [string]$Provider,
        [string]$SecretRoot = "",
        [switch]$AsPlainText
    )
    $paths = Get-LlmSecretPaths -Provider $Provider -SecretRoot $SecretRoot
    $cipherPath = [string]$paths.CipherPath
    if (-not (Test-Path $cipherPath)) {
        throw "Secret ciphertext missing for provider '$Provider'."
    }
    $cipher = (Get-Content -Raw -Encoding UTF8 $cipherPath).Trim()
    if (-not $cipher) {
        throw "Secret ciphertext empty for provider '$Provider'."
    }
    $secure = $cipher | ConvertTo-SecureString
    if (-not $AsPlainText) {
        return $secure
    }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-LlmKeyStatus {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("openai", "gemini")]
        [string]$Provider,
        [int]$RotationDays = 60,
        [string]$SecretRoot = ""
    )
    $paths = Get-LlmSecretPaths -Provider $Provider -SecretRoot $SecretRoot
    $cipherPath = [string]$paths.CipherPath
    $metaPath = [string]$paths.MetaPath

    $present = (Test-Path $cipherPath)
    $meta = @{}
    if (Test-Path $metaPath) {
        try {
            $metaRaw = Get-Content -Raw -Encoding UTF8 $metaPath
            $metaObj = $null
            try {
                $metaObj = ($metaRaw | ConvertFrom-Json -AsHashtable -ErrorAction Stop)
            } catch {
                $metaObj = ($metaRaw | ConvertFrom-Json -ErrorAction Stop)
            }
            if ($metaObj -is [hashtable]) {
                $meta = $metaObj
            } elseif ($metaObj -ne $null) {
                foreach ($p in $metaObj.PSObject.Properties) {
                    $meta[[string]$p.Name] = $p.Value
                }
            }
        } catch {
            $meta = @{}
        }
    }

    $created = ""
    if ($meta -is [hashtable] -and $meta.ContainsKey("created_at")) {
        $created = [string]$meta["created_at"]
    }
    $rotated = ""
    if ($meta -is [hashtable] -and $meta.ContainsKey("last_rotated_at")) {
        $rotated = [string]$meta["last_rotated_at"]
    }
    if (-not $rotated) {
        $rotated = $created
    }

    $ageDays = $null
    if ($rotated) {
        try {
            $dt = [DateTimeOffset]::Parse($rotated).UtcDateTime
            $ageDays = [math]::Floor(((Get-Date).ToUniversalTime() - $dt).TotalDays)
        } catch {
            $ageDays = $null
        }
    }
    $rotationDue = $false
    if ($present -and $ageDays -ne $null -and [int]$ageDays -ge [int]$RotationDays) {
        $rotationDue = $true
    }

    $status = "missing"
    if ($present) {
        $status = if ($rotationDue) { "rotation_due" } else { "present" }
    }

    return @{
        provider = $Provider
        status = $status
        present = [bool]$present
        rotation_due = [bool]$rotationDue
        age_days = $ageDays
        created_at = $created
        last_rotated_at = $rotated
        ciphertext_path = $cipherPath
        metadata_path = $metaPath
    }
}
