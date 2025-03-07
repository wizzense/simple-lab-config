Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($Config.ConfigPXE -eq $true) {

    New-NetFirewallRule -DisplayName prov-pxe-67 -Enabled True -Direction inbound -Protocol udp -LocalPort 67 -Action Allow -RemoteAddress any
    New-NetFirewallRule -DisplayName prov-pxe-69 -Enabled True -Direction inbound -Protocol udp -LocalPort 69 -Action Allow -RemoteAddress any
    New-NetFirewallRule -DisplayName prov-pxe-17519 -Enabled True -Direction inbound -Protocol tcp -LocalPort 17519 -Action Allow -RemoteAddress any
    New-NetFirewallRule -DisplayName prov-pxe-17530 -Enabled True -Direction inbound -Protocol tcp -LocalPort 17530 -Action Allow -RemoteAddress any

}