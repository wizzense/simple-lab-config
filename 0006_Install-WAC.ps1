Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

# ---- WAC Installation & Certificate Assignment ----

Write-Host "Checking for existing Windows Admin Center installation..."

$wacInstalled = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -match "Windows Admin Center" }
if ($wacInstalled) {
    Write-Host "Windows Admin Center is already installed. Skipping installation."
    return
}

Write-Host "Installing Windows Admin Center..."

# Check if WAC is configured in the provided config
$WacConfig = $Config.WAC
if ($null -eq $WacConfig) {
    Write-Host "No WAC configuration found. Skipping installation."
    return
}

# Validate that required properties exist
if (-not $WacConfig.PSObject.Properties["InstallPort"] -or -not $WacConfig.PSObject.Properties["FriendlyName"]) {
    Write-Host "Error: Missing required properties (InstallPort or FriendlyName) in WAC config. Exiting."
    return
}

$installPort  = $WacConfig.InstallPort
$certFriendly = $WacConfig.FriendlyName
$certSubject  = if ($WacConfig.PSObject.Properties["CertificateSubject"]) { 
    $WacConfig.CertificateSubject 
} else { 
    "WAC-Cert-$env:COMPUTERNAME"  # Default to a reasonable fallback
}

# Capture CA name from config
$CAName = $Config.CertificateAuthority.CommonName
Write-Host "Using CA name: $CAName"

# 1. Generate or retrieve a valid certificate from the CA for WAC
Write-Host "Checking for an existing certificate with Friendly Name '$certFriendly'..."
$cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq $certFriendly } | Select-Object -First 1

if (-not $cert) {
    Write-Host "No existing certificate found. Requesting a new certificate from CA..."

    # Prepare the .INF text for certreq
    $certRequest = @"
    [NewRequest]
    Subject="CN=$certSubject"
    Exportable=TRUE
    KeyLength=2048
    KeySpec=1
    HashAlgorithm=SHA256
    RequestType=PKCS10
    MachineKeySet=TRUE
    
    ; [RequestAttributes]
    ; CertificateTemplate=WebServer
    "@

    # Paths
    $infFile      = "$env:TEMP\WACCert.inf"
    $reqFile      = "$env:TEMP\WACCert.req"
    $certFile     = "$env:TEMP\WACCert.cer"

    # Create the INF
    $certRequest | Out-File -Encoding ascii -FilePath $infFile

    # 1a. Generate a certificate request (.req)
    certreq -new $infFile $reqFile

    # 1b. Submit the request to the CA (which returns the .cer file)
    certreq -submit -config "$CAName" $reqFile $certFile

    # 1c. Import the issued certificate
    Write-Host "Importing issued certificate..."
    $importedCert = Import-Certificate -FilePath $certFile -CertStoreLocation Cert:\LocalMachine\My

    # 1d. Update FriendlyName after import
    #     (FriendlyName doesn’t come from the .INF, so we set it manually)
    $certThumbprint = $importedCert.Thumbprint
    $storePath      = "Cert:\LocalMachine\My\$certThumbprint"
    (Get-Item $storePath).FriendlyName = $certFriendly

    # Retrieve the updated certificate object
    $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $certThumbprint }
} else {
    Write-Host "Using existing certificate."
}

# Make sure we have a valid certificate reference
if (-not $cert) {
    Write-Host "ERROR: The certificate was not found or could not be imported."
    return
}

# 2. Download the Windows Admin Center MSI
$downloadUrl = "https://aka.ms/wacdownload"
$installerPath = "$env:TEMP\WindowsAdminCenter.msi"

Write-Host "Downloading WAC from $downloadUrl"
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

# 3. Install WAC with the generated certificate
Write-Host "Installing WAC silently on port $installPort with certificate thumbprint $($cert.Thumbprint)"
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /qn /L*v `"$env:TEMP\WacInstall.log`" SME_PORT=$installPort SME_THUMBPRINT=$($cert.Thumbprint) ACCEPT_EULA=1"

Write-Host "Windows Admin Center installation complete with certificate applied."
