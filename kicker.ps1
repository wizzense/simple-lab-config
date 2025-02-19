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
$gitExe = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitExe) {
    Write-Host "Git is not installed. Downloading and installing Git for Windows..."

    $gitInstallerUrl = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.39.2-64-bit.exe"
    $gitInstallerPath = Join-Path -Path $env:TEMP -ChildPath "GitInstaller.exe"

    Invoke-WebRequest -Uri $gitInstallerUrl -OutFile $gitInstallerPath -UseBasicParsing
    Write-Host "Installing Git silently..."
    Start-Process -FilePath $gitInstallerPath -ArgumentList "/SILENT" -Wait -NoNewWindow

    Remove-Item -Path $gitInstallerPath -ErrorAction SilentlyContinue
    Write-Host "Git installation completed."

    # Add Git to PATH
    $gitPath = "C:\Program Files\Git\cmd"
    if (Test-Path $gitPath) {
        $env:Path = "$gitPath;$env:Path"
        [System.Environment]::SetEnvironmentVariable("Path", "$gitPath;$([System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine))", [System.EnvironmentVariableTarget]::Machine)
    }
}

# Verify Git installation
$gitVersion = git --version 2>$null
if ($gitVersion) {
    Write-Host "Git is installed: $gitVersion"
} else {
    Write-Error "ERROR: Git installation failed. Exiting."
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

Write-Host "==== Checking GitHub CLI Authentication ===="
$authStatus = gh auth status 2>&1
if ($authStatus -match "not logged into github.com") {
    Write-Host "GitHub CLI is not authenticated. Attempting to log in..."
    gh auth login --web
    if ($LASTEXITCODE -ne 0) {
        Write-Error "ERROR: GitHub authentication failed. Please log in manually using 'gh auth login'."
        exit 1
    }
} else {
    Write-Host "GitHub CLI is authenticated."
}

# ------------------------------------------------
# (4) Clone or Update Repository
# ------------------------------------------------
Write-Host "==== Cloning or updating the target repository ===="
$repoUrl = $config.RepoUrl
if (-not $repoUrl) {
    Write-Error "ERROR: config.json does not specify 'RepoUrl'."
    exit 1
}

$localPath = $config.LocalPath
if (-not $localPath) {
    $localPath = "$env:USERPROFILE\Documents\ServerSetup"
}

Write-Host "Ensuring local path '$localPath' exists..."
if (!(Test-Path $localPath)) {
    New-Item -ItemType Directory -Path $localPath | Out-Null
}

$repoName = ($repoUrl.Split('/')[-1]).Replace(".git", "")
$repoPath = Join-Path $localPath $repoName

if (!(Test-Path $repoPath)) {
    Write-Host "Cloning repository from $repoUrl to $repoPath..."
    gh repo clone $repoUrl $repoPath 2>&1 | Tee-Object -FilePath "$env:TEMP\gh_clone_log.txt"

    # Verify that cloning succeeded
    if (!(Test-Path $repoPath)) {
        Write-Error "ERROR: Repository cloning failed. Check log: $env:TEMP\gh_clone_log.txt"
        exit 1
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
