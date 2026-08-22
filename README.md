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
- [Deploying into an Azure Landing Zone](#deploying-into-an-azure-landing-zone)
- [Using a Pre-Existing VNet and Subnets](#using-a-pre-existing-vnet-and-subnets)
- [Offline / Disconnected Package Install](#offline--disconnected-package-install)
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

- Terraform `>= 1.12.0`
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

`Application.ReadWrite.All` is the broad application-management permission assumed by this module for bootstrap and full lifecycle operations. Adding entries to `azuread_app_owners` can still be useful for consumers that later split responsibilities, because follow-on changes to the NME application may then be performed by automation using `Application.ReadWrite.OwnedBy` instead of `Application.ReadWrite.All`. That narrower pattern is environment-specific and left to consumers to implement.


### Terraform Providers

The root module requires `hashicorp/azurerm ~> 5.0`. 

The `modules/service` child module requires:

- `hashicorp/azurerm ~> 5.0`
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
  - Entra ID application + service principal, with optional additional app owners (`azuread_app_owners`) to support owner-scoped application management patterns
  - Application password and certificate credential
  - App roles (Reviewer, HelpDesk, DesktopAdmin, WvdAdmin, RestClient) and optional user role assignments
  - RBAC role assignments for the NME service principal
- **Database**
  - Azure SQL Server + database
  - Entra ID admin configuration — defaults to the deploying service principal, or a custom principal via `sql_azuread_administrator`
  - System-assigned identity by default, or a centrally managed user-assigned identity via `sql_server_identity` (common in Landing Zone environments)
  - SQL firewall rules for Azure services and deployer IP (when private endpoints are disabled)
  - SQL user bootstrap for NME service principal
- **Secrets and keys**
  - Key Vault (purge protection always enabled)
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
  - A dedicated VNet + subnets for private endpoints and app integration created by the module, **or** an existing VNet and subnets (`existing_network_config`) for Azure Landing Zone deployments
  - VNet peering to a deployment VNet (optional — not needed when the deployment machine already has network line of sight to the existing VNet, e.g. via hub-spoke peering)
  - Private DNS zones + VNet links managed by the module, or left unmanaged (`manage_dns = false`) when a central platform (e.g. Azure Policy) manages private DNS zone groups
  - Private endpoints for Web App, SQL, Key Vault, Storage (blob), Automation
- **Protection (optional)**
  - Management locks for Key Vault, SQL database, and data protection storage account
- **Tagging**
  - Global `tags` applied to all resources, plus `tags_by_resource` for resource-type-specific tags

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

### 5) Azure Landing Zone deployment (existing VNet, centrally managed DNS)

Use `existing_network_config` instead of `network_config` when the private-endpoint VNet and subnets already exist (e.g. deployed by a landing zone spoke pipeline), and set `manage_dns = false` when private DNS zones and zone groups are managed centrally by Azure Policy rather than by this module:

```hcl
configure_private_endpoints = true
private_web_app             = true

existing_network_config = {
  vnet_name           = "spoke-nme-vnet"
  resource_group_name = "rg-network-spoke"
  pe_subnet_name       = "nme-privateendpoints-subnet"
  app_subnet_name      = "nme-app-subnet"

  # DNS zones/records for the private endpoints are created and linked by
  # an Azure Policy assignment at the landing zone level, not by this module.
  manage_dns = false
}

# Not required here: the Terraform runner already has network line of sight
# to the spoke VNet (e.g. via hub-spoke peering), so deployment_vnet_name /
# deployment_resource_group_name can be omitted.

# Use a centrally managed user-assigned identity for SQL Server instead of a
# system-assigned identity. identity_ids and primary_user_assigned_identity_id
# are ARM resource IDs (not object/principal IDs) - the module looks up the
# identity's object/principal ID itself when granting Directory.Read.All.
sql_server_identity = {
  type                               = "SystemAssigned, UserAssigned"
  identity_ids                       = ["/subscriptions/.../resourceGroups/rg-identity/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-nme-sql"]
  primary_user_assigned_identity_id  = "/subscriptions/.../resourceGroups/rg-identity/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-nme-sql"
}

# Use a break-glass group as the SQL Entra ID admin instead of the deploying
# service principal
sql_azuread_administrator = {
  login_username = "sql-admins@contoso.com"
  object_id      = "00000000-0000-0000-0000-000000000000"
  tenant_id      = "11111111-1111-1111-1111-111111111111"
}

# Apply mandatory landing zone tags to every resource
tags = {
  environment  = "production"
  cost-center  = "12345"
  landing-zone = "corp"
}
```

See [Deploying into an Azure Landing Zone](#deploying-into-an-azure-landing-zone) for the full set of options.

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
| `azuread_app_owners` | `set(string)` | `[]` | Object IDs of additional owners to assign to the Entra ID application. This can help consumers use `Application.ReadWrite.OwnedBy` for follow-on app changes instead of the broader `Application.ReadWrite.All` |
| `tags` | `map(string)` | `{}` | Tags applied to every resource created by the module, merged with `tags_by_resource` |
| `tags_by_resource` | `map(map(string))` | `{}` | Resource-type-specific tags |
| `configure_private_endpoints` | `bool` | `false` | Whether to create private endpoints for services |
| `deployment_vnet_name` | `string` | `null` | VNet from which Terraform deployment is executed. **Required when `configure_private_endpoints = true`**, unless `existing_network_config` is set and the runner already has connectivity to that VNet |
| `deployment_resource_group_name` | `string` | `null` | Resource group of the deployment VNet. **Required when `configure_private_endpoints = true`**, unless `existing_network_config` is set and the runner already has connectivity to that VNet |
| `network_config` | `object` | `null` | Network configuration used to **create** a new VNet and subnets for private endpoints. Required when `configure_private_endpoints = true` and `existing_network_config` is not set. Mutually exclusive with `existing_network_config` |
| `existing_network_config` | `object` | `null` | Use a **pre-existing** VNet and subnets instead of creating new ones (Azure Landing Zone pattern). Required when `configure_private_endpoints = true` and `network_config` is not set. See [Deploying into an Azure Landing Zone](#deploying-into-an-azure-landing-zone) |
| `sql_server_identity` | `object` | `{}` (system-assigned) | SQL Server identity configuration. Set `type = "SystemAssigned, UserAssigned"` plus `identity_ids` / `primary_user_assigned_identity_id` (ARM resource IDs, e.g. `.../userAssignedIdentities/<name>`) to use a centrally managed user-assigned identity. `create_role_assignment` controls whether the module grants `Directory.Read.All` to the identity |
| `sql_azuread_administrator` | `object` | `null` | Custom Entra ID administrator for SQL Server (`login_username`, `object_id`, `tenant_id`). Defaults to the deploying service principal when not set |
| `private_web_app` | `bool` | `false` | Whether the Web App should be accessible only via private endpoint |
| `data_protection_key_name` | `string` | `"DataProtection-main"` | Name of the data protection key in Key Vault |
| `maintenance_service_url` | `string` | `"https://nwp-web-app.azurewebsites.net"` | URL of the NME maintenance service |
| `app_package_version` | `string` | `"latest"`  | Application package version to deploy or `latest`. Ignored when `app_package_local_path` is set |
| `app_package_local_path` | `string` | `null` | Absolute path to a pre-downloaded NME application package `.zip` on the machine running Terraform. When set, the maintenance service is not contacted (offline/disconnected install). The package archive must contain `app.zip` and related deployment files |
| `app_package_redeploy_trigger` | `string` | `"1"` | Change this value to force the application package to be re-downloaded and redeployed on the next `apply`. Package deployment steps only run when this value changes, rather than on every `apply` |
| `app_role_assignments` | `map(list(string))` | `{}` | Map of app role names to lists of user principal names to assign |
| `private_endpoint_post_resolve_delay` | `number` | `0` | Extra delay in seconds after private endpoint connectivity is confirmed. Increase to 60–180 if first deploy with private endpoints fails with 403 errors on KV writes |
| `read_only_deployment_principal_ids` | `set(string)` | `[]` | Principal object IDs to grant read-only Key Vault data-plane access to. Intended for a lower-privilege identity used for `terraform plan` or other read-only validation flows |
| `read_write_deployment_principal_ids` | `set(string)` | `[]` | Principal object IDs to grant read-write Key Vault data-plane access to. Intended for the identity that runs `terraform apply`. Defaults to the current caller when not set |

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

> **Azure Landing Zone deployments:** if you already have a VNet, subnets, and/or centrally managed private DNS (e.g. via Azure Policy), use `existing_network_config` instead of `network_config`. See [Deploying into an Azure Landing Zone](#deploying-into-an-azure-landing-zone).

### Why Terraform must run from the deployment network

Once private endpoints are enabled, the following resources reject traffic originating from outside the VNet:

- **SQL Server** — `public_network_access_enabled = false`; no firewall rules are created.
- **Key Vault** — `public_network_access_enabled = false`; network ACL default action is `Deny`.
- **Storage Account** — `public_network_access_enabled = false`.

Terraform needs to reach these resources during deployment (e.g., to bootstrap the SQL user, write Key Vault secrets, and upload blobs). If Terraform runs from a machine that is not on a network peered to the NME VNet, those operations will fail with network connectivity errors.

To solve this, run Terraform from a VM (or CI/CD agent) that resides on a **deployment VNet** — a pre-existing VNet that the module will peer with the NME private-endpoints VNet. The module creates bidirectional VNet peering and links every private DNS zone to the deployment VNet, so the deployment machine can resolve and reach all private endpoints. If the runner already has network line of sight to the NME VNet (for example, it runs inside a landing zone hub that is already peered to the spoke), `deployment_vnet_name` / `deployment_resource_group_name` can be omitted and no additional peering will be created.

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
| `deployment_vnet_name` | Conditional | Name of the pre-existing VNet where the Terraform runner is located. Required unless `existing_network_config` is used and the runner already has connectivity. The module creates VNet peering and links all private DNS zones to this VNet |
| `deployment_resource_group_name` | Conditional | Resource group of the deployment VNet. Same condition as `deployment_vnet_name` |
| `network_config` | One of `network_config` / `existing_network_config` required (when PE enabled) | Object defining VNet and subnet names/CIDRs for a **new** NME private network created by the module |
| `existing_network_config` | One of `network_config` / `existing_network_config` required (when PE enabled) | Object referencing an **existing** VNet, subnets, and (optionally) DNS zones — see [Deploying into an Azure Landing Zone](#deploying-into-an-azure-landing-zone) |

## Deploying into an Azure Landing Zone

Azure Landing Zone (ALZ) environments typically provision spoke VNets and subnets ahead of time (via a network pipeline or Bicep/Terraform IaC outside this module) and often manage private DNS zones centrally with Azure Policy (e.g. the `DINE` policies that create and link `privatelink.*` zones automatically). The `existing_network_config` variable lets this module participate in that pattern instead of creating its own network resources.

### Referencing an existing VNet and subnets

Set `existing_network_config` instead of `network_config`. The module uses data sources to reference the VNet and subnets, so nothing is created or imported:

```hcl
configure_private_endpoints = true

existing_network_config = {
  vnet_name           = "spoke-nme-vnet"
  resource_group_name = "rg-network-spoke"
  pe_subnet_name      = "nme-privateendpoints-subnet"
  app_subnet_name     = "nme-app-subnet"
}
```

Requirements for the existing subnets:

- The app-integration subnet must be delegated to `Microsoft.Web/serverFarms` and have the `Microsoft.KeyVault` service endpoint enabled.
- Both subnets should have `private_endpoint_network_policies = RouteTableEnabled` (or the equivalent for your provider version).

### Controlling private DNS management

`existing_network_config` includes DNS options so the module can either manage private DNS itself or defer entirely to a central platform:

| Field | Default | Description |
|-------|---------|-------------|
| `manage_dns` | `true` | When `false`, this module does not create, link, or reference any private DNS zones. Private endpoints are still created, but their `private_dns_zone_group` is left unmanaged (`lifecycle { ignore_changes = [private_dns_zone_group] }`) so a central process — typically an Azure Policy assignment — can populate DNS records without Terraform reverting them on the next `apply` |
| `create_dns_zones` | `true` | When `manage_dns = true`: whether the module creates the five `privatelink.*` private DNS zones. Set to `false` to reuse zones that already exist (e.g. in a hub resource group) |
| `link_dns_zones` | `true` | When `manage_dns = true`: whether the module links the private DNS zones to the NME VNet (and deployment VNet, if configured) |
| `dns_zone_ids` | `null` | Required when `manage_dns = true` and `create_dns_zones = false`. Object with `sql`, `blob`, `automation`, `key_vault`, and `app_service` keys giving the resource IDs of the existing private DNS zones to use |

Common combinations:

```hcl
# 1) DNS fully managed centrally by Azure Policy — this module does not touch DNS at all
existing_network_config = {
  vnet_name           = "spoke-nme-vnet"
  resource_group_name = "rg-network-spoke"
  pe_subnet_name      = "nme-privateendpoints-subnet"
  app_subnet_name     = "nme-app-subnet"
  manage_dns          = false
}

# 2) Reuse existing hub private DNS zones, but let this module create the VNet links
existing_network_config = {
  vnet_name           = "spoke-nme-vnet"
  resource_group_name = "rg-network-spoke"
  pe_subnet_name      = "nme-privateendpoints-subnet"
  app_subnet_name     = "nme-app-subnet"
  create_dns_zones    = false
  dns_zone_ids = {
    sql         = "/subscriptions/.../resourceGroups/rg-dns-hub/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"
    blob        = "/subscriptions/.../resourceGroups/rg-dns-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    automation  = "/subscriptions/.../resourceGroups/rg-dns-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-automation.net"
    key_vault   = "/subscriptions/.../resourceGroups/rg-dns-hub/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    app_service = "/subscriptions/.../resourceGroups/rg-dns-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
  }
}
```

> `network_config` and `existing_network_config` are mutually exclusive — set exactly one of them when `configure_private_endpoints = true`.

### Identity and access in Landing Zone environments

Two additional variables help align the deployment with centrally governed identity patterns commonly enforced in Landing Zones:

- `sql_server_identity` — use a centrally managed user-assigned identity for the SQL Server instead of (or alongside) its system-assigned identity, and optionally skip the module's `Directory.Read.All` role assignment if that permission is already granted centrally (`create_role_assignment = false`). `identity_ids` and `primary_user_assigned_identity_id` take the identity's ARM resource ID (not its object/principal ID) — the module resolves the object/principal ID itself when creating the role assignment.
- `sql_azuread_administrator` — set the SQL Server's Entra ID administrator to a specific group or principal (e.g. a break-glass admin group) instead of defaulting to the deploying service principal.
- `azuread_app_owners` — assign additional owners (e.g. a platform team group) to the Entra ID application created for NME. In some environments this supports a reduced-permission operating model where later application changes can use `Application.ReadWrite.OwnedBy` instead of the broader `Application.ReadWrite.All`.

Where possible, prefer passing these values into this module from references already resolved in your own root module (for example from another module's outputs, data sources, or remote state) rather than maintaining duplicated literal IDs in tfvars. This module intentionally accepts plain values, so that wiring is left to consumers to implement in the way that best fits their platform composition.

See [Configuration Example 5](#5-azure-landing-zone-deployment-existing-vnet-centrally-managed-dns) for a complete example combining these options.

## Using a Pre-Existing VNet and Subnets

> **Prefer `existing_network_config`** (see [Deploying into an Azure Landing Zone](#deploying-into-an-azure-landing-zone)) if you simply want the module to reference an existing VNet and subnets — it does this natively via data sources and requires no import step. The import-based approach below remains useful if you want the VNet and subnets themselves to be fully managed by this module's Terraform state (for example, to apply `network_config`-style changes to them going forward).

If you have already deployed the VNet and subnets outside of this Terraform module (manually, via another pipeline, or a separate Terraform root), you can still import them so the module manages them going forward via `network_config`.

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


## Offline / Disconnected Package Install

By default, the deployment downloads the NME application package from the Nerdio maintenance service over the public internet. If the machine running Terraform cannot reach the maintenance service (restricted or disconnected environments), you can supply a pre-downloaded package instead:

```hcl
app_package_local_path = "C:/packages/package.zip"   # or /opt/packages/package.zip on Linux
```

When `app_package_local_path` is set:

- The maintenance service is **not contacted** — no version resolution and no package download.
- `app_package_version` is ignored; the version deployed is whatever the local file contains.
- The file must be the `package.zip` served by the maintenance service, or an equivalent archive containing `app.zip` and related deployment files. The inner `app.zip` alone is not supported.

Note that this is not a fully air-gapped install: the deployment still requires connectivity to Azure (ARM, the web app's SCM/Kudu endpoint, and the health-check endpoint). The typical scenario is a runner that can reach Azure — possibly via private endpoints and the deployment VNet — but cannot reach the Nerdio maintenance service.

## Operational Notes

- `provider "azurerm"` in root sets `resource_provider_registrations = "none"`; resource providers must already be registered in the subscription.
- The application package deployment steps (download, deploy, WebJob stop/start, health check) only re-run when `app_package_redeploy_trigger` changes, rather than on every `terraform apply`. Change this variable's value (e.g. bump a version string) to force a redeploy.
- When enabling private endpoints with `network_config` (module-created VNet), the build pipeline running Terraform **must** execute from the deployment network specified by `deployment_vnet_name`. This network is peered to the NME VNet and all private DNS zones are linked to it, giving the runner access to otherwise private resources (SQL, Key Vault, Storage). `deployment_vnet_name` and `deployment_resource_group_name` are optional when using `existing_network_config` if the runner already has network connectivity to the existing VNet.
- Exactly one of `network_config` or `existing_network_config` is required when `configure_private_endpoints = true`.
- When `existing_network_config.manage_dns = false`, this module does not create, link, or write to any private DNS zone for the private endpoints — it is expected that a central process (typically an Azure Policy assignment) manages private DNS zone groups for the endpoints. The module still creates the private endpoints themselves and ignores changes to `private_dns_zone_group` on them.
- Key Vault `purge_protection_enabled` is always `true` and cannot be disabled. Soft-deleted Key Vaults cannot be permanently purged before the retention period (90 days) expires; plan resource naming accordingly if you expect to redeploy under the same name.
- `read_only_deployment_principal_ids` and `read_write_deployment_principal_ids` currently control **Key Vault data-plane RBAC** created by this module. Read-only principals receive `Key Vault Reader`. Read-write principals receive `Key Vault Crypto Officer`, `Key Vault Secrets Officer`, and `Key Vault Certificates Officer` so they can create and update the data protection key, secrets, and certificate material needed during deployment.
- A common best-practice pattern is to run `terraform plan` with a dedicated lower-privilege identity included in `read_only_deployment_principal_ids`, and run `terraform apply` with a separate higher-privilege identity included in `read_write_deployment_principal_ids`. If `read_write_deployment_principal_ids` is left empty, the module falls back to the current caller's object ID.
- The Microsoft Graph and ARM/Service Management API service principals are referenced via data sources rather than managed resources, so `terraform destroy` will never attempt to delete these shared, tenant-wide service principals.
- On clean deployments with `configure_private_endpoints = true`, Azure may return **403 `ForbiddenByConnection`** errors when writing Key Vault secrets or keys. This happens because of race condition between private endpoint creation and DNS propagation. Two mitigation options:
  1. **Increase the post-resolve delay** — set `private_endpoint_post_resolve_delay = 60` (or higher) to add a wait buffer after DNS and TCP checks pass but before Terraform proceeds to write secrets.
  2. **Re-run `terraform apply`** — a second apply will succeed because the private endpoints are already fully propagated; this is safe because all Terraform resources are idempotent.


## Troubleshooting

- **PowerShell command not found**
  - Ensure `pwsh` and required Az/SqlServer modules exist in the Terraform runner environment.
- **App role assignments fail for users**
  - Verify each UPN exists in Entra ID, and that the deployment identity can read users and assign app roles.
- **Private endpoint deployment cannot resolve resources**
  - Verify `network_config` (or `existing_network_config`), DNS zone links, and — if the runner is not already connected to the VNet — that `deployment_vnet_name` + `deployment_resource_group_name` are correct.
- **Private endpoint DNS records never appear / `manage_dns = false` but resources are unreachable**
  - Confirm the central Azure Policy (or other platform process) responsible for populating `private_dns_zone_group` on private endpoints is assigned to the resource group/subscription and has run. This module intentionally does not manage DNS in this mode.
- **`dns_zone_ids must be specified` / `dns_zone_ids should not be specified` validation errors**
  - These come from `existing_network_config`: set `dns_zone_ids` only when `manage_dns = true` and `create_dns_zones = false`; otherwise omit it.
- **SQL bootstrap (`Invoke-Sqlcmd`) fails**
  - Ensure SQL connectivity path is valid from the deployment environment and token-based auth commands succeed.

