Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($Config.InstallWAC -eq $true) {
    # Retrieve configuration for WAC from the config object
    $WacConfig = $Config.WAC
    if ($null -eq $WacConfig) {
        Write-Host "No WAC configuration found. Skipping installation."
        return
    }

    $installPort = $WacConfig.InstallPort

    # Define a helper function to check a registry path for Windows Admin Center
    function Get-WacRegistryInstallation {
        param(
            [string]$RegistryPath
        )
        $items = Get-ChildItem $RegistryPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            $itemProps = Get-ItemProperty $item.PSPath -ErrorAction SilentlyContinue
            # Only check if the DisplayName property exists
            if ($itemProps.PSObject.Properties['DisplayName'] -and $itemProps.DisplayName -like "*Windows Admin Center*") {
                return $itemProps
            }
        }
        return $null
    }

    # Check both standard and Wow6432Node uninstall registry keys for WAC installation
    $wacInstalled = Get-WacRegistryInstallation -RegistryPath "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    if (-not $wacInstalled) {
        $wacInstalled = Get-WacRegistryInstallation -RegistryPath "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
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

    $ProgressPreference = 'SilentlyContinue'

    Write-Host "Downloading WAC from $downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Installing WAC silently on port $installPort"
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /qn /L*v `"$env:TEMP\WacInstall.log`" SME_PORT=$installPort ACCEPT_EULA=1"

    Write-Host "WAC installation complete."
}