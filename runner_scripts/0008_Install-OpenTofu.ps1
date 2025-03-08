param(

    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
    )

if ($Config.InstallOpenTofu -eq $true) {
    
    $Cosign = Join-Path $Config.CosignPath "cosign-windows-amd64.exe"
    & .\runner_scripts\OpenTofuInstaller.ps1 -installMethod standalone -cosignPath $Cosign
}