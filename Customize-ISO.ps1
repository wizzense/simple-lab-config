<#

# Define local paths for the installer files.
$adkInstaller    = Join-Path $PSScriptRoot "adksetup.exe"
$peAddonInstaller = Join-Path $PSScriptRoot "adkwinpesetup.exe"

# Install Windows ADK silently.
Write-Output "Installing Windows ADK for Server 2025..."
try {
    Start-Process -FilePath $adkInstaller -ArgumentList "/quiet", "/norestart", "/features optionid.deploymenttools optionid.userstatemigrationtool" -Wait -ErrorAction Stop
    Write-Output "Windows ADK installation complete."
}
catch {
    Write-Error "Installation of Windows ADK failed: $_"
    exit 1
}

# Install Windows PE Add-on silently.
Write-Output "Installing Windows PE Add-on for Windows ADK..."
try {
    Start-Process -FilePath $peAddonInstaller -ArgumentList "/quiet", "/norestart" -Wait -ErrorAction Stop
    Write-Output "Windows PE Add-on installation complete."
}
catch {
    Write-Error "Installation of Windows PE Add-on failed: $_"
    exit 1
}


Mount-DiskImage -ImagePath "E:\2_auto_unattend_en-us_windows_server_2025_updated_feb_2025_x64_dvd_3733c10e.iso"
robocopy H:\ E:\CustomISO\ /E
mkdir E:\Mount
dism /mount-image /ImageFile:E:\CustomISO\sources\install.wim /Index:3 /MountDir:E:\Mount
copy-item "C:\Users\alexa\OneDrive\Documents\0. wizzense\opentofu-lab-automation\bootstrap.ps1" E:\mount\Windows\bootstrap.ps1
Copy-Item $UnattendXML -Destination E:\Mount\Windows\autounattend.xml" -Force
dism /Unmount-Image /MountDir:E:\Mount /Commit
Set-Location -path "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
.\oscdimg.exe -m -o -u2 -udfver102 -bootdata:2#p0,e,bE:\CustomISO\boot\etfsboot.com#pEF,e,bE:\CustomISO\efi\microsoft\boot\efisys.bin E:\CustomISO E:\CustomWinISO.iso
Dismount-DiskImage -ImagePath "E:\2_auto_unattend_en-us_windows_server_2025_updated_feb_2025_x64_dvd_3733c10e.iso"
#>

# Define paths
$ISOPath = "E:\2_auto_unattend_en-us_windows_server_2025_updated_feb_2025_x64_dvd_3733c10e.iso"   # Path to original Windows ISO
$ExtractPath = "E:\CustomISO"            # Extracted ISO location
$MountPath = "E:\Mount"                  # WIM mount directory
$WIMFile = "$ExtractPath\sources\install.wim"  # WIM file inside extracted ISO
$SetupScript = "E:\bootstrap.ps1"    # Your PowerShell setup script
$UnattendXML = "E:\Path\to\autounattend.xml"  # Your unattended XML file
$OutputISO = "E:\CustomWinISO.iso"       # Final customized ISO output path
$OscdimgExe = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

Remove-Item -Recurse -Force $MountPath

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit
}

# Step 1: Mount the Windows ISO
Write-Host "Mounting Windows ISO..." -ForegroundColor Yellow
$ISO = Mount-DiskImage -ImagePath $ISOPath -PassThru
$DriveLetter = ($ISO | Get-Volume).DriveLetter + ":"

# Step 2: Extract ISO contents
Write-Host "Extracting ISO contents to $ExtractPath..." -ForegroundColor Yellow
if (-Not (Test-Path $ExtractPath)) { New-Item -Path $ExtractPath -ItemType Directory | Out-Null }
robocopy "$DriveLetter\" $ExtractPath /E /NFL /NDL /NJH /NJS /NC /NS

# Step 3: Dismount the ISO
Write-Host "Dismounting ISO..." -ForegroundColor Yellow
Dismount-DiskImage -ImagePath $ISOPath

# Step 4: Mount the Install.wim Image
Write-Host "Mounting install.wim..." -ForegroundColor Yellow
if (-Not (Test-Path $MountPath)) { New-Item -Path $MountPath -ItemType Directory | Out-Null }
dism /Mount-Image /ImageFile:$WIMFile /Index:3 /MountDir:$MountPath

# Step 5: Copy bootstrap.ps1 into Windows
Write-Host "Copying setup.ps1 into Windows..." -ForegroundColor Green
Copy-Item $SetupScript -Destination "$MountPath\Windows\bootstrap.ps1" -Force

# Step 6: Commit Changes & Unmount WIM
Write-Host "Committing changes and unmounting install.wim..." -ForegroundColor Yellow
dism /Unmount-Image /MountDir:$MountPath /Commit

# Step 7: Add autounattend.xml to ISO root
Write-Host "Copying autounattend.xml to ISO root..." -ForegroundColor Green
Copy-Item $UnattendXML -Destination "$ExtractPath\autounattend.xml" -Force

# Step 8: Recreate Bootable ISO
Write-Host "Recreating bootable ISO..." -ForegroundColor Yellow
Start-Process Start-Process -FilePath $OscdimgExe -ArgumentList @(
    "-m",
    "-o",
    "-u2",
    "-udfver102",
    "-bootdata:2#p0,e,b`"$ExtractPath\boot\etfsboot.com`"#pEF,e,b`"$ExtractPath\efi\microsoft\boot\efisys.bin`"",
    "`"$ExtractPath`"",
    "`"$OutputISO`""
) -NoNewWindow -Wait

Write-Host "Custom ISO creation complete! New ISO saved as $OutputISO" -ForegroundColor Green
