locals {
  data_protection_storage_blob_container = "dataprotectionkeys"
  blob_lease_container                   = "locks"
}

# SAS tokens (Terraform equivalent of listServiceSas)
# We generate an *account SAS* limited to the blob service + container/object resource types and rcw permissions.
data "azurerm_storage_account_sas" "dp_keys_sas" {
  connection_string = azurerm_storage_account.data_protection.primary_connection_string

  https_only = true

  start  = "2020-01-01T00:00:00Z"
  expiry = "2050-01-01T00:00:00Z"

  services {
    blob  = true
    file  = false
    queue = false
    table = false
  }

  resource_types {
    service   = false
    container = true
    object    = true
  }

  permissions {
    read    = true
    create  = true
    write   = true
    delete  = false
    list    = false
    add     = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

data "azurerm_storage_account_sas" "dp_locks_sas" {
  connection_string = azurerm_storage_account.data_protection.primary_connection_string

  https_only = true

  start  = "2020-01-01T00:00:00Z"
  expiry = "2050-01-01T00:00:00Z"

  services {
    blob  = true
    file  = false
    queue = false
    table = false
  }

  resource_types {
    service   = false
    container = true
    object    = true
  }

  permissions {
    read    = true
    create  = true
    write   = true
    delete  = false
    list    = false
    add     = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

resource "azurerm_storage_account" "data_protection" {
  name                = var.data_protection_storage_account_name
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
    identity_ids = [azurerm_user_assigned_identity.data_protection.id]
  }
  customer_managed_key {
    user_assigned_identity_id = azurerm_user_assigned_identity.data_protection.id
    key_vault_key_id          = azurerm_key_vault_key.data_protection_cmk.versionless_id
  }

  dynamic "network_rules" {
    for_each = var.configure_private_endpoints ? [0] : [1]
    content {
      default_action = "Allow"
      bypass         = ["AzureServices"]
    }
  }

  tags = merge(var.tags,
    lookup(
      var.tags_by_resource,
      "Microsoft.Storage/storageAccounts",
      {}
    )
  )
  depends_on = [
    azurerm_role_assignment.data_protection_cmk,
    time_sleep.wait_key_vault_nsp_association,
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

resource "azurerm_storage_container" "dp_keys" {
  name                  = local.data_protection_storage_blob_container
  storage_account_id    = azurerm_storage_account.data_protection.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "dp_locks" {
  name                  = local.blob_lease_container
  storage_account_id    = azurerm_storage_account.data_protection.id
  container_access_type = "private"
}

resource "azurerm_private_dns_zone" "blob" {
  count               = local.create_dns_zones ? 1 : 0
  name                = local.blob_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones", {}))
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                = local.link_dns_zones ? 1 : 0
  name                 = "${local.virtual_network_name}-link"
  private_dns_zone_id  = local.blob_private_dns_zone_id
  virtual_network_id   = local.virtual_network_id
  tags                 = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {}))
  registration_enabled = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "data_protection_deployment" {
  count                = local.link_dns_zones && var.deployment_vnet_name != null ? 1 : 0
  name                 = "${var.deployment_vnet_name}-deployment-link"
  private_dns_zone_id  = local.blob_private_dns_zone_id
  virtual_network_id   = data.azurerm_virtual_network.deployment_vnet[0].id
  tags                 = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {}))
  registration_enabled = false
}
moved {
  from = azurerm_private_endpoint.storage_blob
  to   = azurerm_private_endpoint.data_protection_storage_blob
}
resource "azurerm_private_endpoint" "data_protection_storage_blob" {
  count               = local.deploy_private_endpoint_managed_dns ? 1 : 0
  name                = "${azurerm_storage_account.data_protection.name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.data_protection_storage_account_name}-blob-pls"
    private_connection_resource_id = azurerm_storage_account.data_protection.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_private_dns_zone_id]
  }
}
moved {
  from = azurerm_private_endpoint.storage_blob_unmanged_dns
  to   = azurerm_private_endpoint.data_protection_storage_blob_unmanaged_dns
}
resource "azurerm_private_endpoint" "data_protection_storage_blob_unmanaged_dns" {
  count               = local.deploy_private_endpoint_unmanaged_dns ? 1 : 0
  name                = "${azurerm_storage_account.data_protection.name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.data_protection_storage_account_name}-blob-pls"
    private_connection_resource_id = azurerm_storage_account.data_protection.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_role_assignment" "data_protection_cmk" {
  role_definition_name = "Key Vault Crypto Service Encryption User"
  scope                = azurerm_key_vault_key.data_protection_cmk.resource_versionless_id
  principal_id         = azurerm_user_assigned_identity.data_protection.principal_id
}

resource "azurerm_user_assigned_identity" "data_protection" {
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = "${var.data_protection_storage_account_name}-uai"
}
resource "time_offset" "storage_account_encryption" {
  offset_months = 18
}

resource "azurerm_key_vault_key" "data_protection_cmk" {
  name         = "${var.data_protection_storage_account_name}-cmk"
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
  expiration_date = time_offset.storage_account_encryption.rfc3339
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
