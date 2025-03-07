param(

    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
    )

if ($Config.InstallOpenTofu -eq $true) {
    & .\OpenTofuInstaller.ps1 -installMethod standalone -skipVerify
}