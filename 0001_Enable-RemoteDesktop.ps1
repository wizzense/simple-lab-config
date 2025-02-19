Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($Config.AllowRemoteDesktop -eq $true) {
    Write-Host "Enabling Remote Desktop..."
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                     -Name "fDenyTSConnections" `
                     -Value 0
}
else {
    Write-Host "Remote Desktop is NOT enabled by config."
}
