<#
.SYNOPSIS
  Master runner script to sequentially execute configuration scripts.
#>

Param(
    [string]$ConfigFile = ".\config.json"
)

# Function to recursively convert an object to a hashtable.
function ConvertTo-Hashtable {
    param (
        $obj
    )
    if ($obj -is [System.Collections.IDictionary]) {
        $ht = @{}
        foreach ($key in $obj.Keys) {
            $ht[$key] = ConvertTo-Hashtable $obj[$key]
        }
        return $ht
    }
    elseif ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
        $arr = @()
        foreach ($item in $obj) {
            $arr += ConvertTo-Hashtable $item
        }
        return $arr
    }
    elseif ($obj -is [PSCustomObject]) {
        $ht = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            $ht[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $ht
    }
    else {
        return $obj
    }
}

# Helper function to format values for display.
function Format-ValueForDisplay {
    param (
        $value
    )
    if ($value -is [bool]) {
        return $value.ToString().ToLower()
    }
    elseif ($value -is [array]) {
        return ($value -join ", ")
    }
    else {
        return $value
    }
}

# Prompt the user for a new value while preserving the original type.
function Prompt-ForValue {
    param (
        [string]$PromptMessage,
        $CurrentValue
    )
    # Use the helper to display booleans in lowercase.
    $displayVal = Format-ValueForDisplay $CurrentValue
    $inputVal = Read-Host "$PromptMessage (current: $displayVal) (Press Enter to keep current)"
    if ([string]::IsNullOrEmpty($inputVal)) {
        return $CurrentValue
    }
    else {
        # Convert input to the same type as the current value.
        if ($CurrentValue -is [int]) {
            return [int]$inputVal
        }
        elseif ($CurrentValue -is [bool]) {
            if ($inputVal -match '^(true|t)$') {
                return $true
            }
            elseif ($inputVal -match '^(false|f)$') {
                return $false
            }
            else {
                Write-Host "Invalid boolean value. Keeping current value."
                return $CurrentValue
            }
        }
        else {
            return $inputVal
        }
    }
}

# Allow the user to choose which config keys to edit by number.
function Customize-Config {
    param (
        [hashtable]$ConfigObject
    )
    while ($true) {
        Write-Host "`n==== Configuration Customization ===="
        Write-Host "Current configuration keys:"
        $keys = @($ConfigObject.Keys)
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $key = $keys[$i]
            $val = Format-ValueForDisplay $ConfigObject[$key]
            Write-Host "[$i] $key : $val"
        }
        $choice = Read-Host "Enter the number of the config you want to edit (or type 'exit' to finish)"
        if ($choice -match '^(exit|quit)$') {
            break
        }
        if ($choice -match '^\d+$' -and [int]$choice -ge 0 -and [int]$choice -lt $keys.Count) {
            $selectedKey = $keys[[int]$choice]
            $currentValue = $ConfigObject[$selectedKey]

            if ($currentValue -is [hashtable]) {
                # Edit nested keys.
                while ($true) {
                    Write-Host "`nEditing subkeys of '$selectedKey':"
                    $subkeys = @($currentValue.Keys)
                    for ($j = 0; $j -lt $subkeys.Count; $j++) {
                        $subKey = $subkeys[$j]
                        $subVal = Format-ValueForDisplay $currentValue[$subKey]
                        Write-Host "   [$j] $subKey : $subVal"
                    }
                    $subChoice = Read-Host "Enter the number of the subkey to edit (or type 'back' to return)"
                    if ($subChoice -match '^(back|exit|quit)$') {
                        break
                    }
                    if ($subChoice -match '^\d+$' -and [int]$subChoice -ge 0 -and [int]$subChoice -lt $subkeys.Count) {
                        $selectedSubKey = $subkeys[[int]$subChoice]
                        $newSubValue = Prompt-ForValue -PromptMessage "$selectedKey.$selectedSubKey" -CurrentValue $currentValue[$selectedSubKey]
                        $currentValue[$selectedSubKey] = $newSubValue
                    }
                    else {
                        Write-Host "Invalid selection, try again."
                    }
                }
                $ConfigObject[$selectedKey] = $currentValue
            }
            elseif ($currentValue -is [array]) {
                $listDisplay = Format-ValueForDisplay $currentValue
                $inputVal = Read-Host "Enter comma separated values for '$selectedKey' (current: $listDisplay) (Press Enter to keep current)"
                if (-not [string]::IsNullOrEmpty($inputVal)) {
                    $ConfigObject[$selectedKey] = $inputVal -split "\s*,\s*"
                }
            }
            else {
                $newValue = Prompt-ForValue -PromptMessage "$selectedKey" -CurrentValue $currentValue
                $ConfigObject[$selectedKey] = $newValue
            }
        }
        else {
            Write-Host "Invalid selection. Please try again."
        }
    }
    return $ConfigObject
}



