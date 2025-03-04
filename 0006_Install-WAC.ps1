Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

# Check if Windows Admin Center is already installed or running
$wacService = Get-Service -DisplayName "Windows Admin Center" -ErrorAction SilentlyContinue
if ($wacService) {
    Write-Host "Windows Admin Center is already installed."
    if ($wacService.Status -eq "Running") {
        Write-Host "Windows Admin Center service is running. Skipping installation."
    } else {
        Write-Host "Windows Admin Center is installed but not running. Consider starting the service."
    }
    return
}

Write-Host "Installing Windows Admin Center..."

# Retrieve configuration for WAC from the config object
$WacConfig = $Config.WAC
if ($null -eq $WacConfig) {
    Write-Host "No WAC configuration found. Skipping installation."
    return
}

$installPort = $WacConfig.InstallPort

# Download the Windows Admin Center MSI
$downloadUrl = "https://aka.ms/wacdownload"
$installerPath = "$env:TEMP\WindowsAdminCenter.msi"

Write-Host "Downloading WAC from $downloadUrl"
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

Write-Host "Installing WAC silently on port $installPort"
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /qn /L*v `"$env:TEMP\WacInstall.log`" SME_PORT=$installPort ACCEPT_EULA=1"

Write-Host "WAC installation complete."
