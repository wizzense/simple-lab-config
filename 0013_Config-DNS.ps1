Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($Config.SetDNSServers -eq $true) {
    
    $interfaceIndex = (Get-NetIPAddress -AddressFamily IPv4 | Select-Object -First 1 -ExpandProperty InterfaceIndex)
    Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses $config.$DNSServers
       
}