Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

# Determine InfraPath
$InfraPath = if ($Config.InfraRepoPath) { $Config.InfraRepoPath } else { "C:\Temp\base-infra" }

# Ensure the local directory exists; create if it does not
Write-Host "Ensuring local path '$InfraPath' exists..."
if (-not (Test-Path $InfraPath)) {
    Write-Host "Path not found. Creating directory..."
    New-Item -ItemType Directory -Path $InfraPath -Force | Out-Null
}

# Check if the directory is a git repository
if (-not (Test-Path (Join-Path $InfraPath ".git"))) {
    Write-Host "Directory is not a git repository. Cloning repository..."
    git clone $config.InfraRepoUrl $InfraPath
} else {
    Write-Host "Git repository found. Updating repository..."
    Push-Location $InfraPath
    try {
        git reset --hard
        git clean -fd
        git pull
    } catch {
        Write-Error "An error occurred while updating the repository: $_"
    } finally {
        Pop-Location
    }
}
