Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

# Check current Remote Desktop status
$currentStatus = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections"

if ($Config.AllowRemoteDesktop -eq $true) {
    if ($currentStatus.fDenyTSConnections -eq 0) {
        Write-Host "Remote Desktop is already enabled."
    }
    else {
        Write-Host "Enabling Remote Desktop..."
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                         -Name "fDenyTSConnections" `
                         -Value 0
    }
}
else {
    Write-Host "Remote Desktop is NOT enabled by config."
}
