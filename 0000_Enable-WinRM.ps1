Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

# Check if WinRM is already configured
$winrmStatus = Get-Service -Name WinRM -ErrorAction SilentlyContinue

if ($winrmStatus -and $winrmStatus.Status -eq 'Running') {
    Write-Host "WinRM is already enabled and running."
} else {
    Write-Host "Enabling WinRM..."
    
    # WinRM QuickConfig
    Enable-PSRemoting -Force
    
    # Optionally configure additional authentication methods, etc.:
    # e.g.: Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
    
    Write-Host "WinRM has been enabled."
}

