resource "azurerm_storage_account" "custom_scripts" {
  name                = var.custom_scripts_storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = local.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  shared_access_key_enabled        = true
  https_traffic_only_enabled       = true

  public_network_access_enabled = var.configure_private_endpoints ? false : true

  infrastructure_encryption_enabled = true
  queue_encryption_key_type         = "Account"
  table_encryption_key_type         = "Account"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.custom_scripts.id]
  }
  customer_managed_key {
    user_assigned_identity_id = azurerm_user_assigned_identity.custom_scripts.id
    key_vault_key_id          = azurerm_key_vault_key.custom_scripts_cmk.versionless_id
  }

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = merge(var.tags,
    lookup(
      var.tags_by_resource,
      "Microsoft.Storage/storageAccounts",
      {}
    ),
    {
      NMW_OBJECT_TYPE = "CUSTOM_SCRIPTS_STORAGE_ACCOUNT"
    }
  )
  depends_on = [
    azurerm_role_assignment.custom_scripts_cmk,
    azurerm_network_security_perimeter_access_rule.subscription,
    azurerm_network_security_perimeter_association.key_vault,
  ]
  lifecycle {
    # Ignore changes to encryption settings to avoid recreation of the storage account
    ignore_changes = [
      queue_encryption_key_type,
      table_encryption_key_type,
      infrastructure_encryption_enabled,
    ]
  }
}

resource "azurerm_private_endpoint" "custom_scripts_storage_blob" {
  count               = local.deploy_private_endpoint_managed_dns ? 1 : 0
  name                = "${azurerm_storage_account.custom_scripts.name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.custom_scripts_storage_account_name}-blob-pls"
    private_connection_resource_id = azurerm_storage_account.custom_scripts.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_private_dns_zone_id]
  }
}

resource "azurerm_private_endpoint" "custom_scripts_storage_blob_unmanaged_dns" {
  count               = local.deploy_private_endpoint_unmanaged_dns ? 1 : 0
  name                = "${azurerm_storage_account.custom_scripts.name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.custom_scripts_storage_account_name}-blob-pls"
    private_connection_resource_id = azurerm_storage_account.custom_scripts.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_role_assignment" "custom_scripts_cmk" {
  role_definition_name = "Key Vault Crypto Service Encryption User"
  scope                = azurerm_key_vault_key.data_protection_cmk.resource_versionless_id
  principal_id         = azurerm_user_assigned_identity.data_protection.principal_id
}

resource "azurerm_user_assigned_identity" "custom_scripts" {
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = "${var.custom_scripts_storage_account_name}-uai"
}
resource "time_offset" "custom_scripts_cmk" {
  offset_months = 18
}

resource "azurerm_key_vault_key" "custom_scripts_cmk" {
  name         = "${var.custom_scripts_storage_account_name}-cmk"
  key_vault_id = azurerm_key_vault.key_vault.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "unwrapKey",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_after_creation = "P12M"
    }
    expire_after         = "P18M"
    notify_before_expiry = "P1M"
  }
  expiration_date = time_offset.custom_scripts_cmk.rfc3339
  lifecycle {
    ignore_changes = [
      expiration_date
    ]
  }
  depends_on = [
    azurerm_role_assignment.key_vault_deployer_crypto_officer,
    null_resource.wait_for_key_vault_private_dns,
  ]
}
