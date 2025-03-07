Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($Config.DisableTCPIP6 -eq $true) {
    
    Get-NetAdapterBinding -ComponentID 'ms_tcpip6' | where-object enabled -eq $true | Disable-NetAdapterBinding -ComponentID 'ms_tcpip6'
       
}
