Param(
    [Parameter(Mandatory=$true)]
    [PSCustomObject]$Config
)

if ($Config.PrepareHyperVHost -eq $true) {

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------
# 1) Environment Preparation
# ------------------------------

# Check if Hyper-V feature is enabled
$hvFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
if ($hvFeature.State -ne "Enabled") {
    Write-Host "Enabling Hyper-V feature..."
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
} else {
    Write-Host "Hyper-V is already enabled."
}

# Check if WinRM is enabled by testing the local WSMan endpoint
try {
    Test-WSMan -ComputerName localhost -ErrorAction Stop | Out-Null
    Write-Host "WinRM is already enabled."
}
catch {
    Write-Host "Enabling WinRM..."
    Enable-PSRemoting -SkipNetworkProfileCheck -Force
}

# Check and set WinRS MaxMemoryPerShellMB to 1024 if needed
$currentMaxMemory = (Get-WSManInstance -ResourceURI winrm/config/WinRS).MaxMemoryPerShellMB
if ($currentMaxMemory -ne 1024) {
    Write-Host "Setting WinRS MaxMemoryPerShellMB to 1024..."
    Set-WSManInstance -ResourceURI winrm/config/WinRS -ValueSet @{MaxMemoryPerShellMB = 1024}
}
else {
    Write-Host "WinRS MaxMemoryPerShellMB is already 1024."
}

# Check and set WinRM MaxTimeoutms to 1800000 if needed
$currentTimeout = (Get-WSManInstance -ResourceURI winrm/config).MaxTimeoutms
if ($currentTimeout -ne 1800000) {
    Write-Host "Setting WinRM MaxTimeoutms to 1800000..."
    Set-WSManInstance -ResourceURI winrm/config -ValueSet @{MaxTimeoutms = 1800000}
}
else {
    Write-Host "WinRM MaxTimeoutms is already 1800000."
}

# Check and set TrustedHosts to "*" for the WinRM client if needed
$currentTrustedHosts = (Get-WSManInstance -ResourceURI winrm/config/Client).TrustedHosts
if ($currentTrustedHosts -ne "*") {
    Write-Host "Setting TrustedHosts to '*'..."
    try {
        Set-WSManInstance -ResourceURI winrm/config/Client -ValueSet @{TrustedHosts = "*"}
    }
    catch {
        Write-Host "TrustedHosts is set by policy."
    }
}
else {
    Write-Host "TrustedHosts is already set to '*'."
}

# Check and set Negotiate to True in WinRM service auth if needed
$currentNegotiate = (Get-WSManInstance -ResourceURI winrm/config/Service/Auth).Negotiate
if (-not $currentNegotiate) {
    Write-Host "Setting Negotiate to True..."
    Set-WSManInstance -ResourceURI winrm/config/Service/Auth -ValueSet @{Negotiate = $true}
}
else {
    Write-Host "Negotiate is already set to True."
}

# ------------------------------
# 2) Configure WinRM HTTPS
# ------------------------------

$rootCaName = $config.CertificateAuthority.CommonName
$UserInput = Read-Host -Prompt "Enter the password for the Root CA certificate" -AsSecureString
$rootCaPassword = $UserInput
#$rootCaPassword   = ConvertTo-SecureString $UserInput -AsPlainText -Force
$rootCaCertificate = Get-ChildItem cert:\LocalMachine\Root | Where-Object {$_.Subject -eq "CN=$rootCaName"}

if ($rootCaCertificate) {
    # Cleanup if present
    Get-ChildItem cert:\LocalMachine\My | Where-Object {$_.subject -eq "CN=$rootCaName"} | Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item ".\$rootCaName.cer" -Force -ErrorAction SilentlyContinue
    Remove-Item ".\$rootCaName.pfx" -Force -ErrorAction SilentlyContinue

    $params = @{
        Type              = 'Custom'
        DnsName           = $rootCaName
        Subject           = "CN=$rootCaName"
        KeyExportPolicy   = 'Exportable'
        CertStoreLocation = 'Cert:\LocalMachine\My'
        KeyUsageProperty  = 'All'
        KeyUsage          = 'None'
        Provider          = 'Microsoft Strong Cryptographic Provider'
        KeySpec           = 'KeyExchange'
        KeyLength         = 4096
        HashAlgorithm     = 'SHA256'
        KeyAlgorithm      = 'RSA'
        NotAfter          = (Get-Date).AddYears(5)
    }

    Write-Host "Creating Root CA..."
    $rootCaCertificate = New-SelfSignedCertificate @params

    Export-Certificate -Cert $rootCaCertificate -FilePath ".\$rootCaName.cer" -Verbose
    Export-PfxCertificate -Cert $rootCaCertificate -FilePath ".\$rootCaName.pfx" -Password $rootCaPassword -Verbose

    # Re-import to Root store & My store
    Get-ChildItem cert:\LocalMachine\My | Where-Object {$_.subject -eq "CN=$rootCaName"} | Remove-Item -Force -ErrorAction SilentlyContinue
    Import-PfxCertificate -FilePath ".\$rootCaName.pfx" -CertStoreLocation Cert:\LocalMachine\Root -Password $rootCaPassword -Exportable -Verbose
    Import-PfxCertificate -FilePath ".\$rootCaName.pfx" -CertStoreLocation Cert:\LocalMachine\My -Password $rootCaPassword -Exportable -Verbose

    $rootCaCertificate = Get-ChildItem cert:\LocalMachine\My | Where-Object {$_.subject -eq "CN=$rootCaName"}
}

# Create Host Certificate
$hostName      = [System.Net.Dns]::GetHostName()
$UserInput = Read-Host -Prompt "Enter the password for the host." -AsSecureString
$hostPassword = $UserInput
#$hostPassword  = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$hostCertificate = Get-ChildItem cert:\LocalMachine\My | Where-Object {$_.Subject -eq "CN=$hostName"}

if ($hostCertificate) {
    # Cleanup if present
    Get-ChildItem cert:\LocalMachine\My | Where-Object {$_.subject -eq "CN=$hostName"} | Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item ".\$hostName.cer" -Force -ErrorAction SilentlyContinue
    Remove-Item ".\$hostName.pfx" -Force -ErrorAction SilentlyContinue

    $dnsNames = @($hostName, "localhost", "127.0.0.1") + [System.Net.Dns]::GetHostByName($env:ComputerName).AddressList.IPAddressToString
    $params = @{
        Type              = 'Custom'
        DnsName           = $dnsNames
        Subject           = "CN=$hostName"
        KeyExportPolicy   = 'Exportable'
        CertStoreLocation = 'Cert:\LocalMachine\My'
        KeyUsageProperty  = 'All'
        KeyUsage          = @('KeyEncipherment','DigitalSignature','NonRepudiation')
        TextExtension     = @("2.5.29.37={text}1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2")
        Signer            = $rootCaCertificate
        Provider          = 'Microsoft Strong Cryptographic Provider'
        KeySpec           = 'KeyExchange'
        KeyLength         = 2048
        HashAlgorithm     = 'SHA256'
        KeyAlgorithm      = 'RSA'
        NotAfter          = (Get-Date).AddYears(2)
    }

    Write-Host "Creating host certificate..."
    $hostCertificate = New-SelfSignedCertificate @params

    Export-Certificate -Cert $hostCertificate -FilePath ".\$hostName.cer" -Verbose
    Export-PfxCertificate -Cert $hostCertificate -FilePath ".\$hostName.pfx" -Password $hostPassword -Verbose

    Get-ChildItem cert:\LocalMachine\My | Where-Object {$_.Subject -eq "CN=$hostName"} | Remove-Item -Force -ErrorAction SilentlyContinue
    Import-PfxCertificate -FilePath ".\$hostName.pfx" -CertStoreLocation Cert:\LocalMachine\My -Password $hostPassword -Exportable -Verbose

    $hostCertificate = Get-ChildItem cert:\LocalMachine\My | Where-Object {$_.subject -eq "CN=$hostName"}
}

Write-Host "Configuring WinRM HTTPS listener..."
Get-ChildItem wsman:\localhost\Listener\ | Where-Object -Property Keys -eq 'Transport=HTTPS' | Remove-Item -Recurse -ErrorAction SilentlyContinue
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $($hostCertificate.Thumbprint) -Force -Verbose
Restart-Service WinRM -Verbose -Force

Write-Host "Allowing HTTPS (5986) through firewall..."
New-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -Name "WinRMHTTPSIn" -Profile Any -LocalPort 5986 -Protocol TCP -Verbose

# ------------------------------
# 3) Configure WinRM HTTP (optional)
# ------------------------------
<#
$PubNets = Get-NetConnectionProfile -NetworkCategory Public -ErrorAction SilentlyContinue
foreach ($PubNet in $PubNets) {
    Set-NetConnectionProfile -InterfaceIndex $PubNet.InterfaceIndex -NetworkCategory Private
}

Set-WSManInstance WinRM/Config/Service -ValueSet @{AllowUnencrypted = $true}

foreach ($PubNet in $PubNets) {
    Set-NetConnectionProfile -InterfaceIndex $PubNet.InterfaceIndex -NetworkCategory Public
}

Get-ChildItem wsman:\localhost\Listener\ | Where-Object -Property Keys -eq 'Transport=HTTP' | Remove-Item -Recurse -ErrorAction SilentlyContinue
New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address * -Force -Verbose
Restart-Service WinRM -Verbose -Force

Write-Host "Allowing HTTP (5985) through firewall..."
New-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Name "WinRMHTTPIn" -Profile Any -LocalPort 5985 -Protocol TCP -Verbose
#>

# ------------------------------
# 4) Build & Install Hyper-V Provider in InfraRepoPath
# ------------------------------

# Use Config to find the infra repo path, fallback if empty
$infraRepoPath = if ([string]::IsNullOrWhiteSpace($Config.InfraRepoPath)) {
    Join-Path $PSScriptRoot "my-infra"
} else {
    $Config.InfraRepoPath
}

Write-Host "InfraRepoPath for hyperv provider: $infraRepoPath"

Write-Host "Setting up Go environment..."
$goWorkspace = "C:\\GoWorkspace"
$env:GOPATH = $goWorkspace
[System.Environment]::SetEnvironmentVariable('GOPATH', $goWorkspace, 'User')

Write-Host "Ensuring taliesins provider dir structure..."
$taliesinsDir = Join-Path -Path $env:GOPATH -ChildPath "src\\github.com\\taliesins"
if (!(Test-Path $taliesinsDir)) {
    New-Item -ItemType Directory -Force -Path $taliesinsDir | Out-Null
}
Set-Location $taliesinsDir

# Define the provider directory/exe
$providerDir     = Join-Path $taliesinsDir "terraform-provider-hyperv"
$providerExePath = Join-Path $providerDir  "terraform-provider-hyperv.exe"

Write-Host "Checking if we need to clone or rebuild the hyperv provider..."
if (!(Test-Path $providerExePath)) {
    Write-Host "Provider exe not found; cloning from GitHub..."
    git clone https://github.com/taliesins/terraform-provider-hyperv.git
}
Set-Location $providerDir

Write-Host "Building hyperv provider with go..."
go build -o terraform-provider-hyperv.exe

# The version in your default main.tf is 1.2.1, so place it accordingly
$hypervProviderDir = Join-Path $infraRepoPath ".terraform\\providers\\registry.opentofu.org\\taliesins\\hyperv\\1.2.1"
if (!(Test-Path $hypervProviderDir)) {
    New-Item -ItemType Directory -Force -Path $hypervProviderDir | Out-Null
}

Write-Host "Copying provider exe -> $hypervProviderDir"
$destinationBinary = Join-Path $hypervProviderDir "terraform-provider-hyperv.exe"
Copy-Item -Path $providerExePath -Destination $destinationBinary -Force -Verbose

Write-Host "Hyper-V provider installed at: $destinationBinary"

# ------------------------------
# 5) Update Provider Config File (providers.tf)
# ------------------------------
<#
I am disabling this for now because opentofu doesn't like the certs :(

$tfFile = Join-Path -Path $infraRepoPath -ChildPath "providers.tf"
if (Test-Path $tfFile) {
    Write-Host "Updating providers configuration in providers.tf with certificate paths..."

    # Get absolute paths for the certificate files using $infraRepoPath
    $rootCAPath   = (Resolve-Path (Join-Path -Path $infraRepoPath -ChildPath "$rootCaName.cer")).Path
    $hostCertPath = (Resolve-Path (Join-Path -Path $infraRepoPath -ChildPath "$hostName.cer")).Path
    $hostKeyPath  = (Resolve-Path (Join-Path -Path $infraRepoPath -ChildPath "$hostName.pfx")).Path

    # Escape backslashes for Terraform using literal string replacement
    $escapedRootCAPath   = $rootCAPath.Replace('\', '\\')
    $escapedHostCertPath = $hostCertPath.Replace('\', '\\')
    $escapedHostKeyPath  = $hostKeyPath.Replace('\', '\\')

    # Read the file as a single string
    $content = Get-Content $tfFile -Raw

    # Update insecure to false
    $content = $content -replace '(insecure\s*=\s*)(true|false)', '${1}false'
    # Update tls_server_name to match the host name
    $content = $content -replace '(tls_server_name\s*=\s*")[^"]*"', ( '${1}' + $hostName + '"' )
    # Update certificate file paths with the escaped values
    $content = $content -replace '(cacert_path\s*=\s*")[^"]*"', ( '${1}' + $escapedRootCAPath + '"' )
    $content = $content -replace '(cert_path\s*=\s*")[^"]*"', ( '${1}' + $escapedHostCertPath + '"' )
    $content = $content -replace '(key_path\s*=\s*")[^"]*"', ( '${1}' + $escapedHostKeyPath + '"' )

    Set-Content -Path $tfFile -Value $content
    Write-Host "Updated providers.tf successfully."
}
else {
    Write-Host "providers.tf not found in $infraRepoPath; skipping provider config update."
}
#>
    Write-Host @"
Done preparing Hyper-V host and installing the provider.
You can now run 'tofu plan'/'tofu apply' in $infraRepoPath.
"@
}
