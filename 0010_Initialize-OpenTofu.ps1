<#
.SYNOPSIS
  Initialize OpenTofu using Hyper-V settings from config.json.
.DESCRIPTION
  - Reads the Hyper-V values from the passed-in config.
  - For any missing or empty Hyper-V property, prompts the user for input.
  - Writes any prompted values back to config.json.
  - Generates a main.tf file using these settings.
  - Checks that the tofu command is available, and if not, adds the known installation folder to PATH.
  - Runs 'tofu init' to initialize OpenTofu in the specified local folder.
#>

param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Config
)

# Determine the path to the config file (as specified in config.json)
if ($Config.ConfigFile) {
    $configFilePath = (Resolve-Path $Config.ConfigFile).ProviderPath
} else {
    Write-Warning "ConfigFile path not specified in config. Changes will not be saved to config.json."
    $configFilePath = $null
}

Write-Host "---- Hyper-V Configuration Check ----"

# Ensure $Config.HyperV exists
if (-not $Config.HyperV) {
    $Config | Add-Member -MemberType NoteProperty -Name HyperV -Value ([PSCustomObject]@{})
}

# List of keys to check
$keys = @(
    "User",
    "Password",
    "Host",
    "Port",
    "Https",
    "Insecure",
    "UseNtlm",
    "TlsServerName",
    "CacertPath",
    "CertPath",
    "KeyPath",
    "ScriptPath",
    "Timeout"
)

# For each key, if the value is missing or empty, prompt for input
foreach ($key in $keys) {
    if (-not $Config.HyperV.PSObject.Properties[$key] -or [string]::IsNullOrWhiteSpace($Config.HyperV[$key].ToString())) {
        $inputValue = Read-Host "Enter value for HyperV.${key}:"
        switch ($key) {
            "Port" { $inputValue = [int]$inputValue }
            "Https" { $inputValue = ($inputValue -eq "true") }
            "Insecure" { $inputValue = ($inputValue -eq "true") }
            "UseNtlm" { $inputValue = ($inputValue -eq "true") }
        }
        $Config.HyperV | Add-Member -MemberType NoteProperty -Name $key -Value $inputValue -Force
    }
}


Write-Host "Final Hyper-V configuration:"
$Config.HyperV | Format-List

# Update config.json with any prompted values if a config file path is known
if ($configFilePath) {
    try {
        $Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFilePath -Encoding UTF8
        Write-Host "Configuration updated in $configFilePath"
    } catch {
        Write-Warning "Could not update config file: $_"
    }
}

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
    $defaultTofuExe = "C:\Users\Administrator\AppData\Local\Programs\OpenTofu\tofu.exe"
    if (Test-Path $defaultTofuExe) {
        Write-Host "Tofu command not found in PATH. Adding its folder to the session PATH..."
        $tofuFolder = Split-Path -Path $defaultTofuExe
        $env:PATH = "$env:PATH;$tofuFolder"
        # Re-check for tofu command
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
