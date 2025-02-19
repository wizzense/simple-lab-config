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

# We'll store status codes here if needed
$exitCode = 0

# Helper function: test whether a product is installed via registry display name.
function Test-ProductInstalled {
    param(
        [string[]]$productNames
    )
    try {
        $installedApps = @()

        # 64-bit
        $installedApps += Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* 2>$null `
                          | Select-Object DisplayName, InstallLocation
        # 32-bit
        $installedApps += Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* 2>$null `
                          | Select-Object DisplayName, InstallLocation

        foreach ($productName in $productNames) {
            $found = $installedApps | Where-Object { $_.DisplayName -like "*$productName*" }
            if ($found) {
                return $true
            }
        }
    } catch {
        # If we can't read registry or no items found, we just continue
    }
    return $false
}

# Helper function: do we actually have 'git.exe' in PATH and can run it?
function Test-GitInPath {
    try {
        git --version | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Helper function: do we have 'gh.exe'?
function Test-GhInPath {
    try {
        gh --version | Out-Null
        return $true
    } catch {
        return $false
    }
}

# ------------------------------------------------
# (2) Check/Install Git for Server Core
# ------------------------------------------------
Write-Host "==== (2) Check if Git is installed and in PATH ===="
$gitInPath = $false

try {
    # First, see if the 'git' command is recognized
    $gitInPath = Test-GitInPath

    if ($gitInPath) {
        Write-Host "Git is already available in PATH."
    } else {
        # If not in PATH, check if installed but just missing from PATH
        if (Test-ProductInstalled -productNames "Git") {
            Write-Warning "Git is installed but not in PATH. We'll try to locate it and add it to PATH."
            # Attempt to find Git in the typical location:
            $possibleLocations = @(
                "$($env:ProgramFiles)\Git\cmd\git.exe",
                "$($env:ProgramFiles)\Git\bin\git.exe",
                "$($env:ProgramFiles(x86))\Git\cmd\git.exe",
                "$($env:ProgramFiles(x86))\Git\bin\git.exe"
            )
            $foundGit = $possibleLocations | Where-Object { Test-Path $_ }
            if ($foundGit) {
                # Take the first one
                $gitExePath = $foundGit[0]
                $gitDir = Split-Path $gitExePath
                Write-Host "Found Git at: $gitExePath. Adding to PATH for the current session."
                $env:Path = "$gitDir;$env:Path"
                # Re-check
                if (Test-GitInPath) {
                    Write-Host "Git is now in PATH for this session."
                    $gitInPath = $true
                } else {
                    Write-Error "Git was found at $gitExePath, but we still can't execute 'git' in this session."
                }
            } else {
                Write-Warning "Could not find a typical Git install path. We'll attempt a fresh install."
            }
        }

        # If still not in PATH or not installed, do a minimal install
        if (-not $gitInPath) {
            Write-Host "Performing a new minimal Git install (Server Core)."

            # Example: Minimal/Portable Git from Git for Windows (64-bit)
            # Adjust to your preferred version:
            $gitInstallerUrl = $config.GitInstallerUrl
            if (-not $gitInstallerUrl) {
                # fallback if config doesn't specify
                $gitInstallerUrl = "https://github.com/git-for-windows/git/releases/download/v2.39.1.windows.1/MinGit-2.39.1-64-bit.zip"
            }

            Write-Host "Downloading minimal Git from $gitInstallerUrl ..."
            $gitZip = Join-Path $env:TEMP "git-minimal.zip"
            try {
                Invoke-WebRequest -Uri $gitInstallerUrl -OutFile $gitZip -UseBasicParsing
            } catch {
                Write-Error "Failed to download minimal Git. $($_.Exception.Message)"
                exit 1
            }

            # Unzip it to a permanent folder (e.g., C:\Git)
            $gitInstallPath = "C:\Git"
            if (!(Test-Path $gitInstallPath)) {
                New-Item -ItemType Directory -Path $gitInstallPath | Out-Null
            }

            Write-Host "Extracting $gitZip to $gitInstallPath"
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($gitZip, $gitInstallPath)

            # Clean up
            Remove-Item $gitZip -Force

            # Add the 'cmd' folder to PATH for the current session
            $gitCmdPath = Join-Path $gitInstallPath "cmd"
            $env:Path = "$gitCmdPath;$env:Path"

            # Confirm we can run git now
            if (Test-GitInPath) {
                Write-Host "Git minimal installation succeeded and is now in PATH."
                $gitInPath = $true
            } else {
                Write-Error "ERROR: Even after installing minimal Git, 'git' is not recognized."
                exit 1
            }
        }
    }

    # Now configure Git if we have it
    if ($gitInPath) {
        Write-Host "Configuring Git username/email..."
        try {
            git config --global user.name $config.GitUsername
            git config --global user.email $config.GitEmail
        } catch {
            Write-Error "Failed to configure Git username/email. $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Error "Unexpected error installing/configuring Git: $($_.Exception.Message)"
    exit 1
}

# ------------------------------------------------
# (3) Check/Install GitHub CLI (Optional)
# ------------------------------------------------
Write-Host "`n==== (3) Check if GitHub CLI is installed (optional) ===="
$ghInPath = $false
try {
    $ghInPath = Test-GhInPath
    if ($ghInPath) {
        Write-Host "GitHub CLI is already available in PATH."
    } else {
        if (Test-ProductInstalled -productNames "GitHub CLI") {
            Write-Warning "GitHub CLI is installed but not in PATH. We'll attempt to find it."
            # Typically installed under "C:\Program Files\GitHub CLI\gh.exe"
            $possibleGh = @(
                "$($env:ProgramFiles)\GitHub CLI\gh.exe",
                "$($env:ProgramFiles(x86))\GitHub CLI\gh.exe"
            ) | Where-Object { Test-Path $_ }
            if ($possibleGh) {
                $ghExe = $possibleGh[0]
                $ghDir = Split-Path $ghExe
                $env:Path = "$ghDir;$env:Path"
                if (Test-GhInPath) {
                    Write-Host "GitHub CLI is now in PATH for this session."
                    $ghInPath = $true
                } else {
                    Write-Warning "We found GH at $ghExe but couldn't run it in this session."
                }
            } else {
                Write-Warning "Could not find GitHub CLI location. Will try installing fresh."
            }
        }
        if (-not $ghInPath) {
            Write-Host "Attempting to install GitHub CLI..."

            $ghCliUrl = $config.GitHubCLIInstallerUrl
            if (-not $ghCliUrl) {
                # fallback if config doesn't specify
                $ghCliUrl = "https://github.com/cli/cli/releases/latest/download/gh_2.20.2_windows_amd64.msi"
            }

            $ghCliInstaller = Join-Path -Path $env:TEMP -ChildPath "GitHubCLIInstaller.msi"
            try {
                Invoke-WebRequest -Uri $ghCliUrl -OutFile $ghCliInstaller -UseBasicParsing
            } catch {
                Write-Error "Failed to download GitHub CLI. $($_.Exception.Message)"
                exit 1
            }

            Write-Host "Installing GitHub CLI silently..."
            try {
                Start-Process msiexec.exe `
                    -ArgumentList "/i `"$ghCliInstaller`" /quiet /norestart /log `"$env:TEMP\ghCliInstall.log`"" `
                    -Wait -Verb RunAs
            } catch {
                Write-Error "Failed to install GitHub CLI. $($_.Exception.Message)"
            } finally {
                Remove-Item -Path $ghCliInstaller -ErrorAction SilentlyContinue
            }

            # Attempt to see if GH is now in PATH automatically
            if (Test-GhInPath) {
                Write-Host "GitHub CLI installation completed and is in PATH."
                $ghInPath = $true
            } else {
                Write-Warning "GitHub CLI installed, but 'gh' is not in PATH. You may need to set PATH manually."
            }
        }
    }
}
catch {
    Write-Error "Unexpected error installing/configuring GitHub CLI: $($_.Exception.Message)"
}

# ------------------------------------------------
# (4) Clone or Update the Repository
# ------------------------------------------------
Write-Host "`n==== (4) Clone or update the target repository ===="
if (-not $gitInPath) {
    Write-Error "ERROR: We cannot continue because Git is not available in PATH."
    exit 1
}

$repoUrl = $config.RepoUrl
if (-not $repoUrl) {
    Write-Error "ERROR: config.json does not specify 'RepoUrl'."
    exit 1
}

# If config.LocalPath is empty, choose a default
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

# Derive the repo folder name
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
# (5) Invoke the Runner Script
# ------------------------------------------------
Write-Host "`n==== (5) Invoke the runner script ===="
$runnerScriptName = $config.RunnerScriptName
if (-not $runnerScriptName) {
    Write-Warning "No runner script name specified in config. Exiting gracefully."
    exit 0
}

# Confirm the path to runner
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

Write-Host "`n=== Kicker script finished successfully! ==="
exit 0
