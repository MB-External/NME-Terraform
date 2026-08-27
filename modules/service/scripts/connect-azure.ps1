param(
    [Parameter(Mandatory)]
    [string]$Environment,

    [Parameter(Mandatory)]
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

$existingContext = Get-AzContext -ErrorAction SilentlyContinue
if ($existingContext -and $existingContext.Account) {
    Write-Verbose "Az PowerShell: already authenticated as '$($existingContext.Account.Id)'. Skipping login."
}
elseif ($env:ARM_CLIENT_SECRET) {
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

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Verbose "Az PowerShell: subscription set to '$SubscriptionId'."

# ── Az CLI ───────────────────────────────────────────────────────────────────

az cloud set --name $Environment 2>&1 | Out-Null

$cliAccount = az account show 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($cliAccount -and $cliAccount.id) {
    Write-Verbose "Az CLI: already authenticated as '$($cliAccount.user.name)'. Skipping login."
}
elseif ($env:ARM_CLIENT_SECRET) {
    az login --service-principal `
        --username $env:ARM_CLIENT_ID `
        --password $env:ARM_CLIENT_SECRET `
        --tenant $env:ARM_TENANT_ID `
        --output none
}
elseif ($env:ARM_OIDC_TOKEN) {
    az login --service-principal `
        --username $env:ARM_CLIENT_ID `
        --federated-token $env:ARM_OIDC_TOKEN `
        --tenant $env:ARM_TENANT_ID `
        --output none
}
elseif ($env:ARM_CLIENT_CERTIFICATE_PATH -or $env:ARM_CLIENT_CERTIFICATE) {
    $tempCliCert = $null
    try {
        if ($env:ARM_CLIENT_CERTIFICATE_PATH) {
            $cliCertPath = $env:ARM_CLIENT_CERTIFICATE_PATH
        } else {
            $certBytes = [Convert]::FromBase64String($env:ARM_CLIENT_CERTIFICATE)
            $tempCliCert = Join-Path ([System.IO.Path]::GetTempPath()) "tf_cli_cert_$([guid]::NewGuid().ToString('N')).pem"
            [System.IO.File]::WriteAllBytes($tempCliCert, $certBytes)
            $cliCertPath = $tempCliCert
        }
        az login --service-principal `
            --username $env:ARM_CLIENT_ID `
            --certificate $cliCertPath `
            --tenant $env:ARM_TENANT_ID `
            --output none
    } finally {
        if ($tempCliCert -and (Test-Path $tempCliCert)) { Remove-Item $tempCliCert -Force }
    }
}
else {
    throw "No Azure CLI authentication method found. Set one of: ARM_CLIENT_SECRET, ARM_OIDC_TOKEN, ARM_CLIENT_CERTIFICATE_PATH, or ARM_CLIENT_CERTIFICATE"
}

az account set --subscription $SubscriptionId
Write-Verbose "Az CLI: subscription set to '$SubscriptionId'."
