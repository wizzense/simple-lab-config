param(

    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
    )

& .\OpenTofuInstaller.ps1 -installMethod standalone -skipVerify
