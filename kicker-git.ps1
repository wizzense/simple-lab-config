<# 
.SYNOPSIS
  Kicker script for a fresh Windows Server Core setup with robust error handling.

  1) Loads config.json from the same folder by default (override with -ConfigFile).
  2) Checks if command-line Git is installed and in PATH.
     - Installs a minimal version if missing.
     - Updates PATH if installed but not found in PATH.
  3) Checks if GitHub CLI is installed and in PATH.
     - Installs GitHub CLI if missing.
     - Updates PATH if installed but not found in PATH.
     - Prompts for authentication if not already authenticated.
  4) Clones a repository from config.json -> RepoUrl to config.json -> LocalPath (or a default path).
  5) Invokes runner.ps1 from that repo.
#>
$ErrorActionPreference = 'Stop'  # So any error throws an exception
$ProgressPreference = 'SilentlyContinue'

Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/opentofu-lab-automation/refs/heads/main/config.json' -OutFile '.\config.json'
$ConfigFile = (Join-Path $PSScriptRoot "config.json")

# ------------------------------------------------
# (1) Load Configuration
# ------------------------------------------------
Write-Host "==== Loading configuration file ===="
if (!(Test-Path $ConfigFile)) {
    Write-Error "ERROR: Could not find config.json at $ConfigFile"
    exit 1
}

try {
    $config = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json
    Write-Host "Config file loaded from $ConfigFile."
} catch {
    Write-Error "ERROR: Failed to parse JSON from $ConfigFile. $($_.Exception.Message)"
    exit 1
}

# ------------------------------------------------
# (2) Check & Install Git for Windows
# ------------------------------------------------
Write-Host "==== Checking if Git is installed ===="
$gitPath = "C:\Program Files\Git\cmd\git.exe"

if (Test-Path $gitPath) {
    Write-Host "Git is already installed at: $gitPath"
} else {
    Write-Host "Git is not installed. Downloading and installing Git for Windows..."

    $gitInstallerUrl = "https://github.com/git-for-windows/git/releases/download/v2.48.1.windows.1/Git-2.48.1-64-bit.exe"
    $gitInstallerPath = Join-Path -Path $env:TEMP -ChildPath "GitInstaller.exe"

    Invoke-WebRequest -Uri $gitInstallerUrl -OutFile $gitInstallerPath -UseBasicParsing
    Write-Host "Installing Git silently..."
    Start-Process -FilePath $gitInstallerPath -ArgumentList "/SILENT" -Wait -NoNewWindow

    Remove-Item -Path $gitInstallerPath -ErrorAction SilentlyContinue
    Write-Host "Git installation completed."
}

# Double-check Git
try {
    & "$gitPath" --version | Write-Host
    Write-Host "Git is installed and working."
} catch {
    Write-Error "ERROR: Git installation failed or is not accessible. Exiting."
    exit 1
}

# ------------------------------------------------
# (3) Check GitHub CLI and call by explicit path
# ------------------------------------------------
Write-Host "==== Checking if GitHub CLI is installed ===="
$ghExePath = "C:\Program Files\GitHub CLI\gh.exe"

if (!(Test-Path $ghExePath)) {
    Write-Host "GitHub CLI not found. Downloading from $($config.GitHubCLIInstallerUrl)..."
    $ghCliInstaller = Join-Path -Path $env:TEMP -ChildPath "GitHubCLIInstaller.msi"
    Invoke-WebRequest -Uri $config.GitHubCLIInstallerUrl -OutFile $ghCliInstaller -UseBasicParsing

    Write-Host "Installing GitHub CLI silently..."
    Start-Process msiexec.exe -ArgumentList "/i `"$ghCliInstaller`" /quiet /norestart /log `"$env:TEMP\ghCliInstall.log`"" -Wait -Verb RunAs
    Remove-Item -Path $ghCliInstaller -ErrorAction SilentlyContinue

    Write-Host "GitHub CLI installation completed."
} else {
    Write-Host "GitHub CLI found at '$ghExePath'."
}

if (!(Test-Path $ghExePath)) {
    Write-Error "ERROR: gh.exe not found at '$ghExePath'. Installation may have failed."
    exit 1
}

