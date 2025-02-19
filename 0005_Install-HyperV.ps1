Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

Write-Host "Installing Hyper-V..."

# In your config, you might have "EnableManagementTools": true/false
$enableMgtTools = $Config.HyperV.EnableManagementTools -eq $true

$featureName = "Hyper-V"
$additionalArgs = if ($enableMgtTools) { "-IncludeManagementTools" } else { "" }

$cmd = "Install-WindowsFeature -Name $featureName $additionalArgs -Restart:$false -ErrorAction Stop"
Write-Host $cmd
Invoke-Expression $cmd

Write-Host "Hyper-V installation complete. A restart is typically required to finalize installation."
# Optionally:
# Restart-Computer -Force
