Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

Write-Host "Enabling WinRM..."

# WinRM QuickConfig
# For Server Core, we want remote management to be straightforward:
Enable-PSRemoting -Force

# Optionally configure additional authentication methods, etc.:
# e.g.: Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true

Write-Host "WinRM has been enabled."
