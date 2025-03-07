Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

<# Define local path (fallback if not in config)

Doesn't work because this will be running from the root of the repo, not the user's home directory.

Can update this later to copy the script to C:\temp and run it from there.

$localPath = if ($config.LocalPath) { $config.LocalPath } else { "$env:USERPROFILE\Documents\ServerSetup" }

# Ensure local directory exists
Write-Host "Ensuring local path '$localPath' exists..."
if ((Test-Path $localPath)) {
    Remove-Item -Recurse -Force -Path $localPath
}

#>

$InfraPath = if ($config.InfraRepoPath) { $config.InfraRepoPath } else { "C:\Temp\base-infra" }

# Ensure local directory exists
Write-Host "Ensuring local path '$InfraPath' exists..."
if ((Test-Path $InfraPath)) {
    Remove-Item -Recurse -Force -Path $InfraPath
}