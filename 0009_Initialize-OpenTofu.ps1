<#
.SYNOPSIS
  Initialize OpenTofu using Hyper-V settings from config.json.

.DESCRIPTION
  - Reads InfraRepoUrl and InfraRepoPath from the passed-in config.
  - If InfraRepoUrl is provided, clones/copies .tf files into InfraRepoPath.
  - Otherwise, generates a main.tf using Hyper-V config.
  - Checks that the tofu command is available, and if not, adds the known installation folder to PATH.
  - Runs 'tofu init' to initialize OpenTofu in InfraRepoPath.
#>

Param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Config
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "---- Hyper-V Configuration Check ----"
Write-Host "Final Hyper-V configuration:"
$Config.HyperV | Format-List

# --------------------------------------------------
# 1) Determine infra repo path
# --------------------------------------------------
$infraRepoUrl  = $Config.InfraRepoUrl
$infraRepoPath = $Config.InfraRepoPath

# Fallback if InfraRepoPath is not specified
if ([string]::IsNullOrWhiteSpace($infraRepoPath)) {
    $infraRepoPath = Join-Path $PSScriptRoot "my-infra"
}

Write-Host "Using InfraRepoPath: $infraRepoPath"

# Ensure local directory exists
if (!(Test-Path $infraRepoPath)) {
    New-Item -ItemType Directory -Path $infraRepoPath -Force | Out-Null
    Write-Host "Created directory: $infraRepoPath"
}
else {
    Write-Host "Directory already exists: $infraRepoPath"
}

# --------------------------------------------------
# 2) If InfraRepoUrl is given, clone/copy .tf files
# --------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($infraRepoUrl)) {
    Write-Host "InfraRepoUrl detected: $infraRepoUrl"

    # Clone to a temp folder, then copy only .tf files
    $tempClonePath = Join-Path $env:TEMP ("infraRepoClone_" + [guid]::NewGuid().ToString())
    if (Test-Path $tempClonePath) {
        Remove-Item -Recurse -Force $tempClonePath
    }

    Write-Host "Cloning $infraRepoUrl to temp path $tempClonePath..."
    git clone $infraRepoUrl $tempClonePath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "ERROR: Failed to clone $infraRepoUrl"
        exit 1
    }

    Write-Host "Copying .tf files from $tempClonePath to $infraRepoPath..."
    $tfFiles = Get-ChildItem -Path $tempClonePath -Filter '*.tf' -Recurse -File
    foreach ($file in $tfFiles) {
        # Use char array for TrimStart so it's not a 2-char string
        $relativePath = $file.FullName.Substring($tempClonePath.Length).TrimStart([char]'\\',[char]'/')
        $dest = Join-Path $infraRepoPath $relativePath
        $destDir = Split-Path $dest -Parent
        if (!(Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        Copy-Item -Path $file.FullName -Destination $dest -Force
    }

    Remove-Item -Recurse -Force $tempClonePath
    Write-Host "Successfully retrieved .tf files from InfraRepoUrl."
}
else {
    Write-Host "No InfraRepoUrl provided. Using local or default .tf files."

    # If no main.tf found, create one from Hyper-V config
    $tfFile = Join-Path -Path $infraRepoPath -ChildPath "main.tf"
    if (-not (Test-Path $tfFile)) {
        Write-Host "No main.tf found; creating main.tf using Hyper-V configuration..."
        $tfContent = @"
terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "1.2.1"
    }
  }
}

provider "hyperv" {
  user            = "$($Config.HyperV.User)"
  password        = "$($Config.HyperV.Password)"
  host            = "$($Config.HyperV.Host)"
  port            = $($Config.HyperV.Port)
  https           = $($Config.HyperV.Https.ToString().ToLower())
  insecure        = $($Config.HyperV.Insecure.ToString().ToLower())
  use_ntlm        = $($Config.HyperV.UseNtlm.ToString().ToLower())
  tls_server_name = "$($Config.HyperV.TlsServerName)"
  cacert_path     = "$($Config.HyperV.CacertPath)"
  cert_path       = "$($Config.HyperV.CertPath)"
  key_path        = "$($Config.HyperV.KeyPath)"
  script_path     = "$($Config.HyperV.ScriptPath)"
  timeout         = "$($Config.HyperV.Timeout)"
}
"@
        Set-Content -Path $tfFile -Value $tfContent
        Write-Host "Created main.tf at $tfFile"
    }
    else {
        Write-Host "main.tf already exists; not overwriting."
    }
}

# --------------------------------------------------
# 3) Check if tofu is in the PATH. If not, add it.
# --------------------------------------------------
$tofuCmd = Get-Command tofu -ErrorAction SilentlyContinue
if (-not $tofuCmd) {
    $defaultTofuExe = Join-Path $env:USERPROFILE -ChildPath "AppData\\Local\\Programs\\OpenTofu\\tofu.exe"
    if (Test-Path $defaultTofuExe) {
        Write-Host "Tofu command not found in PATH. Adding its folder to the session PATH..."
        $tofuFolder = Split-Path -Path $defaultTofuExe
        $env:PATH = "$env:PATH;$tofuFolder"
        $tofuCmd = Get-Command tofu -ErrorAction SilentlyContinue
        if (-not $tofuCmd) {
            Write-Warning "Even after updating PATH, tofu command is not recognized."
        }
        else {
            Write-Host "Tofu command found: $($tofuCmd.Path)"
        }
    }
    else {
        Write-Error "Tofu executable not found at $defaultTofuExe. Please install OpenTofu or update your PATH."
        exit 1
    }
}

# --------------------------------------------------
# 4) Run tofu init in InfraRepoPath
# --------------------------------------------------
Write-Host "Initializing OpenTofu in $infraRepoPath..."
Push-Location $infraRepoPath
try {
    tofu init
}
catch {
    Write-Error "Failed to run 'tofu init'. Ensure OpenTofu is installed and available in the PATH."
    Pop-Location
    exit 1
}
Pop-Location

Write-Host "OpenTofu initialized successfully."

Write-Host @"
NEXT STEPS:
1. Check or edit the .tf files in '$infraRepoPath'.
2. Run 'tofu plan' to preview changes.
3. Run 'tofu apply' to provision resources.
"@

# Optionally place you in $infraRepoPath at the end
Set-Location $infraRepoPath
exit 0
