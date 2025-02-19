Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

Write-Host "Installing Certificate Authority (Standalone Root CA)..."

# Only proceed if you actually want to install a CA.
# Because the user might not always want to do this on every server.
# We'll read a property from $Config to decide if we do it or skip.
if ($null -eq $Config.CertificateAuthority) {
    Write-Host "No CA config found. Skipping CA installation."
    return
}

$CAName          = $Config.CertificateAuthority.CommonName
$ValidityYears   = $Config.CertificateAuthority.ValidityYears

if (-not $CAName) {
    Write-Host "Missing CAName in config. Skipping CA installation."
    return
}

# Install CA Feature
Install-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools -ErrorAction Stop

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
