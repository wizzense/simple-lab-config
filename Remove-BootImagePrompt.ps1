Function Remove-BootImagePrompt {
    <#
    .SYNOPSIS
    Removes boot prompt from WinPE image. 
    .DESCRIPTION
    Removes boot prompt from WinPE image. 
    .PARAMETER SourceISO
    This is a mandatory parameter which specifies the path to the source ISO image.
    .PARAMETER NewISO
    This is a mandatory parameter which specifies the path to the ISO image to be created.
    .PARAMETER Architecture
    This is an optional parameter which specifies the boot image architecture.  The default value is 'amd64'.
    .EXAMPLE
    Remove-BootImagePrompt -SourceISO C:\WinPEx64.iso -NewISO C:\WinPEx64_no_prompt.iso
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1)][ValidateScript( { Test-Path $_ })][string]$SourceISO,
        [Parameter(Mandatory = $true, Position = 2)][ValidateScript( { Test-Path (Split-Path $_) })][string]$NewISO,
        [Parameter(Position = 3)][ValidateSet('x86', 'amd64')][string]$Architecture = 'amd64'
    )
    $AdkDir = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$Architecture\Oscdimg"
    $etfsboot = "$AdkDir\etfsboot.com"
    $efisys = "$AdkDir\efisys_noprompt.bin"
    $oscdimg = "$AdkDir\oscdimg.exe"

    # Mount the ISO
    $mount = Mount-DiskImage -Imagepath $SourceISO -Passthru

    # Get the drive letter assigned to the iso.
    $DriveLetter = ($mount | Get-Volume).driveletter
    $SourceISODrive = "$($DriveLetter):"
    
    # Recompile the files to an ISO
    $BootData='2#p0,e,b"{0}"#pEF,e,b"{1}"' -f "$etfsboot","$efisys" 
    $Process = Start-Process -FilePath "$oscdimg" -ArgumentList @("-bootdata:$BootData",'-u2','-udfver102',"$SourceISODrive\","`"$NewISO`"") -PassThru -Wait -NoNewWindow 
    if ($Process.ExitCode -ne 0) {
        Throw "Failed to generate ISO with exitcode: $($Process.ExitCode)"
        # Dismount the ISO
        Dismount-DiskImage -ImagePath "$SourceISO"
    }

    # Dismount the Source ISO
    Dismount-DiskImage -ImagePath "$SourceISO"
}

Remove-BootImagePrompt -SourceISO "E:\2_auto_unattend_en-us_windows_server_2025_updated_feb_2025_x64_dvd_3733c10e.iso" -NewISO E:\WinPEx64_no_prompt.iso