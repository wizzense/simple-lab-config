<#
.SYNOPSIS
  Initialize OpenTofu using Hyper-V settings from config.json.
.DESCRIPTION
  - Reads the Hyper-V values from the passed-in config.
  - Generates a main.tf file using these settings.
  - Checks that the tofu command is available, and if not, adds the known installation folder to PATH.
  - Runs 'tofu init' to initialize OpenTofu in the specified local folder.
#>

param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Config
)

Write-Host "---- Hyper-V Configuration Check ----"


Write-Host "Final Hyper-V configuration:"
$Config.HyperV | Format-List

# Determine the local infrastructure folder (defaults to "my-infra" if LocalPath is empty)
$localPath = if ([string]::IsNullOrWhiteSpace($Config.LocalPath)) { "my-infra" } else { $Config.LocalPath }
$repoPath = Join-Path -Path $PSScriptRoot -ChildPath $localPath

if (-not (Test-Path $repoPath)) {
    New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
    Write-Host "Created directory: $repoPath"
} else {
    Write-Host "Directory already exists: $repoPath"
}

# Create (or skip creating) main.tf using the Hyper-V settings from config.json
$tfFile = Join-Path -Path $repoPath -ChildPath "main.tf"
if (-not (Test-Path $tfFile)) {
    Write-Host "Creating main.tf using Hyper-V configuration..."
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
  https           = $($Config.HyperV.Https)
  insecure        = $($Config.HyperV.Insecure)
  use_ntlm        = $($Config.HyperV.UseNtlm)
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
} else {
    Write-Host "main.tf already exists; not overwriting."
}

# --------------------------------------------------------------------------------
# Check if tofu is in the PATH. If not, add the known installation path.
# --------------------------------------------------------------------------------
$tofuCmd = Get-Command tofu -ErrorAction SilentlyContinue
if (-not $tofuCmd) {
    $defaultTofuExe = Join-Path $env:USERPROFILE -ChildPath "AppData\Local\Programs\OpenTofu\tofu.exe"
    if (Test-Path $defaultTofuExe) {
        Write-Host "Tofu command not found in PATH. Adding its folder to the session PATH..."
        $tofuFolder = Split-Path -Path $defaultTofuExe
        $env:PATH = "$env:PATH;$tofuFolder"
        $tofuCmd = Get-Command tofu -ErrorAction SilentlyContinue
        if (-not $tofuCmd) {
            Write-Warning "Even after updating PATH, tofu command is not recognized."
        } else {
            Write-Host "Tofu command found: $($tofuCmd.Path)"
        }
    } else {
        Write-Error "Tofu executable not found at $defaultTofuExe. Please install OpenTofu or update your PATH."
        exit 1
    }
}

# --------------------------------------------------------------------------------
# Run tofu init in the repository folder
# --------------------------------------------------------------------------------
Write-Host "Initializing OpenTofu in $repoPath..."
Push-Location $repoPath
try {
    tofu init
} catch {
    Write-Error "Failed to run 'tofu init'. Ensure OpenTofu is installed and available in the PATH."
    Pop-Location
    exit 1
}
Pop-Location

Write-Host "OpenTofu initialized successfully."

Write-Host @"
NEXT STEPS:
1. Edit '$tfFile' as needed.
2. Run 'tofu plan' to preview changes.
3. Run 'tofu apply' to provision resources.
"@
exit 0
