Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

# Define local path (fallback if not in config)
$localPath = if ($config.LocalPath) { $config.LocalPath } else { "$env:USERPROFILE\Documents\ServerSetup" }

# Ensure local directory exists
Write-Host "Ensuring local path '$localPath' exists..."
if ((Test-Path $localPath)) {
    Remove-Item -Recurse -Force -Path $localPath
}

$InfraPath = if ($config.InfraRepoPath) { $config.InfraRepoPath } else { "C:\Temp\base-infra" }

# Ensure local directory exists
Write-Host "Ensuring local path '$InfraPath' exists..."
if ((Test-Path $InfraPath)) {
    Remove-Item -Recurse -Force -Path $InfraPath
}