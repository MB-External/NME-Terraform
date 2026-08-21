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

  private_endpoints_subnet_id = var.configure_private_endpoints ? azurerm_subnet.private_endpoints[0].id : null
  app_subnet_id               = var.configure_private_endpoints ? azurerm_subnet.app[0].id : null

  arm_api_app_id = {
    AzureCloud        = "797f4846-ba00-4fd7-ba43-dac1f8f63013"
    AzureUSGovernment = "40a69793-8fe6-4db1-9591-dbc5c57b17d8"
  }
  has_arm_api = contains(keys(local.arm_api_app_id), var.azure_environment)
}
