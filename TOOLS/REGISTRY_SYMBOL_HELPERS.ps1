function Get-RegistryCanonicalSymbol {
    param([object]$RegistryItem)

    foreach ($propertyName in @("symbol", "broker_symbol")) {
        if ($RegistryItem.PSObject.Properties.Name -contains $propertyName) {
            $value = [string]$RegistryItem.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return ($value -replace '\.pro$','')
            }
        }
    }

    if ($RegistryItem.PSObject.Properties.Name -contains "code_symbol") {
        $value = [string]$RegistryItem.code_symbol
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return ""
}

function Get-RegistryBrokerSymbol {
    param([object]$RegistryItem)

    if ($RegistryItem.PSObject.Properties.Name -contains "broker_symbol") {
        $value = [string]$RegistryItem.broker_symbol
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    $canonical = Get-RegistryCanonicalSymbol -RegistryItem $RegistryItem
    if ([string]::IsNullOrWhiteSpace($canonical)) {
        return ""
    }

    if ($canonical.EndsWith(".pro", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $canonical
    }

    return ($canonical + ".pro")
}

function Get-RegistryCodeSymbol {
    param([object]$RegistryItem)

    if ($RegistryItem.PSObject.Properties.Name -contains "code_symbol") {
        $value = [string]$RegistryItem.code_symbol
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    $canonical = Get-RegistryCanonicalSymbol -RegistryItem $RegistryItem
    if ([string]::IsNullOrWhiteSpace($canonical)) {
        return ""
    }

    return (($canonical -replace '[^A-Za-z0-9]','').ToUpperInvariant())
}

function Get-RegistryDisplaySymbol {
    param(
        [object]$RegistryItem,
        [switch]$PreferBroker
    )

    if ($PreferBroker) {
        $broker = Get-RegistryBrokerSymbol -RegistryItem $RegistryItem
        if (-not [string]::IsNullOrWhiteSpace($broker)) {
            return $broker
        }
    }

    $canonical = Get-RegistryCanonicalSymbol -RegistryItem $RegistryItem
    if (-not [string]::IsNullOrWhiteSpace($canonical)) {
        return $canonical
    }

    return ""
}

function Get-RegistrySymbolCandidates {
    param([object]$RegistryItem)

    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($propertyName in @("symbol", "broker_symbol", "code_symbol")) {
        if ($RegistryItem.PSObject.Properties.Name -contains $propertyName) {
            $value = [string]$RegistryItem.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                [void]$candidates.Add($value)
                [void]$candidates.Add(($value -replace '\.pro$',''))
            }
        }
    }

    $canonical = Get-RegistryCanonicalSymbol -RegistryItem $RegistryItem
    if (-not [string]::IsNullOrWhiteSpace($canonical)) {
        [void]$candidates.Add($canonical)
    }

    $broker = Get-RegistryBrokerSymbol -RegistryItem $RegistryItem
    if (-not [string]::IsNullOrWhiteSpace($broker)) {
        [void]$candidates.Add($broker)
        [void]$candidates.Add(($broker -replace '\.pro$',''))
    }

    $codeSymbol = Get-RegistryCodeSymbol -RegistryItem $RegistryItem
    if (-not [string]::IsNullOrWhiteSpace($codeSymbol)) {
        [void]$candidates.Add($codeSymbol)
    }

    return @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Test-RegistryAliasMatch {
    param(
        [object]$RegistryItem,
        [string]$Alias
    )

    if ([string]::IsNullOrWhiteSpace($Alias)) {
        return $false
    }

    $normalizedAlias = $Alias.Trim().ToUpperInvariant()
    foreach ($candidate in @(Get-RegistrySymbolCandidates -RegistryItem $RegistryItem)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate.Trim().ToUpperInvariant() -eq $normalizedAlias) {
            return $true
        }
    }

    if ($RegistryItem.PSObject.Properties.Name -contains "expert") {
        $expert = [string]$RegistryItem.expert
        if (-not [string]::IsNullOrWhiteSpace($expert) -and $expert.Trim().ToUpperInvariant() -eq $normalizedAlias) {
            return $true
        }
    }

    return $false
}

function Find-RegistryEntryByAlias {
    param(
        [object]$Registry,
        [string]$Alias
    )

    foreach ($item in @($Registry.symbols)) {
        if (Test-RegistryAliasMatch -RegistryItem $item -Alias $Alias) {
            return $item
        }
    }

    return $null
}

function Resolve-RegistryStateAlias {
    param(
        [object]$RegistryItem,
        [string]$CommonFilesRoot,
        [string[]]$RequiredFiles = @("runtime_control.csv")
    )

    foreach ($candidate in @(Get-RegistrySymbolCandidates -RegistryItem $RegistryItem)) {
        $stateDir = Join-Path $CommonFilesRoot ("state\{0}" -f $candidate)
        if (-not (Test-Path -LiteralPath $stateDir)) {
            continue
        }

        $allRequiredPresent = $true
        foreach ($requiredFile in @($RequiredFiles)) {
            if (-not (Test-Path -LiteralPath (Join-Path $stateDir $requiredFile))) {
                $allRequiredPresent = $false
                break
            }
        }

        if ($allRequiredPresent) {
            return $candidate
        }
    }

    foreach ($candidate in @(Get-RegistrySymbolCandidates -RegistryItem $RegistryItem)) {
        $stateDir = Join-Path $CommonFilesRoot ("state\{0}" -f $candidate)
        if (Test-Path -LiteralPath $stateDir) {
            return $candidate
        }
    }

    return (Get-RegistryCanonicalSymbol -RegistryItem $RegistryItem)
}
