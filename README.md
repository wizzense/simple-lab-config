# opentofu-lab-automation

  DEMO Kicker script for a fresh Windows Server Core setup

  1) Downloads and loads config-demo.json from the same folder by default (override with -ConfigFile).
  2) Checks if command-line Git is installed and in PATH. (requirement)
     - Prompts to install a minimal version if missing.
     - Updates PATH if installed but not found in PATH.
  3) Checks if GitHub CLI is installed and in PATH. (requirement)
     - Prompts to installs GitHub CLI if missing.
     - Updates PATH if installed but not found in PATH.
     - Prompts for authentication if not already authenticated.
  4) Clones this repository from config.json -> RepoUrl to config.json -> LocalPath (or a default path).
  5) Invokes runner.ps1 from this repo. Runner can be ran with optional parameters to automatically run, but it will prompt you to manually select which scripts to run by default.

```
powershell.exe -NoProfile -ExecutionPolicy Byp ass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/opentofu-lab-automation/refs/heads/main/kicker-git-demo.ps1' -OutFile '.\kicker-git-demo.ps1'; .\kicker-git-demo.ps1"
```
It will prompt print the current config and prompt you to customize it interactively. 

Example opentofu-infra repo: https://github.com/wizzense/tofu-base-lab.git

To get opentofu setup, really you only need to specify these when runner.ps1 is called: 0006,0007,0008,0009,0010

The runner script can run the following: 

0000_Cleanup-Files.ps1 - Removed lab-infra opentofu infrastructure repo

0001_Reset-Git.ps1 - resets lab-infra opentofu infrastructure repo in case you modify any files and just want to re-pull the files/ reset

0006_Install-ValidationTools.ps1 - downloads the  cosign exe to C:\temo\cosign

0007_Install-Go.ps1 - downloads and installs Go

0008_Install-OpenTofu.ps1 - Downloads and installs opentofu standalone (verified with cosign)

0009_Initialize-OpenTofu.ps1 - setups up opentofu and the lab-infra repo in C:\temp\base-infra

0010_Prepare-HyperVHost.ps1 - runs a lot of configuration to prep a hyper-v host to be used as a provider 

- Enables hyper-v if not enabled
  
- enables WinRM if not enabled
  
  - WinRS MaxMemoryPerShellMB to 1024
    
  - WinRM MaxTimeoutms to 1800000
    
  - TrustedHosts to '*'
    
  - Negotiate to True
    
- creates a self-signed RootCA Cert (prompts for password)
  
- creates self-signed host certificate (prompts for password)
  
- Configured WinRM HTTPs Listener
  
- Allows HTTP 5986 through firewall
  
- Creates a Go workspace in C:\GoWorkspace
  
  - Builds the hyperv-provider for opentofu from tailiesins git
    
  - Copies the provider to the lab-infra
 
- Note, certificate validation for the hyperv provider is currently disabled by default, I am still working out to get it to use the certificates. I think they have to be converted to .pem first.

Completely optional stuff I usee for other things:
-a----          3/7/2025   7:08 AM            616 0100_Enable-WinRM.ps1
-a----          3/7/2025   7:08 AM            725 0101_Enable-RemoteDesktop.ps1
-a----          3/7/2025   7:08 AM            613 0102_Configure-Firewall.ps1
-a----          3/7/2025   7:08 AM           1203 0103_Change-ComputerName.ps1
-a----          3/7/2025   7:08 AM           1895 0104_Install-CA.ps1
-a----          3/7/2025   7:08 AM           1141 0105_Install-HyperV.ps1
-a----          3/7/2025   7:08 AM           2568 0106_Install-WAC.ps1
-a----          3/7/2025   7:08 AM            272 0111_Disable-TCPIP6.ps1
-a----          3/7/2025   7:08 AM            705 0112_Enable-PXE.ps1
-a----          3/7/2025   7:08 AM            351 0113_Config-DNS.ps1
-a----          3/7/2025   7:08 AM            259 0114_Config-TrustedHosts.ps1

To run ALL scripts, type 'all'.
To run one or more specific scripts, provide comma separated 4-digit prefixes (e.g. 0001,0003).
Or type 'exit' to quit this script.

Make sure to modify the 'main.tf' so it uses your admin credentials and hostname/IP of the host machine if you don't have a customized config.json or choose not to customize.

provider "hyperv" {
  user            = "ad\\administrator"
  password        = ""
  host            = "192.168.1.121"
  port            = 5986
  https           = true
  insecure        = true  # This skips SSL validation
  use_ntlm        = true  # Use NTLM as it's enabled on the WinRM service
  tls_server_name = ""
  cacert_path     = ""    # Leave empty if skipping SSL validation
  cert_path       = ""    # Leave empty if skipping SSL validation
  key_path        = ""    # Leave empty if skipping SSL validation
  script_path     = "C:/Temp/terraform_%RAND%.cmd"
  timeout         = "30s"
}


variable "hyperv_host_name" {
  type    = string
  default = "192.168.1.121"
}

variable "hyperv_user" {
  type    = string
  default = "ad\\administrator"
}

variable "hyperv_password" {
  type    = string
  default = ""
}

You will also have to modify:


hyperv_vhd: Create multiple VHD objects (one per VM) with distinct paths

resource "hyperv_vhd" "control_node_vhd" {
  count = var.number_of_vms

  depends_on = [hyperv_network_switch.Lan]

  Unique path for each VHD (e.g. ...-0.vhdx, ...-1.vhdx, etc.)
  path = "B:\\hyper-v\\PrimaryControlNode\\PrimaryControlNode-Server2025-${count.index}.vhdx"
  size = 60737421312
}

And:

  dvd_drives {
    controller_number   = "0"
    controller_location = "1"
    path                = "B:\\share\\isos\\2_auto_unattend_en-us_windows_server_2025_updated_feb_2025_x64_dvd_3733c10e.iso"
  }
