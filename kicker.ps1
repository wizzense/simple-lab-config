<#
.SYNOPSIS
  Kicker script for a fresh Windows Server Core setup.
  1) Installs/configures Git (if missing).
  2) Installs/configures GitHub CLI (if missing).
  3) Clones a repository using info from config.json.
  4) Invokes "runner.ps1" from that repository to do the real tasks.
#>

Param(
    [string]$ConfigFile = "$PSScriptRoot\config.json"
)

Write-Host "==== (1) Loading configuration file ===="
if (!(Test-Path $ConfigFile)) {
    Write-Host "ERROR: Could not find config.json at $ConfigFile"
    exit 1
}

try {
    $config = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json
    Write-Host "Config file loaded from $ConfigFile."
} catch {
    Write-Host "ERROR: Failed to parse JSON from $ConfigFile. $_"
    exit 1
}

# Helper function: test whether a product is installed.
function Test-ProductInstalled {
    param(
        [string[]]$productNames
    )

    $installedApps = @()

    # 64-bit uninstall registry
    $installedApps += Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* 2>$null | Select-Object DisplayName, InstallLocation
    # 32-bit uninstall registry
    $installedApps += Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* 2>$null | Select-Object DisplayName, InstallLocation

    foreach ($productName in $productNames) {
        $product = $installedApps | Where-Object { $_.DisplayName -like "*$productName*" }
        if ($null -ne $product) {
            return $true
        }
    }
    return $false
}

Write-Host "==== (2) Check if Git is installed ===="
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "Git is already available in PATH."
} else {
    # If not in PATH, also confirm via registry
    if (Test-ProductInstalled -productNames "Git") {
        Write-Host "Git appears to be installed but not in PATH. We'll assume it's installed."
    } else {
        # Install Git
        Write-Host "Git not found. Downloading Git installer from $($config.GitInstallerUrl)..."
        $gitInstaller = Join-Path -Path $env:TEMP -ChildPath "GitInstaller.exe"
        Invoke-WebRequest -Uri $config.GitInstallerUrl -OutFile $gitInstaller -UseBasicParsing

        Write-Host "Running Git installer silently..."
        Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT" -Wait
        Remove-Item -Path $gitInstaller -ErrorAction SilentlyContinue
        Write-Host "Git installation completed."
    }

    Write-Host "Configuring Git username/email..."
    git config --global user.name $config.GitUsername
    git config --global user.email $config.GitEmail
}

Write-Host "==== (3) Check if GitHub CLI is installed (optional) ===="
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "GitHub CLI is already available."
} else {
    if (Test-ProductInstalled -productNames "GitHub CLI") {
        Write-Host "GitHub CLI is installed but not in PATH. We'll assume it's present."
    } else {
        Write-Host "GitHub CLI not found. Downloading from $($config.GitHubCLIInstallerUrl)..."
        $ghCliInstaller = Join-Path -Path $env:TEMP -ChildPath "GitHubCLIInstaller.msi"
        Invoke-WebRequest -Uri $config.GitHubCLIInstallerUrl -OutFile $ghCliInstaller -UseBasicParsing

        Write-Host "Installing GitHub CLI silently..."
        Start-Process msiexec.exe -ArgumentList "/i `"$ghCliInstaller`" /quiet /norestart /log `"$env:TEMP\ghCliInstall.log`"" -Wait -Verb RunAs
        Remove-Item -Path $ghCliInstaller -ErrorAction SilentlyContinue
        Write-Host "GitHub CLI installation completed."
    }
}

Write-Host "==== (4) Clone or update the target repository ===="
# If config.LocalPath is empty, construct a default:
if ([string]::IsNullOrWhiteSpace($config.LocalPath)) {
    $config.LocalPath = Join-Path $env:USERPROFILE "Documents\ServerSetup"
}

Write-Host "Ensuring local path '$($config.LocalPath)' exists..."
if (-not (Test-Path $config.LocalPath)) {
    New-Item -ItemType Directory -Path $config.LocalPath | Out-Null
}

# Determine the final path for the repo
$repoUrl = $config.RepoUrl
# e.g. 'MyServerSetupRepo'
$repoName = ($repoUrl.Split('/')[-1]).Replace(".git", "")
$repoPath = Join-Path $config.LocalPath $repoName

if (!(Test-Path $repoPath)) {
    Write-Host "Repository doesn't exist locally. Cloning from $repoUrl..."
    git clone $repoUrl $repoPath
} else {
    Write-Host "Repository already exists at $repoPath. Let's fetch latest changes..."
    Push-Location $repoPath
    git pull
    Pop-Location
}

Write-Host "==== (5) Invoke the runner script ===="
$runnerScript = $config.RunnerScriptName
if (-not $runnerScript) {
    Write-Host "No runner script name specified in config. Skipping."
    exit 0
}

Write-Host "Switching to $repoPath"
Set-Location $repoPath

Write-Host "Running $runnerScript..."
if (!(Test-Path $runnerScript)) {
    Write-Host "ERROR: Could not find $runnerScript in $repoPath. Exiting."
    exit 1
}

# Dot-source or call the runner
. .\$runnerScript

Write-Host "`n=== Kicker script finished! ==="
exit 0
