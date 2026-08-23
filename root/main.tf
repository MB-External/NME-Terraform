terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  resource_provider_registrations = "none"
  features {}
}

resource "azurerm_resource_group" "core" {
  name     = var.resource_group_name
  location = var.location
}

module "service" {
  source = "../modules/service"

  resource_group_name = azurerm_resource_group.core.name

  azuread_app_name          = var.azuread_app_name
  azure_environment         = var.azure_environment
  subscription_display_name = var.subscription_display_name

  location          = azurerm_resource_group.core.location
  protect_resources = var.protect_resources

  # (keep passing through the rest as you already do)
  azure_tag_prefix                     = var.azure_tag_prefix
  app_service_plan_sku_name            = var.app_service_plan_sku_name
  sql_collation                        = var.sql_collation
  database_max_size_gb                 = var.database_max_size_gb
  database_sku_name                    = var.database_sku_name
  tags_by_resource                     = var.tags_by_resource
  configure_private_endpoints          = var.configure_private_endpoints
  deployment_vnet_name                 = var.deployment_vnet_name
  deployment_resource_group_name       = var.deployment_resource_group_name
  network_config                       = var.network_config
  private_web_app                      = var.private_web_app
  web_app_portal_name                  = var.web_app_portal_name
  app_service_plan_name                = var.app_service_plan_name
  sql_server_name                      = var.sql_server_name
  database_name                        = var.database_name
  key_vault_name                       = var.key_vault_name
  app_insights_name                    = var.app_insights_name
  automation_account_name              = var.automation_account_name
  law_name                             = var.law_name
  logs_law_name                        = var.logs_law_name
  scripted_action_account_name         = var.scripted_action_account_name
  data_protection_storage_account_name = var.data_protection_storage_account_name
  data_protection_keys_blob_name       = var.data_protection_keys_blob_name
  data_protection_key_name             = var.data_protection_key_name
  maintenance_service_url              = var.maintenance_service_url
  app_package_version                  = var.app_package_version
  app_package_local_path               = var.app_package_local_path
  app_role_assignments                 = var.app_role_assignments
  private_endpoint_post_resolve_delay  = var.private_endpoint_post_resolve_delay
  app_cert_name                        = var.app_cert_name
  app_cert_lifetime_months             = var.app_cert_lifetime_months
  app_package_redeploy_trigger         = var.app_package_redeploy_trigger
  read_only_deployment_principal_ids   = var.read_only_deployment_principal_ids
  read_write_deployment_principal_ids  = var.read_write_deployment_principal_ids
  existing_network_config              = var.existing_network_config
  tags                                 = var.tags
  sql_server_identity                  = var.sql_server_identity
  azuread_app_owners                   = var.azuread_app_owners
  sql_azuread_administrator            = var.sql_azuread_administrator
  assign_subscription_roles            = var.assign_subscription_roles
  enable_zone_redundancy               = var.enable_zone_redundancy
}
