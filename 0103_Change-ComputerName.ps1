Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($config.SetComputerName -eq $true) {

    try {
        $CurrentName = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Name
    } catch {
        Write-Host "Error retrieving current computer name: $_"
        exit 1
    }

    if ($null -ne $Config.ComputerName -and $Config.ComputerName -match "^\S+$") {
        if ($CurrentName -ne $Config.ComputerName) {
            Write-Host "Changing Computer Name from $CurrentName to $($Config.ComputerName)..."
            try {
                Rename-Computer -NewName $Config.ComputerName -Force -ErrorAction Stop
                Write-Host "Computer name changed successfully. A reboot is usually required."
                # Uncomment to reboot automatically
                # Restart-Computer -Force
            } catch {
                Write-Host "Failed to change computer name: $_"
            }
        } else {
            Write-Host "Computer name is already set to $($Config.ComputerName). Skipping rename."
        }
    } else {
        Write-Host "No valid ComputerName specified in config. Skipping rename."
    }
}