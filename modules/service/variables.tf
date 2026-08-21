variable "resource_group_name" {
  description = "Resource group name where all resources are created"
  type        = string
}

variable "azuread_app_name" {
  description = "Name of the Azure AD application to create/use for the service"
  type        = string
}

variable "azuread_app_owners" {
  description = "List of Azure AD user principals to assign as owners of the Azure AD application"
  type        = list(string)
  default     = []
}

variable "location" {
  description = "Location for all resources"
  type        = string
}

variable "protect_resources" {
  description = "Specifies whether resources should be protected with management locks"
  type        = bool
  default     = false
}

variable "azure_tag_prefix" {
  description = "Prefix for Azure Tags"
  type        = string
}

variable "app_service_plan_sku_name" {
  description = "The SKU of App Service Plan"
  type        = string
}

variable "sql_collation" {
  description = "The database collation"
  type        = string
}

variable "database_max_size_gb" {
  description = "Maximum size of the SQL database in GB"
  type        = number
  default     = 250
}

variable "database_sku_name" {
  description = "SQL database SKU name"
  type        = string
}

variable "tags_by_resource" {
  description = "Optional extra tags by resource"
  type        = map(map(string))
  default     = {}
}

variable "configure_private_endpoints" {
  description = "Specifies whether Private Endpoints will be configured"
  type        = bool
  default     = false
}

variable "deployment_vnet_name" {
  description = "VNet from which Terraform deployment will be executed. Required when configure_private_endpoints = true."
  type        = string
  default     = null

  validation {
    condition     = var.configure_private_endpoints == false || var.existing_network_config != null || var.deployment_vnet_name != null
    error_message = "deployment_vnet_name is required when configure_private_endpoints is true."
  }
}

variable "deployment_resource_group_name" {
  description = "Resource group of the deployment VNet. Required when configure_private_endpoints = true."
  type        = string
  default     = null

  validation {
    condition     = var.configure_private_endpoints == false || var.existing_network_config != null || var.deployment_resource_group_name != null
    error_message = "deployment_resource_group_name is required when configure_private_endpoints is true."
  }
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

  validation {
    condition     = var.configure_private_endpoints == false || (var.network_config != null || var.existing_network_config != null)
    error_message = "network_config or existing_network_config is required when configure_private_endpoints is true"
  }
  validation {
    condition     = var.configure_private_endpoints == false || (var.network_config == null || var.existing_network_config == null)
    error_message = "only one of network_config or existing_network_config should be provided when configure_private_endpoints is true"
  }
}

variable "existing_network_config" {
  description = "Existing network configuration for private endpoints. Required when configure_private_endpoints = true and network_config is not provided."
  type = object({
    vnet_name           = string
    pe_subnet_name      = string
    app_subnet_name     = string
    resource_group_name = string
    manage_dns          = optional(bool, true)
    create_dns_zones    = optional(bool, true)
    link_dns_zones      = optional(bool, true)
    dns_zone_ids = optional(object({
      sql             = string
      data_protection = string
      automation      = string
    }))
  })
  default = null
  validation {
    condition     = var.existing_network_config == null || var.existing_network_config.manage_dns == false || var.existing_network_config.create_dns_zones == true || var.existing_network_config.dns_zone_ids != null
    error_message = "dns_zone_ids must be specified if manage_dns is true and create_dns_zones is false"
  }
  validation {
    condition     = var.existing_network_config == null || var.existing_network_config.create_dns_zones == false || var.existing_network_config.dns_zone_ids == null
    error_message = "dns_zone_ids should not be specified when create_dns_zones is true"
  }
  validation {
    condition     = var.existing_network_config == null || var.existing_network_config.manage_dns == true || (var.existing_network_config.create_dns_zones == false && var.existing_network_config.link_dns_zones == false && var.existing_network_config.dns_zone_ids == null)
    error_message = "create_dns_zones, link_dns_zones, and dns_zone_ids are only applicable when manage_dns is true"
  }
}

variable "private_web_app" {
  description = "Specifies whether the Web App should be private or public"
  type        = bool
  default     = false
}

variable "web_app_portal_name" {
  description = "Web App resource name override"
  type        = string
}

variable "app_service_plan_name" {
  description = "App Service Plan resource name override"
  type        = string
}

variable "sql_server_name" {
  description = "SQL Server resource name override"
  type        = string
}

variable "database_name" {
  description = "SQL Database resource name override"
  type        = string
}

variable "sql_azuread_administrator" {
  description = "Azure AD administrator for SQL Server, uses the current service principal if not specified"
  type = object({
    login_username = string
    object_id      = string
    tenant_id      = string
  })
  default = null
}

variable "key_vault_name" {
  description = "Key Vault resource name override"
  type        = string
}

variable "app_insights_name" {
  description = "Application Insights resource name override"
  type        = string
}

variable "automation_account_name" {
  description = "Automation Account name for NME updates"
  type        = string
}

variable "law_name" {
  description = "Log Analytics Workspace for session hosts"
  type        = string
}

variable "logs_law_name" {
  description = "Log Analytics Workspace for Application Insights"
  type        = string
}

variable "scripted_action_account_name" {
  description = "Automation Account for Scripted Actions"
  type        = string
}

variable "data_protection_storage_account_name" {
  description = "Storage Account for Data Protection Keys"
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

variable "data_protection_keys_blob_name" {
  description = "Name of the blob where Data Protection Keys are stored"
  type        = string
}



variable "azure_environment" {
  description = "Azure environment name (AzureCloud, AzureUSGovernment, AzureChinaCloud)"
  type        = string

  validation {
    condition     = contains(["AzureCloud", "AzureUSGovernment", "AzureChinaCloud"], var.azure_environment)
    error_message = "azure_environment must be one of: AzureCloud, AzureUSGovernment, AzureChinaCloud."
  }
}

variable "subscription_display_name" {
  description = "Human-readable subscription name (informational)"
  type        = string
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
  description = "Map of app role names to lists of user principal names to assign"
  type        = map(list(string))
  default     = {}
}

variable "private_endpoint_post_resolve_delay" {
  description = "Extra delay in seconds after private endpoint DNS resolves and TCP connectivity is confirmed. Allows Azure to fully propagate private link authorization on the data-plane. Increase this value (e.g. 30-60) if initial deployments with private endpoints fail with 403 ForbiddenByConnection errors."
  type        = number
  default     = 0
  validation {
    condition     = var.private_endpoint_post_resolve_delay >= 0 && floor(var.private_endpoint_post_resolve_delay) == var.private_endpoint_post_resolve_delay
    error_message = "private_endpoint_post_resolve_delay must be a non-negative whole number of seconds (e.g. 0, 30, 60)."
  }
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
