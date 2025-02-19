<#
.SYNOPSIS
  Kicker script for a fresh Windows Server Core setup with robust error handling.
#>

Param(
    [string]$ConfigFile = "$PSScriptRoot\config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------
# (1) Load Configuration
# ------------------------------------------------
Write-Host "==== (1) Loading configuration file ===="
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
# (2) Helper Functions
# ------------------------------------------------
function Test-ProductInstalled {
    param([string[]]$productNames)
    try {
        $installedApps = @()
        $installedApps += Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* 2>$null |
                          Select-Object DisplayName, InstallLocation
        $installedApps += Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* 2>$null |
                          Select-Object DisplayName, InstallLocation

        foreach ($productName in $productNames) {
            if ($installedApps | Where-Object { $_.DisplayName -like "*$productName*" }) { return $true }
        }
    } catch {}
    return $false
}

function Test-GitInPath {
    try { git --version | Out-Null; return $true } catch { return $false }
}

function Test-GhInPath {
    try { gh --version | Out-Null; return $true } catch { return $false }
}

# ------------------------------------------------
# (3) Ensure Git is Installed and in PATH
# ------------------------------------------------
Write-Host "==== (2) Check if Git is installed and in PATH ===="
$gitInPath = Test-GitInPath

if (-not $gitInPath) {
    Write-Warning "Git is installed but not found in PATH. Attempting to locate Git manually."
    
    $possibleGitLocations = @(
        "C:\Program Files\Git\cmd",
        "C:\Program Files\Git\bin",
        "C:\Program Files (x86)\Git\cmd",
        "C:\Program Files (x86)\Git\bin"
    )
    foreach ($location in $possibleGitLocations) {
        if (Test-Path "$location\git.exe") {
            $env:Path = "$location;$env:Path"
            Write-Host "Manually added Git to PATH: $location"
            break
        }
    }

    if (Test-GitInPath) {
        Write-Host "Git is now available in PATH."
        $gitInPath = $true
    } else {
        Write-Error "Git is not recognized even after manual PATH fix."
        exit 1
    }
}

# Persist Git in System PATH
[System.Environment]::SetEnvironmentVariable("Path", "$env:Path", [System.EnvironmentVariableTarget]::Machine)

# ------------------------------------------------
# (4) Configure Git (If Available)
# ------------------------------------------------
if ($gitInPath) {
    Write-Host "Configuring Git username/email..."
    try {
        git config --global user.name $config.GitUsername
        git config --global user.email $config.GitEmail
    } catch {
        Write-Error "Failed to configure Git. $($_.Exception.Message)"
    }
} else {
    Write-Error "Git is required but not available. Exiting."
    exit 1
}

# ------------------------------------------------
# (5) Check/Install GitHub CLI (Optional)
# ------------------------------------------------
Write-Host "==== (3) Check if GitHub CLI is installed (optional) ===="
$ghInPath = Test-GhInPath

if (-not $ghInPath) {
    Write-Warning "GitHub CLI is installed but not in PATH. Attempting to locate it."
    
    $possibleGhLocations = @(
        "C:\Program Files\GitHub CLI\gh.exe",
        "C:\Program Files (x86)\GitHub CLI\gh.exe"
    )
    foreach ($location in $possibleGhLocations) {
        if (Test-Path $location) {
            $env:Path = "$location;$env:Path"
            Write-Host "Manually added GitHub CLI to PATH: $location"
            break
        }
    }
}

# ------------------------------------------------
# (6) Clone or Update the Repository
# ------------------------------------------------
Write-Host "==== (4) Clone or update the target repository ===="
if (-not $gitInPath) {
    Write-Error "ERROR: We cannot continue because Git is not available in PATH."
    exit 1
}

$repoUrl = $config.RepoUrl
if (-not $repoUrl) {
    Write-Error "ERROR: config.json does not specify 'RepoUrl'."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($config.LocalPath)) {
    $config.LocalPath = Join-Path $env:USERPROFILE "Documents\ServerSetup"
}

Write-Host "Ensuring local path '$($config.LocalPath)' exists..."
try {
    if (-not (Test-Path $config.LocalPath)) {
        New-Item -ItemType Directory -Path $config.LocalPath | Out-Null
    }
} catch {
    Write-Error "ERROR: Could not create local path $($config.LocalPath). $($_.Exception.Message)"
    exit 1
}

$repoName = ($repoUrl.Split('/')[-1]).Replace(".git", "")
$repoPath = Join-Path $config.LocalPath $repoName

if (-not (Test-Path $repoPath)) {
    Write-Host "Repository doesn't exist locally. Cloning from $repoUrl..."
    try {
        git clone $repoUrl $repoPath
    } catch {
        Write-Error "ERROR: Failed to clone from $repoUrl. $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "Repository already exists at $repoPath. Pulling latest changes..."
    Push-Location $repoPath
    try {
        git pull
    } catch {
        Write-Warning "Could not pull updates. $($_.Exception.Message)"
    }
    Pop-Location
}

# ------------------------------------------------
# (7) Invoke the Runner Script
# ------------------------------------------------
Write-Host "==== (5) Invoke the runner script ===="
$runnerScriptName = $config.RunnerScriptName
if (-not $runnerScriptName) {
    Write-Warning "No runner script name specified in config. Exiting gracefully."
    exit 0
}

Set-Location $repoPath
if (-not (Test-Path $runnerScriptName)) {
    Write-Error "ERROR: Could not find $runnerScriptName in $repoPath. Exiting."
    exit 1
}

Write-Host "Running $runnerScriptName from $repoPath ..."
try {
    . .\$runnerScriptName
} catch {
    Write-Error "ERROR: $runnerScriptName threw an exception. $($_.Exception.Message)"
    exit 1
}

Write-Host "=== Kicker script finished successfully! ==="
exit 0
