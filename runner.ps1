<#
.SYNOPSIS
  Master runner script to sequentially execute configuration scripts.
#>

Param(
    [string]$ConfigFile = ".\config.json"
)

Write-Host "==== Loading configuration ===="
if (!(Test-Path $ConfigFile)) {
    Write-Host "ERROR: Cannot find config file at $ConfigFile"
    exit 1
}

# Load and parse JSON
try {
    $Config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
} catch {
    Write-Host "ERROR: Failed to parse JSON from $ConfigFile. $_"
    exit 1
}

Write-Host "==== Locating scripts ===="
# Find all files named NNNN_*.ps1
$ScriptFiles = Get-ChildItem -Path . -Filter "????_*.ps1" -File |
    Sort-Object -Property Name

If (!$ScriptFiles) {
    Write-Host "ERROR: No scripts found matching ????_*.ps1 in current directory."
    exit 1
}

# List the found scripts with their 4-digit prefixes
Write-Host "==== Found the following scripts ===="
foreach ($Script in $ScriptFiles) {
    # Assumes the first 4 characters are the unique identifier
    $prefix = $Script.Name.Substring(0,4)
    Write-Host "$prefix - $($Script.Name)"
}

# Prompt user for selection input
$selection = Read-Host "Enter the script numbers you want to run (comma separated, e.g. 0003,0005,0007)"

# If no selection is made, exit or you could choose to run all
if ([string]::IsNullOrWhiteSpace($selection)) {
    Write-Host "No selection made. Exiting."
    exit 0
}

# Sanitize input: split by comma, trim spaces, and select only those that are 4-digit numbers
$selectedPrefixes = $selection -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d{4}$' }

if (!$selectedPrefixes) {
    Write-Host "ERROR: No valid 4-digit prefixes found in input. Exiting."
    exit 1
}

# Filter the scripts that match any of the provided prefixes (preserving sorted order)
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
        # Dot-source or call the script, passing the config
        & .\$($Script.Name) -Config $Config
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
