resource "azurerm_key_vault" "key_vault" {
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  # Allow current deploying principal to manage secrets
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    certificate_permissions = [
       "Delete", "Create", "Get", "List", "Update",
    ]

    key_permissions = [
       "Delete", "Create", "Get", "List", "Purge", "Recover", "Rotate", "GetRotationPolicy", "SetRotationPolicy"
    ]

    secret_permissions = [
      "Delete", "Set", "Get", "List", 
    ]
  }

  # Allow webapp principal to access secrets and keys
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_windows_web_app.web_app_portal.identity[0].principal_id

    key_permissions = [
      "WrapKey",
      "UnwrapKey",
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
    ]
  }

  enabled_for_deployment     = false
  soft_delete_retention_days = 90
  purge_protection_enabled   = false
  rbac_authorization_enabled = false

  public_network_access_enabled = var.configure_private_endpoints ? false : true

  network_acls {
    bypass         = "AzureServices"
    default_action = var.configure_private_endpoints ? "Deny" : "Allow"
  }

  tags = merge(
    {
      NMW_OBJECT_TYPE = "PAAS"
    },
    lookup(
      var.tags_by_resource,
      "Microsoft.KeyVault/vaults",
      {}
    )
  )
}

resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "ConnectionStrings--DefaultConnection"
  key_vault_id = azurerm_key_vault.key_vault.id

  value = "Server=tcp:${var.sql_server_name}${local.sql_server_suffix},1433;Initial Catalog=${var.database_name};Persist Security Info=False;User ID=${azuread_application.nme_app.client_id};Password=${azuread_application_password.nme_app.value};MultipleActiveResultSets=False;Authentication=Active Directory Service Principal;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

  depends_on = [
    azurerm_mssql_database.database,
    azuread_application_password.nme_app,
    null_resource.wait_for_key_vault_private_dns,
  ]
}

resource "azurerm_key_vault_key" "data_protection" {
  name         = var.data_protection_key_name
  key_vault_id = azurerm_key_vault.key_vault.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "wrapKey",
    "unwrapKey",
  ]

  depends_on = [
    null_resource.wait_for_key_vault_private_dns,
  ]
}


# DataProtection--Storage--Path = https://{account}.blob.{suffix}/{container}/keys-{uniqueStr}.xml?{sas}
resource "azurerm_key_vault_secret" "data_protection_storage_path" {
  name         = "DataProtection--Storage--Path"
  key_vault_id = azurerm_key_vault.key_vault.id

  value = "https://${azurerm_storage_account.data_protection.name}.blob${local.storage_suffix}/${azurerm_storage_container.dp_keys.name}/${var.data_protection_keys_blob_name}?${trimprefix(data.azurerm_storage_account_sas.dp_keys_sas.sas, "?")}"

  depends_on = [
    azurerm_storage_container.dp_keys,
    null_resource.wait_for_key_vault_private_dns,
  ]
}

# Deployment--LocksContainerSasUrl = https://{account}.blob.{suffix}/{locks}?{sas}
resource "azurerm_key_vault_secret" "deployment_locks_container_sas_url" {
  name         = "Deployment--LocksContainerSasUrl"
  key_vault_id = azurerm_key_vault.key_vault.id

  value = "https://${azurerm_storage_account.data_protection.name}.blob${local.storage_suffix}/${azurerm_storage_container.dp_locks.name}?${trimprefix(data.azurerm_storage_account_sas.dp_locks_sas.sas, "?")}"

  depends_on = [
    azurerm_storage_container.dp_locks,
    null_resource.wait_for_key_vault_private_dns,
  ]
}

resource "azurerm_private_dns_zone" "key_vault" {
  count               = var.configure_private_endpoints ? 1 : 0
  name                = local.key_vault_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones", {})
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count                 = var.configure_private_endpoints ? 1 : 0
  name                  = "${var.network_config.vnet_name}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = azurerm_virtual_network.private_endpoints_vnet[0].id
  tags                  = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {})
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault_deployment" {
  count               = var.configure_private_endpoints && var.deployment_vnet_name != null ? 1 : 0
  name                = "${var.deployment_vnet_name}-deployment-link"
  resource_group_name = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = data.azurerm_virtual_network.deployment_vnet[0].id
  tags                  = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {})
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "key_vault" {
  count               = var.configure_private_endpoints ? 1 : 0
  name                = "${var.key_vault_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {})

  private_service_connection {
    name                           = "${var.key_vault_name}-pls"
    private_connection_resource_id = azurerm_key_vault.key_vault.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault[0].id]
  }
}
