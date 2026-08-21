variable "resource_group_name" {
  description = "Name of the resource group where all resources will be created"
  type        = string
}

variable "azuread_app_name" {
  description = "Name of the Azure AD application to create/use for the service"
  type        = string
}

variable "azure_environment" {
  description = "Azure environment name (AzureCloud, AzureUSGovernment, AzureChinaCloud)"
  type        = string
}

variable "subscription_display_name" {
  description = "Human-readable subscription name (informational)"
  type        = string
}


variable "location" {
  description = "Azure region where all resources will be deployed"
  type        = string
}

variable "protect_resources" {
  description = "Whether to apply management locks to critical resources (Key Vault, SQL Database, Storage)"
  type        = bool
  default     = false
}

variable "azure_tag_prefix" {
  description = "Prefix used for custom Azure tags"
  type        = string
}

variable "app_service_plan_sku_name" {
  description = "SKU name for the App Service Plan (e.g., B1, B2, B3, S1, P1v2)"
  type        = string
}

variable "sql_collation" {
  description = "Collation for the SQL database"
  type        = string
}

variable "database_max_size_gb" {
  description = "Maximum size of the SQL database in gigabytes"
  type        = number
  default     = 250
}

variable "database_sku_name" {
  description = "SKU name for the SQL database (e.g., S0, S1, P1)"
  type        = string
}

variable "tags_by_resource" {
  description = "Map of resource type to tags. Allows applying specific tags to different Azure resource types"
  type        = map(map(string))
  default     = {}
}

variable "configure_private_endpoints" {
  description = "Whether to configure private endpoints for services"
  type        = bool
  default     = false
}

variable "deployment_vnet_name" {
  description = "VNet from which TF deployment is executed. Required when configure_private_endpoints = true."
  type        = string
  default     = null
}

variable "deployment_resource_group_name" {
  description = "Resource group from which TF deployment is executed. Required when configure_private_endpoints = true."
  type        = string
  default     = null
}

variable "network_config" {
  description = "Network configuration for private endpoints. Required when configure_private_endpoints = true."
  type = object({
    vnet_name       = string
    vnet_cidr       = string
    pe_subnet_name  = string
    pe_subnet_cidr  = string
    app_subnet_name = string
    app_subnet_cidr = string
  })
  default = null
}

variable "private_web_app" {
  description = "Whether the Web App should be accessible only via private endpoint"
  type        = bool
  default     = false
}

variable "web_app_portal_name" {
  description = "Name for the Web App resource"
  type        = string
}

variable "app_service_plan_name" {
  description = "Name for the App Service Plan resource"
  type        = string
}

variable "sql_server_name" {
  description = "Name for the SQL Server resource"
  type        = string
}

variable "database_name" {
  description = "Name for the SQL Database resource"
  type        = string
}

variable "key_vault_name" {
  description = "Name for the Key Vault resource"
  type        = string
}

variable "app_insights_name" {
  description = "Name for the Application Insights resource"
  type        = string
}

variable "automation_account_name" {
  description = "Name for the Automation Account used for NME updates"
  type        = string
}

variable "law_name" {
  description = "Name for the Log Analytics Workspace used for session host monitoring"
  type        = string
}

variable "logs_law_name" {
  description = "Name for the Log Analytics Workspace used for Application Insights"
  type        = string
}

variable "scripted_action_account_name" {
  description = "Name for the Automation Account used for Scripted Actions"
  type        = string
}

variable "data_protection_storage_account_name" {
  description = "Name for the Storage Account used for Data Protection keys"
  type        = string
}

variable "data_protection_keys_blob_name" {
  description = "Name of the blob file where Data Protection keys are stored"
  type        = string
}

variable "data_protection_key_name" {
  description = "Name of the Data Protection Key"
  type        = string
  default     = "DataProtection-main"
}

variable "maintenance_service_url" {
  description = "Maintenance service URL"
  type        = string
  default     = "https://nwp-web-app.azurewebsites.net"
}

variable "app_package_version" {
  description = "Application package version to request from the maintenance service (e.g. 1.0.0.0)"
  type        = string
  default     = "latest"
}

variable "app_package_local_path" {
  description = "Absolute path to a pre-downloaded NME application package .zip on the machine running Terraform. When set, the maintenance service is not contacted (offline/disconnected install) and app_package_version is ignored. The package archive must contain app.zip and related deployment files."
  type        = string
  default     = null

  validation {
    condition     = var.app_package_local_path == null || can(regex("(?i)\\.zip$", trimspace(var.app_package_local_path)))
    error_message = "app_package_local_path must point to a .zip file."
  }
}

variable "app_role_assignments" {
  description = "Optional map of app role names to lists of user principal names (emails) to assign to those roles. Roles: Reviewer, HelpDesk, DesktopAdmin, WvdAdmin, RestClient"
  type        = map(list(string))
  default     = {}
}


variable "private_endpoint_post_resolve_delay" {
  description = "Extra delay in seconds after private endpoint DNS resolves and TCP connectivity is confirmed. Increase (e.g. 30-60) if first apply with private endpoints fails with 403 errors."
  type        = number
  default     = 0
}

variable "app_cert_name" {
  description = "Name of the self-signed certificate in Key Vault used for Azure AD app authentication (for features that do not support Managed Identity)"
  type        = string
  default     = "nme-app-cert"
}

variable "app_cert_lifetime_months" {
  description = "Validity period in months for the Azure AD app authentication certificate"
  type        = number
  default     = 4

  validation {
    condition     = var.app_cert_lifetime_months >= 1 && var.app_cert_lifetime_months <= 297 && floor(var.app_cert_lifetime_months) == var.app_cert_lifetime_months
    error_message = "app_cert_lifetime_months must be a whole number between 1 and 297 (Key Vault supported range)."
  }
}

