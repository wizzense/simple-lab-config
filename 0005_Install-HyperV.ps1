Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

Write-Host "Installing Hyper-V..."

$enableMgtTools = $Config.HyperV.EnableManagementTools -eq $true
$restart = $false  # Set to $true if you want an automatic restart

if ($restart) {
    Install-WindowsFeature -Name "Hyper-V" -IncludeManagementTools:$enableMgtTools -Restart -ErrorAction Stop
} else {
    Install-WindowsFeature -Name "Hyper-V" -IncludeManagementTools:$enableMgtTools -ErrorAction Stop
}

Write-Host "Hyper-V installation complete. A restart is typically required to finalize installation."
