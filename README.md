# opentofu-lab-automation

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/simple-lab-config/refs/heads/main/config.json' -OutFile '.\config.json'; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/simple-lab-config/refs/heads/main/kicker-git.ps1' -OutFile '.\kicker-git.ps1'; .\kicker-git.ps1"

Example opentofu-infra repo: https://github.com/wizzense/tofu-base-lab.git

The first time you run this it will download and install Git and Github CLI for you so that it can go ahead and clone the repos needed for the rest of the configuration. It will try to auth to github and likely fail.
I recommend you customize config.json.

To get opentofu setup, really you only need run: 0005,0007,0008,0009,0010

0000 - 0000_Enable-WinRM.ps1
0001 - 0001_Enable-RemoteDesktop.ps1
0002 - 0002_Configure-Firewall.ps1
0003 - 0003_Change-ComputerName.ps1
0005 - 0005_Install-HyperV.ps1
0006 - 0006_Install-WAC.ps1
0007 - 0007_Install-Go.ps1
0008 - 0008_Install-OpenTofu.ps1
0009 - 0009_Initialize-OpenTofu.ps1
0010 - 0010_Prepare-HyperVHost.ps1

To run ALL scripts, type 'all'.
To run one or more specific scripts, provide comma separated 4-digit prefixes (e.g. 0001,0003).
Or type 'exit' to quit this script.

Make sure to modify the 'main.tf' so it uses your admin credentials and hostname/IP of the host machine.

provider "hyperv" {
  user            = "ad\\administrator"
  password        = "Tanium1"
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
