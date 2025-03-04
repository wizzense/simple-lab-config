Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

# Retrieve configuration for WAC from the config object
$WacConfig = $Config.WAC
if ($null -eq $WacConfig) {
    Write-Host "No WAC configuration found. Skipping installation."
    return
}

$installPort = $WacConfig.InstallPort

# Check registry uninstall keys for Windows Admin Center installation
$wacInstalled = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue | 
    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } | 
    Where-Object { $_.DisplayName -like "*Windows Admin Center*" }

if (-not $wacInstalled) {
    $wacInstalled = Get-ChildItem "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue | 
        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } | 
        Where-Object { $_.DisplayName -like "*Windows Admin Center*" }
}

if ($wacInstalled) {
    Write-Host "Windows Admin Center is already installed. Skipping installation."
    return
}

# Optionally, check if the desired installation port is already in use.
$portInUse = Get-NetTCPConnection -LocalPort $installPort -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Host "Port $installPort is already in use. Assuming Windows Admin Center is running. Skipping installation."
    return
}

Write-Host "Installing Windows Admin Center..."

# Download the Windows Admin Center MSI
$downloadUrl = "https://aka.ms/wacdownload"
$installerPath = "$env:TEMP\WindowsAdminCenter.msi"

Write-Host "Downloading WAC from $downloadUrl"
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

Write-Host "Installing WAC silently on port $installPort"
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /qn /L*v `"$env:TEMP\WacInstall.log`" SME_PORT=$installPort ACCEPT_EULA=1"

Write-Host "WAC installation complete."
