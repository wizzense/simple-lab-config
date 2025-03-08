Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($Config.InstallCA -eq $true) {
Write-Host "Checking for existing Certificate Authority (Standalone Root CA)..."

# Only proceed if you actually want to install a CA.
if ($null -eq $Config.CertificateAuthority) {
    Write-Host "No CA config found. Skipping CA installation."
    return
}

$CAName        = $Config.CertificateAuthority.CommonName
$ValidityYears = $Config.CertificateAuthority.ValidityYears

if (-not $CAName) {
    Write-Host "Missing CAName in config. Skipping CA installation."
    return
}

# Check if the CA role is already installed
$role = Get-WindowsFeature -Name Adcs-Cert-Authority
if ($role.Installed) {
    Write-Host "Certificate Authority role is already installed. Checking CA configuration..."
    
    # Check if a CA is already configured
    $existingCA = Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' -ErrorAction SilentlyContinue
    if ($existingCA) {
        Write-Host "A Certificate Authority is already configured. Skipping installation."
        return
    }

    Write-Host "CA role is installed but no CA is configured. Proceeding with installation."
} else {
    Write-Host "Installing Certificate Authority role..."
    Install-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools -ErrorAction Stop
}

# If the script reaches this point, it means no existing CA is detected, and installation should proceed.
Write-Host "Configuring CA: $CAName with $($ValidityYears) year validity..."

Install-AdcsCertificationAuthority `
    -CAType StandaloneRootCA `
    -CACommonName $CAName `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -ValidityPeriod Years `
    -ValidityPeriodUnits $ValidityYears `
    -Force

Write-Host "Standalone Root CA '$CAName' installation complete."

}