<#
.SYNOPSIS
  Kicker script for a fresh Windows Server Core setup with robust error handling.
#>

Param(
    [string]$ConfigFile = "$PSScriptRoot\config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'  # So any error throws an exception

if (!(Test-Path "C:\temp")) {
    New-Item -ItemType Directory -Force -Path C:\temp | Out-Null
}

Invoke-WebRequest -Uri https://github.com/wizzense/simple-lab-config/archive/refs/heads/main.zip -outfile C:\temp\simple-lab-config.zip -usebasicparsing
Expand-Archive C:\temp\simple-lab-config.zip
$configFile = "C:\temp\simple-lab-config\simple-lab-config-main\config.json"
& C:\temp\simple-lab-config\simple-lab-config-main\runner.ps1

Write-Host "`n=== Kicker script finished successfully! ==="
exit 0
