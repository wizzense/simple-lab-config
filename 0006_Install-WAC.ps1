Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

Write-Host "Installing Windows Admin Center..."

# Because Windows Admin Center is updated frequently, we point to https://aka.ms/wacdownload
# but we can configure the port and certificate from config.

$WacConfig = $Config.WAC
if ($null -eq $WacConfig) {
    Write-Host "No WAC configuration found. Skipping installation."
    return
}

$installPort     = $WacConfig.InstallPort
$certFriendly    = $WacConfig.FriendlyName

# 1. Download the Windows Admin Center MSI
$downloadUrl = "https://aka.ms/wacdownload"
$installerPath = "$env:TEMP\WindowsAdminCenter.msi"

Write-Host "Downloading WAC from $downloadUrl"
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

# 2. For a truly valid SSL certificate, you might need to create or reference a certificate
#    from the CA installed earlier. That can be done with separate scripts, or integrated here.
#    Let's assume you're just installing WAC with a self-signed or no certificate for now.
#    If you do have a cert, you’d retrieve the thumbprint, e.g.:
#    $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where { $_.FriendlyName -eq $certFriendly } | Select-Object -First 1
#    $thumbprint = $cert.Thumbprint

Write-Host "Installing WAC silently on port $installPort"
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /qn /L*v `"$env:TEMP\WacInstall.log`" SME_PORT=$installPort ACCEPT_EULA=1"

Write-Host "WAC installation complete."
