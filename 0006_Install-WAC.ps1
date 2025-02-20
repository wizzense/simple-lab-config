Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

# Example usage assumptions for $Config:
# $Config.CertificateAuthority.CommonName = "MyCA.domain.local\MyCAName"
# $Config.SCOMCert.Subject = "server01.domain.local"
# $Config.SCOMCert.Template = "OperationsManager"   # If you have an Enterprise CA template
# $Config.SCOMCert.FriendlyName = "SCOM Certificate"

Write-Host "Starting SCOM certificate request..."

# 1. Pull from config (adjust as needed)
$CAName        = $Config.CertificateAuthority.CommonName
$subject       = $Config.SCOMCert.Subject
$template      = $Config.SCOMCert.Template
$friendlyName  = $Config.SCOMCert.FriendlyName
if (-not $friendlyName) { $friendlyName = "SCOM Certificate" }

# 2. Create the .inf contents
#    NOTE: KeyExportable can be TRUE or FALSE. For SCOM, typically "FALSE" is recommended
#    in production unless you need to move the private key to another machine. 
#    The doc example uses KeyExportable=FALSE if the cert is generated on the final machine.
#    The doc also notes for SCOM:
#      - KeyUsage = 0xf0 (Digital Signature, Key Encipherment)
#      - EnhancedKeyUsageExtension: 1.3.6.1.5.5.7.3.1 & 1.3.6.1.5.5.7.3.2
#
#    If you have an Enterprise CA with a named certificate template, you can add:
#    [RequestAttributes]
#    CertificateTemplate="OperationsManager"
#    to request that template automatically.

$infFile = "$env:TEMP\SCOMCert.inf"
$reqFile = "$env:TEMP\SCOMCert.req"
$cerFile = "$env:TEMP\SCOMCert.cer"

$infContent = @"
[Version]
Signature="\$Windows NT\$"

[NewRequest]
Subject="CN=$subject"
KeyExportable=FALSE
HashAlgorithm=SHA256
KeyLength=2048
KeySpec=1 ; AT_KEYEXCHANGE
KeyUsage=0xf0 ; Digital Signature, Key Encipherment
MachineKeySet=TRUE
ProviderName="Microsoft RSA SChannel Cryptographic Provider"
ProviderType=12
KeyAlgorithm="RSA"

[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.1 ; Server Authentication
OID=1.3.6.1.5.5.7.3.2 ; Client Authentication
"@

# If you have an Enterprise CA and want to specify a SCOM-friendly template:
if ($template) {
$infContent += @"

[RequestAttributes]
CertificateTemplate="$template"
"@
}

$infContent | Out-File -FilePath $infFile -Encoding ascii
Write-Host "INF file created at: $infFile"

# 3. Generate the .req file
Write-Host "Generating certificate request (.req)..."
certreq -new $infFile $reqFile

if (-not (Test-Path $reqFile)) {
    Write-Host "ERROR: The req file wasn't created. Exiting."
    return
}

Write-Host "Submitting request to CA: $CAName"
# If $CAName is nonempty, try using -config. 
# If your environment doesn't have a known config or you have multiple CAs,
# you can omit -config and let the user choose from the GUI.
if ([string]::IsNullOrEmpty($CAName)) {
    # This triggers GUI selection:
    certreq -submit $reqFile $cerFile
}
else {
    certreq -submit -config "$CAName" $reqFile $cerFile
}

# If the CA is set to "Manual Approval," the request might come back as "Taken Under Submission."
# If the CA auto-issues, the .cer should appear here. Let's see if it exists:
if (-not (Test-Path $cerFile)) {
    Write-Host "Certificate file $cerFile not found. Possibly the request is pending approval."
    Write-Host "Once approved, retrieve the certificate (or run 'certreq -retrieve <ReqID> $cerFile')"
    return
}

# 4. Import or accept the .cer
Write-Host "Attempting to import the certificate..."
try {
    # 'certreq -accept' will bind it properly to the private key if it was auto-issued.
    # Alternatively, we can do:
    # Import-Certificate -FilePath $cerFile -CertStoreLocation Cert:\LocalMachine\My
    certreq -accept $cerFile

    # After acceptance, find its thumbprint:
    $importedCert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
        $_.Subject -eq "CN=$subject"
    } | Sort-Object NotBefore -Descending | Select-Object -First 1

    if ($importedCert) {
        # Update FriendlyName in the local certificate store
        $storePath = "Cert:\LocalMachine\My\$($importedCert.Thumbprint)"
        (Get-Item $storePath).FriendlyName = $friendlyName

        Write-Host "Certificate imported successfully:"
        Write-Host "  Subject: $($importedCert.Subject)"
        Write-Host "  Thumbprint: $($importedCert.Thumbprint)"
        Write-Host "  FriendlyName set to: $friendlyName"
    }
    else {
        Write-Host "ERROR: Certificate accepted but not found in the local store by subject=CN=$subject."
    }
}
catch {
    Write-Host "ERROR: Couldn't accept the certificate automatically. Details: $($_.Exception.Message)"
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
