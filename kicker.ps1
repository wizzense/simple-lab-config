<#
.SYNOPSIS
  Kicker script for a fresh Windows Server Core setup with robust error handling.

  1) Loads config.json from the same folder by default (override with -ConfigFile).
  2) Checks if command-line Git is installed and in PATH.
     - Installs a minimal version if missing.
     - Updates PATH if installed but not found in PATH.
  3) Checks if GitHub CLI is installed (optional).
  4) Clones a repository from config.json -> RepoUrl to config.json -> LocalPath (or a default path).
  5) Invokes runner.ps1 from that repo.
#>

Param(
    [string]$ConfigFile = "$PSScriptRoot\config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'  # So any error throws an exception

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

# First, check if Git is already installed
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

    # Ensure Git is in PATH
    $gitDir = "C:\Program Files\Git\cmd"
    if (Test-Path $gitDir) {
        $env:Path = "$gitDir;$env:Path"
        [System.Environment]::SetEnvironmentVariable("Path", "$gitDir;$([System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine))", [System.EnvironmentVariableTarget]::Machine)
    }
}

# **Force refresh of environment variables**
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# **Final Git check**
$gitVersion = git --version 2>$null
if ($gitVersion) {
    Write-Host "Git is installed and working: $gitVersion"
} else {
    Write-Error "ERROR: Git installation failed or is not accessible. Exiting."
    exit 1
}

# ------------------------------------------------
# (3) Check GitHub CLI
# ------------------------------------------------
Write-Host "==== Checking if GitHub CLI is installed ===="
$ghExePath = "C:\Program Files\GitHub CLI\gh.exe"
if (Test-Path $ghExePath) {
    Write-Host "GitHub CLI found at $ghExePath. Adding to PATH."
    $env:Path = "C:\Program Files\GitHub CLI;$env:Path"
} else {
    Write-Host "GitHub CLI not found. Downloading from $($config.GitHubCLIInstallerUrl)..."
    $ghCliInstaller = Join-Path -Path $env:TEMP -ChildPath "GitHubCLIInstaller.msi"
    Invoke-WebRequest -Uri $config.GitHubCLIInstallerUrl -OutFile $ghCliInstaller -UseBasicParsing

    Write-Host "Installing GitHub CLI silently..."
    Start-Process msiexec.exe -ArgumentList "/i `"$ghCliInstaller`" /quiet /norestart /log `"$env:TEMP\ghCliInstall.log`"" -Wait -Verb RunAs
    Remove-Item -Path $ghCliInstaller -ErrorAction SilentlyContinue

    Write-Host "GitHub CLI installation completed."
}

if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
    $ghExe = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $ghExe) {
        # Get the current machine PATH
        $currentMachinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
        
        # Check if the GitHub CLI path is already included
        if ($currentMachinePath -notmatch [regex]::Escape("C:\Program Files\GitHub CLI")) {
            # Prepend GitHub CLI to the machine PATH
            $newMachinePath = "C:\Program Files\GitHub CLI;" + $currentMachinePath
            [System.Environment]::SetEnvironmentVariable("Path", $newMachinePath, [System.EnvironmentVariableTarget]::Machine)
            Write-Host "Added GitHub CLI to the system PATH. Please restart your session or computer for changes to take effect."
        } else {
            Write-Host "GitHub CLI is already in the system PATH."
        }
    }
    else {
        Write-Error "gh.exe not found at '$ghExe'"
    }
} else {
    Write-Host "GitHub CLI is already accessible via the PATH."
}


Write-Host "==== Checking GitHub CLI Authentication ===="

try {
    # This will throw if not authenticated because $ErrorActionPreference is 'Stop'
    $authStatus = & gh auth status 2>&1
    Write-Host "GitHub CLI is authenticated."
}
catch {
    Write-Host "GitHub CLI is not authenticated. Attempting to log in..."
    try {
        # Launch interactive login (opens your browser)
        Start-Process -FilePath "gh" -ArgumentList "auth login --web --protocol https" -Wait -ErrorAction Stop
    }
    catch {
        Write-Error "ERROR: Failed to initiate interactive GitHub CLI login."
        exit 1
    }
    
    # After interactive login, recheck authentication
    try {
        $authStatus = & gh auth status 2>&1
        Write-Host "GitHub CLI is now authenticated."
    }
    catch {
        Write-Error "ERROR: GitHub authentication failed. Please log in manually using 'gh auth login'."
        exit 1
    }
}




# ------------------------------------------------
# (4) Clone or Update Repository
# ------------------------------------------------
Write-Host "==== Cloning or updating the target repository ===="

# Ensure config.json contains required values
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

# Define repo path and ensure it's set
$repoName = ($config.RepoUrl -split '/')[-1] -replace "\.git$", ""
$repoPath = Join-Path $localPath $repoName

if (-not $repoPath) {
    Write-Error "ERROR: Repository path could not be determined. Check config.json and retry."
    exit 1
}

# Clone or update the repository
if (!(Test-Path $repoPath)) {
    Write-Host "Cloning repository from $($config.RepoUrl) to $repoPath..."
    
    # Temporarily relax error action to avoid stopping on noncritical errors
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    
    gh repo clone $config.RepoUrl $repoPath 2>&1 | Tee-Object -FilePath "$env:TEMP\gh_clone_log.txt"
    
    # Restore the original error action preference
    $ErrorActionPreference = $prevEAP

    # Fallback to git if GitHub CLI clone appears to have failed
    if (!(Test-Path $repoPath)) {
        Write-Host "GitHub CLI clone failed. Trying git clone..."
        git clone $config.RepoUrl $repoPath 2>&1 | Tee-Object -FilePath "$env:TEMP\git_clone_log.txt"

        if (!(Test-Path $repoPath)) {
            Write-Error "ERROR: Repository cloning failed. Check logs: $env:TEMP\gh_clone_log.txt and $env:TEMP\git_clone_log.txt"
            exit 1
        }
    }
} else {
    Write-Host "Repository already exists. Pulling latest changes..."
    Push-Location $repoPath
    git pull
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
