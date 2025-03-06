# simple-lab-config

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/simple-lab-config/refs/heads/main/config.json' -OutFile '.\config.json'; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/simple-lab-config/refs/heads/main/kicker.ps1' -OutFile '.\kicker.ps1'; .\kicker.ps1"

Really you only need run: 0005,0007,0008,0009,0010

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