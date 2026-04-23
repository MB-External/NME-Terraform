# Nerdio Manager for Enterprise (NME) Terraform Deployment

This Terraform configuration deploys [Nerdio Manager for Enterprise (NME)](https://getnerdio.com/nerdio-manager-for-enterprise/) on Azure with security hardening and best practices recommended by Nerdio.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Authentication](#authentication)
- [Deployment Coverage](#deployment-coverage)
- [Quick Start](#quick-start)
- [Configuration Examples](#configuration-examples)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Configure private endpoints](#configure-private-endpoints)
- [Using a Pre-Existing VNet and Subnets](#using-a-pre-existing-vnet-and-subnets)
- [Operational Notes](#operational-notes)
- [Troubleshooting](#troubleshooting)

## Overview

This repository contains two parts:

- **`modules/service`** — the reusable Terraform module intended to be consumed directly in your own Terraform configuration.
- **`root/`** — a ready-made example root module that shows how to call `modules/service` with all required variables. Use it as a reference or starting point for your own deployment.

The module automates the deployment of Nerdio Manager for Enterprise infrastructure, including:

- Azure Web App hosting the Nerdio application
- SQL Database for data persistence
- Azure Automation Account for runbook execution
- Key Vault for secure credential storage
- Virtual Network with private endpoints for secure connectivity
- Entra ID application and service principal with required permissions
- Monitoring and logging with Application Insights and Log Analytics

## Prerequisites

### Tooling

- Terraform `>= 1.6.0`
- PowerShell 7 or later, with the `pwsh` command available from the command line on the machine running Terraform

If `pwsh` is not already installed, install PowerShell before running Terraform:

#### Windows

Windows requires PowerShell 7 or later, and `pwsh` must be resolvable from `cmd.exe` or PowerShell.

```powershell
winget install --id Microsoft.PowerShell --source winget
```

#### Linux

Use the Microsoft installation guides for your distribution:

- [Install PowerShell on Linux](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux)
- [PowerShell installation overview](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)


The following PowerShell modules must be installed on the machine running Terraform:

| Module |  Used for |
|--------|-----------|
| `Az.Accounts` |  Authentication in all `local-exec` steps |
| `Az.Websites` |  Web App package deploy and WebJob management |
| `SqlServer` |  SQL user bootstrap for the NME service principal |

Install them in a single command if needed:

```powershell
Install-Module Az.Accounts, Az.Websites, SqlServer -Scope CurrentUser -Force
```

### Azure Permissions

The deployment pipeline service principal must have the following permissions on the target Azure subscription: the **Owner** role, or alternatively a combination of **Contributor** and **User Access Administrator** with delegated assignments restricted to **Contributor**, **Reader**, and **Backup Reader**.

### Entra ID Permissions

The service principal used to run Terraform must have the following **Microsoft Graph** API permissions granted (with admin consent where required):

| Permission | Type | Description 
|------------|------|-------------|
| `Application.ReadWrite.All` | Application | Read and write all applications | 
| `AppRoleAssignment.ReadWrite.All` | Application | Manage app permission grants and app role assignments | 
| `Directory.Read.All` | Application | Read directory data | 
| `User.Read` | Delegated | Sign in and read user profile | 


### Terraform Providers

The root module requires `hashicorp/azurerm >= 3.110.0`. 

The `modules/service` child module requires:

- `hashicorp/azurerm >= 3.110.0`
- `hashicorp/azuread >= 2.47.0`
- `hashicorp/random >= 3.5.0`
- `hashicorp/null >= 3.2.0`
- `hashicorp/http >= 3.4.0`
- `hashicorp/local >= 2.4.0`
- `hashicorp/time >= 0.9.0`

## Authentication

This module relies on Terraform providers together with PowerShell local-exec steps that authenticate using Connect-AzAccount. 
Because the PowerShell scripts perform non-interactive authentication, the following environment variables must always be set, even when Terraform is executed outside a CI/CD pipeline.

- `ARM_TENANT_ID`
- `ARM_SUBSCRIPTION_ID`
- `ARM_CLIENT_ID`
- either `ARM_CLIENT_SECRET` **or** `ARM_OIDC_TOKEN`

## Deployment Coverage

The `modules/service` module deploys and configures:

- **Web tier**
  - Windows App Service Plan
  - Windows Web App 
  - Package deployment pipeline
- **Identity and access**
  - Entra ID application + service principal
  - Application password and certificate credential
  - App roles (Reviewer, HelpDesk, DesktopAdmin, WvdAdmin, RestClient) and optional user role assignments
  - RBAC role assignments for the NME service principal
- **Database**
  - Azure SQL Server + database
  - Entra ID admin configuration
  - SQL firewall rules for Azure services and deployer IP (when private endpoints are disabled)
  - SQL user bootstrap for NME service principal
- **Secrets and keys**
  - Key Vault
  - Data protection key
  - Secrets for SQL connection string, Entra ID client secret, data protection blob path, locks container SAS URL
- **Storage**
  - Data protection storage account
  - Private containers for data protection keys and locks
- **Automation**
  - Two Automation Accounts (updates and scripted actions)
  - Imported runbook (`nmwUpdateRunAs`)
- **Monitoring**
  - Log Analytics Workspace for session host monitoring
  - Log Analytics Workspace for Application Insights / app logs
  - Data Collection Endpoint + Data Collection Rule
  - Application Insights
- **Networking (optional)**
  - Dedicated VNet + subnets for private endpoints and app integration
  - VNet peering to deployment VNet (optional)
  - Private DNS zones + VNet links
  - Private endpoints for Web App, SQL, Key Vault, Storage (blob), Automation
- **Protection (optional)**
  - Management locks for Key Vault, SQL database, and data protection storage account

## Quick Start

From `root/`:

```shell
cd .\root
cp .\terraform.tfvars.example .\terraform.tfvars
# edit terraform.tfvars

terraform init
terraform plan -var-file="terraform.tfvars" -out="main.tfplan"
terraform apply "main.tfplan"
```

## Configuration Examples

### 1) Baseline public deployment

```hcl
resource_group_name = "rg-nerdio-nmw-prod"

azuread_app_name          = "nerdio-nmw-app-prod"
azure_environment         = "AzureCloud"
subscription_display_name = "Production Subscription"

location                  = "westeurope"
azure_tag_prefix          = "NMW"
protect_resources         = true

app_service_plan_sku_name = "B3"
app_service_plan_name     = "nme-plan-prod"
web_app_portal_name       = "nme-portal-prod"

sql_server_name     = "nme-sql-prod"
database_name       = "nme-db"
sql_collation       = "SQL_Latin1_General_CP1_CI_AS"
database_sku_name   = "S1"
database_max_size_gb = 250

key_vault_name                         = "nme-kv-prod"
data_protection_storage_account_name   = "nmepdprod001"
data_protection_keys_blob_name         = "keys-prod.xml"
data_protection_key_name               = "DataProtection-prod"

automation_account_name                = "nme-automation-prod"
scripted_action_account_name           = "nme-scripted-actions-prod"
law_name                               = "nme-law-prod"
logs_law_name                          = "nme-logs-law-prod"
app_insights_name                      = "nme-insights-prod"

configure_private_endpoints = false
private_web_app             = false

app_package_version = "latest"
app_role_assignments = {}
tags_by_resource = {}
```

### 2) Private endpoint deployment

```hcl
configure_private_endpoints    = true
private_web_app                = true

deployment_vnet_name           = "corp-deployment-vnet"
deployment_resource_group_name = "rg-network-shared"

network_config = {
  vnet_name       = "nme-private-vnet"
  vnet_cidr       = "10.200.0.0/16"
  pe_subnet_name  = "nme-privateendpoints-subnet"
  pe_subnet_cidr  = "10.200.1.0/24"
  app_subnet_name = "nme-app-subnet"
  app_subnet_cidr = "10.200.2.0/27"
}
```


### 3) App role assignment example

```hcl
app_role_assignments = {
  WvdAdmin     = ["admin@contoso.com", "admin2@contoso.com"]
  Reviewer     = ["viewer@contoso.com"]
  HelpDesk     = ["helpdesk@contoso.com"]
  DesktopAdmin = ["desktopadmin@contoso.com"]
}
```

Valid role keys: `Reviewer`, `HelpDesk`, `DesktopAdmin`, `WvdAdmin`, `RestClient`.

### 4) Resource-type-specific tags

```hcl
tags_by_resource = {
  "Microsoft.Web/sites" = {
    environment = "production"
    owner       = "EUC"
  }

  "Microsoft.Sql/servers" = {
    environment         = "production"
    data-classification = "confidential"
  }

  "Microsoft.KeyVault/vaults" = {
    environment = "production"
  }
}
```

## Inputs

### Required

| Name | Type | Description |
|------|------|-------------|
| `resource_group_name` | `string` | Name of the resource group where all resources will be created |
| `azuread_app_name` | `string` | Name of the Entra ID application to create |
| `azure_environment` | `string` | Azure environment — `AzureCloud`, `AzureUSGovernment`, or `AzureChinaCloud`. The Entra ID login endpoint is derived automatically from this value. |
| `subscription_display_name` | `string` | Human-readable subscription name (informational) |
| `location` | `string` | Azure region where all resources will be deployed |
| `azure_tag_prefix` | `string` | Prefix used for custom Azure tags |
| `app_service_plan_sku_name` | `string` | SKU for the App Service Plan (e.g., `B1`, `B3`, `S1`, `P1v2`) |
| `sql_collation` | `string` | Collation for the SQL database |
| `database_sku_name` | `string` | SKU for the SQL database (e.g., `S0`, `S1`, `P1`) |
| `web_app_portal_name` | `string` | Name for the Web App resource |
| `app_service_plan_name` | `string` | Name for the App Service Plan resource |
| `sql_server_name` | `string` | Name for the SQL Server resource |
| `database_name` | `string` | Name for the SQL Database resource |
| `key_vault_name` | `string` | Name for the Key Vault resource |
| `app_insights_name` | `string` | Name for the Application Insights resource |
| `automation_account_name` | `string` | Name for the Automation Account (NME updates) |
| `law_name` | `string` | Name for the Log Analytics Workspace (session host monitoring) |
| `logs_law_name` | `string` | Name for the Log Analytics Workspace (Application Insights) |
| `scripted_action_account_name` | `string` | Name for the Automation Account (scripted actions) |
| `data_protection_storage_account_name` | `string` | Name for the Storage Account (data protection keys) |
| `data_protection_keys_blob_name` | `string` | Name of the blob file where data protection keys are stored |

### Optional

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `protect_resources` | `bool` | `false` | Apply management locks to Key Vault, SQL Database, and Storage Account |
| `database_max_size_gb` | `number` | `250` | Maximum size of the SQL database in GB |
| `tags_by_resource` | `map(map(string))` | `{}` | Resource-type-specific tags |
| `configure_private_endpoints` | `bool` | `false` | Whether to create private endpoints for services |
| `deployment_vnet_name` | `string` | `null` | VNet from which Terraform deployment is executed. **Required when `configure_private_endpoints = true`** |
| `deployment_resource_group_name` | `string` | `null` | Resource group of the deployment VNet. **Required when `configure_private_endpoints = true`** |
| `network_config` | `object` | `null` | Network configuration for private endpoints. ** Required when `configure_private_endpoints = true`** |
| `private_web_app` | `bool` | `false` | Whether the Web App should be accessible only via private endpoint |
| `data_protection_key_name` | `string` | `"DataProtection-main"` | Name of the data protection key in Key Vault |
| `maintenance_service_url` | `string` | `"https://nwp-web-app.azurewebsites.net"` | URL of the NME maintenance service |
| `app_package_version` | `string` | `"latest"`  | Application package version to deploy or `latest` |
| `app_role_assignments` | `map(list(string))` | `{}` | Map of app role names to lists of user principal names to assign |
| `private_endpoint_post_resolve_delay` | `number` | `0` | Extra delay in seconds after private endpoint connectivity is confirmed. Increase to 60–180 if first deploy with private endpoints fails with 403 errors on KV writes |

See `root/terraform.tfvars.example` for a complete starting-point configuration.


## Outputs

The `modules/service` module exposes the following outputs:

| Output | Description |
|--------|-------------|
| `web_app_id` | ID of the Windows Web App |
| `web_app_name` | Name of the Windows Web App |
| `web_app_default_hostname` | Default hostname of the Web App |
| `web_app_identity_principal_id` | Principal ID of the Web App managed identity |
| `web_app_identity_tenant_id` | Tenant ID of the Web App managed identity |
| `app_service_plan_id` | ID of the App Service Plan |
| `app_service_plan_name` | Name of the App Service Plan |
| `sql_server_id` | ID of the SQL Server |
| `sql_server_name` | Name of the SQL Server |
| `sql_server_fqdn` | Fully qualified domain name of the SQL Server |
| `sql_database_id` | ID of the SQL Database |
| `sql_database_name` | Name of the SQL Database |
| `key_vault_id` | ID of the Key Vault |
| `key_vault_name` | Name of the Key Vault |
| `key_vault_uri` | URI of the Key Vault |
| `storage_account_id` | ID of the Data Protection Storage Account |
| `storage_account_name` | Name of the Data Protection Storage Account |
| `storage_account_primary_blob_endpoint` | Primary blob endpoint of the Storage Account |
| `app_insights_id` | ID of Application Insights |
| `app_insights_name` | Name of Application Insights |
| `app_insights_connection_string` | Connection string of Application Insights (sensitive) |
| `app_insights_instrumentation_key` | Instrumentation key of Application Insights (sensitive) |
| `app_insights_app_id` | App ID of Application Insights |
| `law_id` | ID of the Log Analytics Workspace |
| `law_name` | Name of the Log Analytics Workspace |
| `law_workspace_id` | Workspace ID of the Log Analytics Workspace |
| `logs_law_id` | ID of the Logs Log Analytics Workspace |
| `logs_law_name` | Name of the Logs Log Analytics Workspace |
| `logs_law_workspace_id` | Workspace ID of the Logs Log Analytics Workspace |
| `automation_account_id` | ID of the Automation Account |
| `automation_account_name` | Name of the Automation Account |
| `automation_account_identity_principal_id` | Principal ID of the Automation Account managed identity |
| `scripted_action_account_id` | ID of the Scripted Action Automation Account |
| `scripted_action_account_name` | Name of the Scripted Action Automation Account |
| `private_endpoints_vnet_id` | ID of the Private Endpoints VNet (or `null`) |
| `private_endpoints_vnet_name` | Name of the Private Endpoints VNet (or `null`) |
| `private_endpoints_subnet_id` | ID of the Private Endpoints Subnet (or `null`) |
| `app_subnet_id` | ID of the App Subnet (or `null`) |
| `data_collection_endpoint_id` | ID of the Data Collection Endpoint |
| `data_collection_rule_id` | ID of the Data Collection Rule |
| `resource_group_name` | Name of the Resource Group |
| `location` | Azure location where resources are deployed |
| `azuread_app_client_id` | Client ID of the NME Entra ID application |
| `azuread_app_object_id` | Object ID of the NME Entra ID application |
| `azuread_service_principal_id` | Object ID of the NME service principal |

> **Note:** The root module currently defines no `output` blocks. Run `terraform output` after adding pass-through outputs if needed.

## Configure private endpoints

When `configure_private_endpoints = true`, every NME service is placed behind an Azure Private Endpoint and public network access is disabled. All traffic between services stays on the Microsoft backbone network, and the resources are no longer reachable from the public internet.

### What gets created

The module provisions a dedicated VNet with two subnets and creates private endpoints for five services:

| Service | Private Endpoint sub-resource | Private DNS zone (AzureCloud) |
|---------|-------------------------------|-------------------------------|
| SQL Server | `sqlServer` | `privatelink.database.windows.net` |
| Key Vault | `vault` | `privatelink.vaultcore.azure.net` |
| Storage Account (blob) | `blob` | `privatelink.blob.core.windows.net` |
| Web App | `sites` | `privatelink.azurewebsites.net` |
| Automation Account | `Webhook` | `privatelink.azure-automation.net` |

Each private endpoint gets a corresponding private DNS zone linked to the NME VNet (and the deployment VNet, if configured). This ensures that DNS queries for these services resolve to private IP addresses within the VNet instead of public endpoints.

### Why Terraform must run from the deployment network

Once private endpoints are enabled, the following resources reject traffic originating from outside the VNet:

- **SQL Server** — `public_network_access_enabled = false`; no firewall rules are created.
- **Key Vault** — `public_network_access_enabled = false`; network ACL default action is `Deny`.
- **Storage Account** — `public_network_access_enabled = false`.

Terraform needs to reach these resources during deployment (e.g., to bootstrap the SQL user, write Key Vault secrets, and upload blobs). If Terraform runs from a machine that is not on a network peered to the NME VNet, those operations will fail with network connectivity errors.

To solve this, run Terraform from a VM (or CI/CD agent) that resides on a **deployment VNet** — a pre-existing VNet that the module will peer with the NME private-endpoints VNet. The module creates bidirectional VNet peering and links every private DNS zone to the deployment VNet, so the deployment machine can resolve and reach all private endpoints.

### Configuration

Set the following variables in `terraform.tfvars`:

```hcl
configure_private_endpoints = true
private_web_app             = true   # set to false if the portal should remain publicly accessible

# Deployment network — the VNet where the machine running Terraform resides
deployment_vnet_name           = "corp-deployment-vnet"
deployment_resource_group_name = "rg-network-shared"

# NME private network to be created by the module
network_config = {
  vnet_name       = "nme-private-vnet"
  vnet_cidr       = "10.200.0.0/16"
  pe_subnet_name  = "nme-privateendpoints-subnet"
  pe_subnet_cidr  = "10.200.1.0/24"
  app_subnet_name = "nme-app-subnet"
  app_subnet_cidr = "10.200.2.0/27"
}
```

### Variable reference

| Variable | Required | Description |
|----------|----------|-------------|
| `configure_private_endpoints` | Yes | Set to `true` to enable private endpoints for all services |
| `private_web_app` | No | When `true`, the Web App is also made private (public access disabled). Defaults to `false` |
| `deployment_vnet_name` | Yes (when PE enabled) | Name of the pre-existing VNet where the Terraform runner is located. The module creates VNet peering and links all private DNS zones to this VNet |
| `deployment_resource_group_name` | Yes (when PE enabled) | Resource group of the deployment VNet |
| `network_config` | Yes (when PE enabled) | Object defining VNet and subnet names/CIDRs for the NME private network |

## Using a Pre-Existing VNet and Subnets

If you have already deployed the VNet and subnets outside of this Terraform module (manually, via another pipeline, or a separate Terraform root), you can still use the module. The approach is to import the existing Azure resources into Terraform state so the module treats them as its own, and then set `network_config` so the module's resource definitions match what is already deployed.

### How it works

When `configure_private_endpoints = true`, the module creates:

| Terraform address | Azure resource |
|---|---|
| `module.service.azurerm_virtual_network.private_endpoints_vnet[0]` | The VNet |
| `module.service.azurerm_subnet.private_endpoints[0]` | Private-endpoints subnet |
| `module.service.azurerm_subnet.app[0]` | App-integration subnet |

Importing these resources maps the real Azure objects to those addresses without recreating them.

### Step 1 — Configure `terraform.tfvars` to match your existing resources

Set `network_config` to values that **exactly** match the deployed resources (names and CIDRs must be identical):

```hcl
configure_private_endpoints = true

network_config = {
  vnet_name       = "<your-existing-vnet-name>"
  vnet_cidr       = "<your-existing-vnet-cidr>"         # e.g. "10.0.0.0/16"
  pe_subnet_name  = "<your-existing-pe-subnet-name>"
  pe_subnet_cidr  = "<your-existing-pe-subnet-cidr>"    # e.g. "10.0.1.0/24"
  app_subnet_name = "<your-existing-app-subnet-name>"
  app_subnet_cidr = "<your-existing-app-subnet-cidr>"   # e.g. "10.0.2.0/27"
}
```

Also set the deployment VNet variables (required when private endpoints are enabled):

```hcl
deployment_vnet_name           = "<deployment-vnet-name>"
deployment_resource_group_name = "<deployment-vnet-resource-group>"
```

### Step 2 — Import the existing resources

Run the following commands from the `root/` directory. Replace the placeholder values with your actual subscription ID, resource group, VNet name, and subnet names.

```shell
# VNet
terraform import \
  'module.service.azurerm_virtual_network.private_endpoints_vnet[0]' \
  '/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>'

# Private-endpoints subnet
terraform import \
  'module.service.azurerm_subnet.private_endpoints[0]' \
  '/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<pe-subnet-name>'

# App-integration subnet
terraform import \
  'module.service.azurerm_subnet.app[0]' \
  '/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<app-subnet-name>'
```

### Step 3 — Verify no unintended changes

```shell
terraform plan -var-file="terraform.tfvars"
```

The plan should show **no changes** for the three networking resources. If it shows in-place updates, the most common causes are:

| Symptom | Fix |
|---|---|
| Name or CIDR mismatch | Correct the `network_config` values in `terraform.tfvars` to exactly match the deployed resource |
| Subnet delegation missing | Add the `Microsoft.Web/serverFarms` delegation to the existing app subnet before importing |
| `private_endpoint_network_policies` differs | Set the policy to `RouteTableEnabled` on both subnets in the Azure portal or CLI before importing |
| Missing `Microsoft.KeyVault` service endpoint on app subnet | Add the service endpoint to the existing app subnet before importing |

### Step 4 — Apply

Once the plan shows no networking changes, proceed normally:

```shell
terraform apply -var-file="terraform.tfvars"
```

Terraform will deploy the remaining NME service resources (Web App, SQL, Key Vault, etc.) and use the imported VNet and subnets without touching them.


## Operational Notes

- `provider "azurerm"` in root sets `resource_provider_registrations = "none"`; resource providers must already be registered in the subscription.
- Several deployment steps use `null_resource` with `timestamp()` triggers, so package download, deploy, and health-check steps run on every `terraform apply`.
- When enabling private endpoints, the build pipeline running Terraform **must** execute from the deployment network specified by `deployment_vnet_name`. This network is peered to the NME VNet and all private DNS zones are linked to it, giving the runner access to otherwise private resources (SQL, Key Vault, Storage).
- `network_config`, `deployment_vnet_name`, and `deployment_resource_group_name` are all required when `configure_private_endpoints = true`.
- On clean deployments with `configure_private_endpoints = true`, Azure may return **403 `ForbiddenByConnection`** errors when writing Key Vault secrets or keys. This happens because of race condition between private endpoint creation and DNS propagation. Two mitigation options:
  1. **Increase the post-resolve delay** — set `private_endpoint_post_resolve_delay = 60` (or higher) to add a wait buffer after DNS and TCP checks pass but before Terraform proceeds to write secrets.
  2. **Re-run `terraform apply`** — a second apply will succeed because the private endpoints are already fully propagated; this is safe because all Terraform resources are idempotent.


## Troubleshooting

- **PowerShell command not found**
  - Ensure `pwsh` and required Az/SqlServer modules exist in the Terraform runner environment.
- **App role assignments fail for users**
  - Verify each UPN exists in Entra ID, and that the deployment identity can read users and assign app roles.
- **Private endpoint deployment cannot resolve resources**
  - Verify `network_config`, DNS zone links, and that `deployment_vnet_name` + `deployment_resource_group_name` are correct.
- **SQL bootstrap (`Invoke-Sqlcmd`) fails**
  - Ensure SQL connectivity path is valid from the deployment environment and token-based auth commands succeed.

