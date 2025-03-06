
function ConvertTo-Hashtable {
    param(
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

Write-Host "`n==== Found the following scripts ===="
foreach ($Script in $ScriptFiles) {
    $prefix = $Script.Name.Substring(0,4)
    Write-Host "$prefix - $($Script.Name)"
}

# 
# Main loop so the user doesn't have to re-run runner.ps1 repeatedly:
#
while ($true) {
    Write-Host "`nTo run ALL scripts, type 'all'."
    Write-Host "To run one or more specific scripts, provide comma separated 4-digit prefixes (e.g. 0001,0003)."
    Write-Host "Or type 'exit' to quit this script."
    $selection = Read-Host "Enter selection"

    # If the user wants to exit, break out of the loop.
    if ($selection -match '^(?i)exit$') {
        break
    }

    # If user types "all," select every script in $ScriptFiles.
    if ($selection -eq 'all') {
        $ScriptsToRun = $ScriptFiles
    }
    else {
        # Otherwise, parse any numeric prefixes the user typed.
        $selectedPrefixes = $selection -split "," |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^\d{4}$' }

        if (!$selectedPrefixes) {
            Write-Host "No valid 4-digit prefixes found. Please try again."
            continue
        }

        $ScriptsToRun = $ScriptFiles | Where-Object {
            $prefix = $_.Name.Substring(0,4)
            $selectedPrefixes -contains $prefix
        }

        if (!$ScriptsToRun) {
            Write-Host "None of the provided prefixes match the scripts in the folder. Please try again."
            continue
        }
    }

    # Run all scripts in $ScriptsToRun.
    Write-Host "`n==== Executing selected scripts ===="
    foreach ($Script in $ScriptsToRun) {
        Write-Host "`n--- Running: $($Script.Name) ---"
        try {
            # Execute the script and pass the updated config hashtable.
            & "$PSScriptRoot\$($Script.Name)" -Config $Config
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: $($Script.Name) exited with code $LASTEXITCODE."
                # You can decide here if you want to continue or break.
                break
            }
        }
        catch {
            Write-Host "ERROR: Exception in $($Script.Name). $_"
            # Decide if you want to continue or break.
            break
        }
    }

    Write-Host "`n==== Selected scripts run completed! ===="

    # Now ask if they want to run more scripts or exit.
    $runMore = Read-Host "Run more scripts? (Y/N or 'exit')"
    if ($runMore -match '^(?i)(n|exit)$') {
        break
    }
}

Write-Host "`nAll done!"
exit 0
