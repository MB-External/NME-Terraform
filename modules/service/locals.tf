locals {
  cloud_config = {
    AzureCloud = {
      sql_server_suffix = "database.windows.net"
      key_vault_suffix  = "vault.azure.net"
      storage_suffix    = "core.windows.net"
      web_app_suffix    = "azurewebsites.net"

      azuread_instance = "https://login.microsoftonline.com/"

      sql_private_dns         = "privatelink.database.windows.net"
      blob_private_dns        = "privatelink.blob.core.windows.net"
      file_private_dns        = "privatelink.file.core.windows.net"
      app_service_private_dns = "privatelink.azurewebsites.net"
      key_vault_private_dns   = "privatelink.vaultcore.azure.net"
      automation_private_dns  = "privatelink.azure-automation.net"
    }
    AzureUSGovernment = {
      sql_server_suffix = "database.usgovcloudapi.net"
      key_vault_suffix  = "vault.usgovcloudapi.net"
      storage_suffix    = "core.usgovcloudapi.net"
      web_app_suffix    = "azurewebsites.us"

      azuread_instance = "https://login.microsoftonline.us/"

      sql_private_dns         = "privatelink.database.usgovcloudapi.net"
      blob_private_dns        = "privatelink.blob.core.usgovcloudapi.net"
      file_private_dns        = "privatelink.file.core.usgovcloudapi.net"
      app_service_private_dns = "privatelink.azurewebsites.us"
      key_vault_private_dns   = "privatelink.vaultcore.usgovcloudapi.net"
      automation_private_dns  = "privatelink.azure-automation.us"
    }
    AzureChinaCloud = {
      sql_server_suffix = "database.chinacloudapi.cn"
      key_vault_suffix  = "vault.azure.cn"
      storage_suffix    = "core.chinacloudapi.cn"
      web_app_suffix    = "chinacloudsites.cn"

      azuread_instance = "https://login.chinacloudapi.cn/"

      sql_private_dns         = "privatelink.database.chinacloudapi.cn"
      blob_private_dns        = "privatelink.blob.core.chinacloudapi.cn"
      file_private_dns        = "privatelink.file.core.chinacloudapi.cn"
      app_service_private_dns = "privatelink.chinacloudsites.cn"
      key_vault_private_dns   = "privatelink.vaultcore.azure.cn"
      automation_private_dns  = "privatelink.azure-automation.cn"
    }
  }

  _env = local.cloud_config[var.azure_environment]

  sql_server_suffix = ".${local._env.sql_server_suffix}"
  key_vault_suffix  = ".${local._env.key_vault_suffix}"
  storage_suffix    = ".${local._env.storage_suffix}"
  web_app_suffix    = ".${local._env.web_app_suffix}"

  database_scope = "https://${local._env.sql_server_suffix}"
  web_app_url    = "https://${var.web_app_portal_name}${local.web_app_suffix}/"
  login_url      = "${local.web_app_url}signin-oidc"
  logout_url     = "${local.web_app_url}signout-oidc"

  azuread_instance = local._env.azuread_instance

  sql_private_dns_zone_name         = local._env.sql_private_dns
  blob_private_dns_zone_name        = local._env.blob_private_dns
  file_private_dns_zone_name        = local._env.file_private_dns
  app_service_private_dns_zone_name = local._env.app_service_private_dns
  key_vault_private_dns_zone_name   = local._env.key_vault_private_dns
  automation_private_dns_zone_name  = local._env.automation_private_dns

  private_endpoints_subnet_id = var.configure_private_endpoints ? (var.network_config != null ? azurerm_subnet.private_endpoints[0].id : data.azurerm_subnet.private_endpoints[0].id) : null
  app_subnet_id               = var.configure_private_endpoints ? (var.network_config != null ? azurerm_subnet.app[0].id : data.azurerm_subnet.app[0].id) : null

  arm_api_app_id = {
    AzureCloud        = "797f4846-ba00-4fd7-ba43-dac1f8f63013"
    AzureUSGovernment = "40a69793-8fe6-4db1-9591-dbc5c57b17d8"
  }
  has_arm_api = contains(keys(local.arm_api_app_id), var.azure_environment)

  virtual_network_id                    = var.configure_private_endpoints ? (var.network_config != null ? azurerm_virtual_network.private_endpoints_vnet[0].id : data.azurerm_virtual_network.private_endpoints_vnet[0].id) : null
  virtual_network_name                  = var.configure_private_endpoints ? (var.network_config != null ? azurerm_virtual_network.private_endpoints_vnet[0].name : data.azurerm_virtual_network.private_endpoints_vnet[0].name) : null
  create_dns_zones                      = var.configure_private_endpoints ? (var.network_config != null ? var.network_config.create_dns_zones : var.existing_network_config.create_dns_zones) : false
  link_dns_zones                        = var.configure_private_endpoints ? (var.network_config != null ? var.network_config.link_dns_zones : var.existing_network_config.link_dns_zones) : false
  manage_dns                            = var.configure_private_endpoints ? (var.network_config != null ? var.network_config.manage_dns : var.existing_network_config.manage_dns) : false
  app_service_dns_zone_id               = local.create_dns_zones ? azurerm_private_dns_zone.app_service[0].id : var.existing_network_config.manage_dns ? var.existing_network_config.dns_zone_ids.app_service : null
  automation_dns_zone_id                = local.create_dns_zones ? azurerm_private_dns_zone.automation[0].id : var.existing_network_config.manage_dns ? var.existing_network_config.dns_zone_ids.automation : null
  sql_dns_zone_id                       = local.create_dns_zones ? azurerm_private_dns_zone.sql[0].id : var.existing_network_config.manage_dns ? var.existing_network_config.dns_zone_ids.sql : null
  data_protection_dns_zone_id           = local.create_dns_zones ? azurerm_private_dns_zone.data_protection[0].id : var.existing_network_config.manage_dns ? var.existing_network_config.dns_zone_ids.data_protection : null
  key_vault_dns_zone_id                 = local.create_dns_zones ? azurerm_private_dns_zone.key_vault[0].id : var.existing_network_config.manage_dns ? var.existing_network_config.dns_zone_ids.key_vault : null
  deploy_private_endpoint_managed_dns   = var.configure_private_endpoints && (var.network_config != null || var.existing_network_config.manage_dns)
  deploy_private_endpoint_unmanaged_dns = var.configure_private_endpoints && var.existing_network_config != null && !var.existing_network_config.manage_dns
  private_endpoint_app_service_id       = var.configure_private_endpoints ? local.manage_dns ? azurerm_private_endpoint.web_app[0].id : azurerm_private_endpoint.web_app_unmanaged_dns[0].id : null
  private_endpoint_automation_id        = var.configure_private_endpoints ? local.manage_dns ? azurerm_private_endpoint.automation[0].id : azurerm_private_endpoint.automation_unmanaged_dns[0].id : null
  private_endpoint_sql_server_id        = var.configure_private_endpoints ? local.manage_dns ? azurerm_private_endpoint.sql_server[0].id : azurerm_private_endpoint.sql_server_unmanaged_dns[0].id : null
  private_endpoint_data_protection_id   = var.configure_private_endpoints ? local.manage_dns ? azurerm_private_endpoint.storage_blob[0].id : azurerm_private_endpoint.storage_blob_unmanged_dns[0].id : null
  private_endpoint_key_vault_id         = var.configure_private_endpoints ? local.manage_dns ? azurerm_private_endpoint.key_vault[0].id : azurerm_private_endpoint.key_vault_unmanaged_dns[0].id : null
}
