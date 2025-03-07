Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($Config.SetTrustedHosts -eq $true) {
    
    start-process cmd.exe -ArgumentList "/d /c winrm set winrm/config/client @{TrustedHosts=`"$Config.$TrustedHosts`"}"
       
}

