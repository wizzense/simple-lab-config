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

Write-Host "==== Executing scripts in order ===="
foreach ($Script in $ScriptFiles) {
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

Write-Host "`n==== All scripts have run successfully! ===="
exit 0