# ------------------------------------------------
# (3.5) Check & Prompt for GitHub CLI Authentication
# ------------------------------------------------
Write-Host "==== Checking GitHub CLI Authentication ===="
try {
    # If not authenticated, 'gh auth status' returns non-zero exit code
    & "$ghExePath" auth status 2>&1
    Write-Host "GitHub CLI is authenticated."
}
catch {
    Write-Host "GitHub CLI is not authenticated."

    # Optional: Prompt user for a personal access token
    $pat = Read-Host "Enter your GitHub Personal Access Token (or press Enter to skip):"

    if (-not [string]::IsNullOrWhiteSpace($pat)) {
        Write-Host "Attempting PAT-based GitHub CLI login..."
        try {
            $pat | & "$ghExePath" auth login --hostname github.com --git-protocol https --with-token
        }
        catch {
            Write-Error "ERROR: PAT-based login failed. Please verify your token or try interactive login."
            exit 1
        }
    }
    else {
        # No PAT, attempt normal interactive login in the console
        Write-Host "No PAT provided. Attempting interactive login..."
        try {
            & "$ghExePath" auth login --hostname github.com --git-protocol https
        }
        catch {
            Write-Error "ERROR: Interactive login failed: $($_.Exception.Message)"
            exit 1
        }
    }

    # After the login attempt, re-check auth
    try {
        & "$ghExePath" auth status 2>&1
        Write-Host "GitHub CLI is now authenticated."
    }
    catch {
        Write-Error "ERROR: GitHub authentication failed. Please run '$ghExePath auth login' manually and re-run."
        exit 1
    }
}

# ------------------------------------------------
# (4) Clone or Update Repository (using explicit Git/gh)
# ------------------------------------------------
Write-Host "==== Cloning or updating the target repository ===="

if (-not $config.RepoUrl) {
    Write-Error "ERROR: config.json does not specify 'RepoUrl'."
    exit 1
}

# Define local path (fallback if not in config)
$localPath = if ($config.LocalPath) { $config.LocalPath } else { "$env:USERPROFILE\Documents\ServerSetup" }

# Ensure local directory exists
Write-Host "Ensuring local path '$localPath' exists..."
if (!(Test-Path $localPath)) {
    New-Item -ItemType Directory -Path $localPath -Force | Out-Null
}

# Define repo path
$repoName = ($config.RepoUrl -split '/')[-1] -replace "\.git$", ""
$repoPath = Join-Path $localPath $repoName

if (-not $repoPath) {
    Write-Error "ERROR: Repository path could not be determined. Check config.json and retry."
    exit 1
}

if (!(Test-Path $repoPath)) {
    Write-Host "Cloning repository from $($config.RepoUrl) to $repoPath..."

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    & "$ghExePath" repo clone $config.RepoUrl $repoPath 2>&1 | Tee-Object -FilePath "$env:TEMP\gh_clone_log.txt"

    $ErrorActionPreference = $prevEAP

    # Fallback to git if the GitHub CLI clone appears to have failed
    if (!(Test-Path $repoPath)) {
        Write-Host "GitHub CLI clone failed. Trying git clone..."
        & "$gitPath" clone $config.RepoUrl $repoPath 2>&1 | Tee-Object -FilePath "$env:TEMP\git_clone_log.txt"

        if (!(Test-Path $repoPath)) {
            Write-Error "ERROR: Repository cloning failed. Check logs: $env:TEMP\gh_clone_log.txt and $env:TEMP\git_clone_log.txt"
            exit 1
        }
    }
} else {
    Write-Host "Repository already exists. Pulling latest changes..."
    Push-Location $repoPath
    & "$gitPath" pull
    Pop-Location
}

# ------------------------------------------------
# (5) Invoke the Runner Script
# ------------------------------------------------
Write-Host "==== Invoking the runner script ===="
$runnerScriptName = $config.RunnerScriptName
if (-not $runnerScriptName) {
    Write-Warning "No runner script specified in config. Exiting gracefully."
    exit 0
}

Set-Location $repoPath
if (!(Test-Path $runnerScriptName)) {
    Write-Error "ERROR: Could not find $runnerScriptName in $repoPath. Exiting."
    exit 1
}

Write-Host "Running $runnerScriptName from $repoPath ..."
. .\$runnerScriptName

Write-Host "`n=== Kicker script finished successfully! ==="
exit 0