Write-Host "==== Loading configuration ===="
if (!(Test-Path $ConfigFile)) {
    Write-Host "ERROR: Cannot find config file at $ConfigFile"
    exit 1
}

try {
    $jsonContent = Get-Content -Path $ConfigFile -Raw
    $ConfigRaw = ConvertFrom-Json $jsonContent
    $Config = ConvertTo-Hashtable $ConfigRaw
} catch {
    Write-Host "ERROR: Failed to parse JSON from $ConfigFile. $_"
    exit 1
}

# Display the configuration for review.
Write-Host "==== Current configuration ===="
$formattedConfig = $ConfigRaw | ConvertTo-Json -Depth 5
Write-Host $formattedConfig

# Ask user if they want to customize the configuration values.

$customize = Read-Host "Would you like to customize your configuration? (Y/N)"
if ($customize -match '^(?i)y') {
    $Config = Customize-Config -ConfigObject $Config
    # Save the updated configuration back to the file.
    $Config | ConvertTo-Json -Depth 5 | Out-File -FilePath $ConfigFile -Encoding utf8
    Write-Host "Configuration updated and saved to $ConfigFile"
}

Write-Host "==== Locating scripts ===="
# Find all files named NNNN_*.ps1
$ScriptFiles = Get-ChildItem -Path . -Filter "????_*.ps1" -File | Sort-Object -Property Name

if (!$ScriptFiles) {
    Write-Host "ERROR: No scripts found matching ????_*.ps1 in current directory."
    exit 1
}

# List the found scripts with their 4-digit prefixes.
Write-Host "==== Found the following scripts ===="
foreach ($Script in $ScriptFiles) {
    $prefix = $Script.Name.Substring(0,4)
    Write-Host "$prefix - $($Script.Name)"
}

# Prompt user for selection input.
$selection = Read-Host "Enter the script numbers you want to run (comma separated, e.g. 0003,0005,0007)"
if ([string]::IsNullOrWhiteSpace($selection)) {
    Write-Host "No selection made. Exiting."
    exit 0
}

# Sanitize input: split by comma, trim spaces, and select only those that are 4-digit numbers.
$selectedPrefixes = $selection -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d{4}$' }
if (!$selectedPrefixes) {
    Write-Host "ERROR: No valid 4-digit prefixes found in input. Exiting."
    exit 1
}

# Filter the scripts that match any of the provided prefixes (preserving sorted order).
$ScriptsToRun = $ScriptFiles | Where-Object {
    $prefix = $_.Name.Substring(0,4)
    $selectedPrefixes -contains $prefix
}

if (!$ScriptsToRun) {
    Write-Host "ERROR: None of the selected prefixes correspond to any available scripts."
    exit 1
}

Write-Host "`n==== Executing selected scripts in order ===="
foreach ($Script in $ScriptsToRun) {
    Write-Host "`n--- Running: $($Script.Name) ---"
    try {
        # Execute the script and pass the updated config.
        & "$PSScriptRoot\$($Script.Name)" -Config $Config
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: $($Script.Name) exited with code $LASTEXITCODE."
            exit $LASTEXITCODE
        }
    }
    catch {
        Write-Host "ERROR: Exception in $($Script.Name). $_"
        exit 1
    }
}

Write-Host "`n==== All selected scripts have run successfully! ===="
exit 0
