param(

    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
    )

if ($Config.InstallOpenTofu -eq $true) {
    
    $Cosign = Join-Path $Config.CosignPath "cosign-windows-amd64.exe"
    & .\OpenTofuInstaller.ps1 -installMethod standalone -cosignPath $Cosign
}