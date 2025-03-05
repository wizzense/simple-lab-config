<#
.SYNOPSIS
  Master runner script to sequentially execute configuration scripts.
#>

Param(
    [string]$ConfigFile = ".\config.json"
)

# Function to recursively convert an object to a case‑sensitive dictionary.
function ConvertTo-CaseSensitiveDictionary {
    param (
        $obj
    )
    if ($obj -is [System.Collections.IDictionary]) {
        $dict = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($key in $obj.Keys) {
            $dict[$key] = ConvertTo-CaseSensitiveDictionary $obj[$key]
        }
        return $dict
    }
    elseif ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
        $arr = @()
        foreach ($item in $obj) {
            $arr += ConvertTo-CaseSensitiveDictionary $item
        }
        return $arr
    }
    elseif ($obj -is [PSCustomObject]) {
        $dict = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
        foreach ($prop in $obj.PSObject.Properties) {
            $dict[$prop.Name] = ConvertTo-CaseSensitiveDictionary $prop.Value
        }
        return $dict
    }
    else {
        return $obj
    }
}

# Prompt for a new value for a given key, showing the current value.
function Prompt-ForValue {
    param (
        [string]$PromptMessage,
        $CurrentValue
    )
    $inputVal = Read-Host "$PromptMessage (current: $CurrentValue) (Press Enter to keep current)"
    if ([string]::IsNullOrEmpty($inputVal)) {
        return $CurrentValue
    }
    else {
        # Convert to the same type as the current value if applicable.
        if ($CurrentValue -is [int]) {
            return [int]$inputVal
        }
        elseif ($CurrentValue -is [bool]) {
            return [bool]$inputVal
        }
        else {
            return $inputVal
        }
    }
}

# Walk through the config object and prompt for optional customization.
# Accepts any IDictionary (hashtable or dictionary).
function Customize-Config {
    param (
        [System.Collections.IDictionary]$ConfigObject
    )
    foreach ($key in @($ConfigObject.Keys)) {
        $value = $ConfigObject[$key]
        if ($value -is [System.Collections.IDictionary]) {
            Write-Host "`nConfiguring '$key':"
            foreach ($subKey in @($value.Keys)) {
                $subValue = $value[$subKey]
                $newSubValue = Prompt-ForValue -PromptMessage "$key.$subKey" -CurrentValue $subValue
                $value[$subKey] = $newSubValue
            }
            $ConfigObject[$key] = $value
        }
        elseif ($value -is [array]) {
            $listDisplay = $value -join ", "
            $inputVal = Read-Host "Enter comma separated values for '$key' (current: $listDisplay) (Press Enter to keep current)"
            if (-not [string]::IsNullOrEmpty($inputVal)) {
                $ConfigObject[$key] = $inputVal -split "\s*,\s*"
            }
        }
        else {
            $ConfigObject[$key] = Prompt-ForValue -PromptMessage "$key" -CurrentValue $value
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
    # Load the raw configuration as a PSCustomObject
    $ConfigRaw = ConvertFrom-Json $jsonContent
    # Convert to a case-sensitive dictionary to preserve key casing.
    $Config = ConvertTo-CaseSensitiveDictionary $ConfigRaw
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
