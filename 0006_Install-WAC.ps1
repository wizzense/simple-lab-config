Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

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
    } else {
        Write-Host "CA role is installed but no CA is configured. Proceeding with installation."
    }
} else {
    Write-Host "Installing Certificate Authority role..."
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
}

# ---- WAC Installation & Certificate Assignment ----

Write-Host "Checking for existing Windows Admin Center installation..."

$wacInstalled = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -match "Windows Admin Center" }
if ($wacInstalled) {
    Write-Host "Windows Admin Center is already installed. Skipping installation."
    return
}

Write-Host "Installing Windows Admin Center..."

# Because Windows Admin Center is updated frequently, we point to https://aka.ms/wacdownload
$WacConfig = $Config.WAC
if ($null -eq $WacConfig) {
    Write-Host "No WAC configuration found. Skipping installation."
    return
}

$installPort  = $WacConfig.InstallPort
$certFriendly = $WacConfig.FriendlyName
$certSubject  = $WacConfig.CertificateSubject -replace '\*', 'wildcard'

# 1. Generate or retrieve a valid certificate from the CA for WAC

Write-Host "Checking for an existing certificate with Friendly Name '$certFriendly'..."

$cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq $certFriendly } | Select-Object -First 1

if (-not $cert) {
    Write-Host "No existing certificate found. Requesting a new certificate from CA..."

    $certRequest = @"
[NewRequest]
Subject="CN=$certSubject"
Exportable=TRUE
KeyLength=2048
KeySpec=1
HashAlgorithm=SHA256
RequestType=PKCS10
MachineKeySet=TRUE
"@

    $reqFile = "$env:TEMP\WACCert.req"
    $certFile = "$env:TEMP\WACCert.cer"
    
    $certRequest | Out-File -Encoding ascii -FilePath $reqFile

    certreq -new $reqFile $certFile
    certreq -submit -config "$CAName" $certFile

    Write-Host "Importing issued certificate..."
    $importedCert = Import-Certificate -FilePath $certFile -CertStoreLocation Cert:\LocalMachine\My
    $certThumbprint = $importedCert.Thumbprint
} else {
    Write-Host "Using existing certificate."
    $certThumbprint = $cert.Thumbprint
}

# 2. Download the Windows Admin Center MSI
$downloadUrl = "https://aka.ms/wacdownload"
$installerPath = "$env:TEMP\WindowsAdminCenter.msi"

Write-Host "Downloading WAC from $downloadUrl"
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

# 3. Install WAC with the generated certificate
Write-Host "Installing WAC silently on port $installPort with certificate thumbprint $certThumbprint"
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /qn /L*v `"$env:TEMP\WacInstall.log`" SME_PORT=$installPort SME_THUMBPRINT=$certThumbprint ACCEPT_EULA=1"

Write-Host "Windows Admin Center installation complete with certificate applied."
