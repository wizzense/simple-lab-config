<#
.SYNOPSIS
  Initialize OpenTofu using Hyper-V settings from config.json.

.DESCRIPTION
  - Reads InfraRepoUrl and InfraRepoPath from the passed-in config.
  - If InfraRepoUrl is provided, it clones the repo directly into InfraRepoPath.
  - Otherwise, generates a main.tf using Hyper-V config.
  - Checks that the tofu command is available, and if not, adds the known installation folder to PATH.
  - Runs 'tofu init' to initialize OpenTofu in InfraRepoPath.
#>

Param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Config
)

if ($Config.InitializeOpenTofu -eq $true) {

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
    if (Test-Path $infraRepoPath) {
        Write-Host "Directory already exists: $infraRepoPath"
    }
    else {
        New-Item -ItemType Directory -Path $infraRepoPath -Force | Out-Null
        Write-Host "Created directory: $infraRepoPath"
    }

# --------------------------------------------------
# 2) If InfraRepoUrl is given, clone directly to InfraRepoPath
# --------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($infraRepoUrl)) {
    Write-Host "InfraRepoUrl detected: $infraRepoUrl"

    # If infraRepoPath is already a Git repo, do a pull instead of clone
    if (Test-Path (Join-Path $infraRepoPath ".git")) {
        Write-Host "This directory is already a Git repository. Pulling latest changes..."
        Push-Location $infraRepoPath
        git pull
        Pop-Location
    }
    else {
        # If you want a clean slate each time, uncomment the lines below to remove existing files
        # Remove-Item -Path (Join-Path $infraRepoPath "*") -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "Cloning $infraRepoUrl to $infraRepoPath..."
        git clone $infraRepoUrl $infraRepoPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ERROR: Failed to clone $infraRepoUrl"
            exit 1
        }
    }
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
"@
        Set-Content -Path $tfFile -Value $tfContent
        Write-Host "Created main.tf at $tfFile"
    }
    else {
        Write-Host "main.tf already exists; not overwriting."
    }


    # If no provider.tf found, create one from Hyper-V config
    $ProviderFile = Join-Path -Path $infraRepoPath -ChildPath "providers.tf"
    if (-not (Test-Path $ProviderFile)) {
        Write-Host "No providers.tf found; creating providers.tf using Hyper-V configuration..."
        $tfContent = @"

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
        Set-Content -Path $ProviderFile -Value $tfContent
        Write-Host "Created providers.tf at $ProviderFile"
    }
    else {
        Write-Host "providers.tf already exists; not overwriting."
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
2. You may need to modify variables.tf to match your Hyper-V configuration.
 - Set host, user, password, etc. to match your Hyper-V settings.
3. Run 'tofu plan' to preview changes.
4. Run 'tofu apply' to provision resources.
"@

# Optionally place you in $infraRepoPath at the end
Set-Location $infraRepoPath
exit 0

}