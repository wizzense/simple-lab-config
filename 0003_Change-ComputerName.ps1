Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($null -ne $Config.ComputerName -and $Config.ComputerName -ne "") {
    $CurrentName = (Get-CimInstance Win32_ComputerSystem).Name
    if ($CurrentName -ne $Config.ComputerName) {
        Write-Host "Changing Computer Name from $CurrentName to $($Config.ComputerName)..."
        Rename-Computer -NewName $Config.ComputerName -Force
        Write-Host "Computer name changed. A reboot is usually required."
        # Optionally reboot automatically:
        # Restart-Computer -Force
    } else {
        Write-Host "Computer name is already $($Config.ComputerName). Skipping rename."
    }
} else {
    Write-Host "No ComputerName specified in config. Skipping rename."
}