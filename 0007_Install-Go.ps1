Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)
if ($Config.InstallGo -eq $true) {
    $GoConfig = $Config.Go
    if ($null -eq $GoConfig) {
        Write-Host "No Go configuration found. Skipping installation."
        return
    }

    if ($GoConfig.InstallerUrl) {
        $installerUrl = $GoConfig.InstallerUrl
        if ($installerUrl -match "go([\d\.]+)\.windows-([a-z0-9]+)\.msi") {
            $goVersion = $matches[1]
            $goArch = $matches[2]
        } else {
            Write-Host "Unable to extract Go version and architecture from InstallerUrl."
            return
        }
    } elseif ($GoConfig.Version) {
        $goVersion = $GoConfig.Version
        $goArch = $GoConfig.Architecture
        if (-not $goArch) { $goArch = "amd64" }
    } else {
        Write-Host "No Go version or InstallerUrl specified. Skipping installation."
        return
    }

    # Check if Go is already installed by looking for the 'go' command
    if (Get-Command go -ErrorAction SilentlyContinue) {
        Write-Host "Go is already installed. Skipping installation."
        return
    }

    Write-Host "Installing Go version $goVersion for architecture $goArch..."
    $installerPath = "$env:TEMP\GoInstaller.msi"

    $ProgressPreference = 'SilentlyContinue'
    Write-Host "Downloading Go from $installerUrl"
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Installing Go silently..."
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /qn /L*v `"$env:TEMP\GoInstall.log`""

    Write-Host "Go installation complete."
}