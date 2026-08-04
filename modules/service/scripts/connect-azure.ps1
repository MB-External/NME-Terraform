param(
    [Parameter(Mandatory)]
    [string]$Environment,

    [Parameter(Mandatory)]
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

if ($env:ARM_CLIENT_SECRET) {
    $securePassword = ConvertTo-SecureString $env:ARM_CLIENT_SECRET -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($env:ARM_CLIENT_ID, $securePassword)
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $env:ARM_TENANT_ID -Environment $Environment | Out-Null
}
elseif ($env:ARM_OIDC_TOKEN) {
    Connect-AzAccount -ServicePrincipal -ApplicationId $env:ARM_CLIENT_ID -FederatedToken $env:ARM_OIDC_TOKEN -Tenant $env:ARM_TENANT_ID -Environment $Environment | Out-Null
}
elseif ($env:ARM_CLIENT_CERTIFICATE_PATH -or $env:ARM_CLIENT_CERTIFICATE) {
    $certParams = @{
        ServicePrincipal = $true
        ApplicationId    = $env:ARM_CLIENT_ID
        Tenant           = $env:ARM_TENANT_ID
        Environment      = $Environment
    }
    if ($env:ARM_CLIENT_CERTIFICATE_PATH) {
        $certParams['CertificatePath'] = $env:ARM_CLIENT_CERTIFICATE_PATH
    } else {
        $certBytes = [Convert]::FromBase64String($env:ARM_CLIENT_CERTIFICATE)
        $tempCert = Join-Path ([System.IO.Path]::GetTempPath()) "tf_arm_cert_$([guid]::NewGuid().ToString('N')).pfx"
        [System.IO.File]::WriteAllBytes($tempCert, $certBytes)
        $certParams['CertificatePath'] = $tempCert
    }
    if ($env:ARM_CLIENT_CERTIFICATE_PASSWORD) {
        $certParams['CertificatePassword'] = (ConvertTo-SecureString $env:ARM_CLIENT_CERTIFICATE_PASSWORD -AsPlainText -Force)
    }
    try {
        Connect-AzAccount @certParams | Out-Null
    } finally {
        if ($tempCert -and (Test-Path $tempCert)) { Remove-Item $tempCert -Force }
    }
}
else {
    throw "No Azure authentication method found. Set one of: ARM_CLIENT_SECRET, ARM_OIDC_TOKEN, ARM_CLIENT_CERTIFICATE_PATH, or ARM_CLIENT_CERTIFICATE"
}

Set-AzContext -Subscription $SubscriptionId | Out-Null
