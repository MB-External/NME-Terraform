resource "azurerm_key_vault" "key_vault" {
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  enabled_for_deployment     = false
  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  rbac_authorization_enabled = true

  public_network_access_enabled = var.configure_private_endpoints ? false : true

  network_acls {
    bypass         = "AzureServices"
    default_action = var.configure_private_endpoints ? "Deny" : "Allow"
  }

  tags = merge(var.tags,
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

# Allow deploying principal(s) to create the data protection key and secrets (data plane).
resource "azurerm_role_assignment" "key_vault_deployer_crypto_officer" {
  for_each             = local.read_write_deployment_principal_ids
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "key_vault_deployer_secrets_officer" {
  for_each             = local.read_write_deployment_principal_ids
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "key_vault_deployer_certificates_officer" {
  for_each             = local.read_write_deployment_principal_ids
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "key_vault_reader" {
  for_each             = local.read_only_deployment_principal_ids
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Reader"
  principal_id         = each.value
}

# Allow webapp principal to access secrets, keys, and certificates (data plane).
resource "azurerm_role_assignment" "key_vault_webapp_secrets_officer" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_windows_web_app.web_app_portal.identity[0].principal_id
}

resource "azurerm_role_assignment" "key_vault_webapp_crypto_user" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_windows_web_app.web_app_portal.identity[0].principal_id
}

resource "azurerm_role_assignment" "key_vault_webapp_certificate_user" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = azurerm_windows_web_app.web_app_portal.identity[0].principal_id
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
    azurerm_role_assignment.key_vault_deployer_crypto_officer,
    null_resource.wait_for_key_vault_private_dns,
  ]
}


# DataProtection--Storage--Path = https://{account}.blob.{suffix}/{container}/keys-{uniqueStr}.xml?{sas}
resource "azurerm_key_vault_secret" "data_protection_storage_path" {
  name         = "DataProtection--Storage--Path"
  key_vault_id = azurerm_key_vault.key_vault.id

  value = "https://${azurerm_storage_account.data_protection.name}.blob${local.storage_suffix}/${azurerm_storage_container.dp_keys.name}/${var.data_protection_keys_blob_name}?${trimprefix(data.azurerm_storage_account_sas.dp_keys_sas.sas, "?")}"

  depends_on = [
    azurerm_role_assignment.key_vault_deployer_secrets_officer,
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
    azurerm_role_assignment.key_vault_deployer_secrets_officer,
    azurerm_storage_container.dp_locks,
    null_resource.wait_for_key_vault_private_dns,
  ]
}

resource "azurerm_private_dns_zone" "key_vault" {
  count               = local.create_dns_zones ? 1 : 0
  name                = local.key_vault_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones", {}))
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count                = local.link_dns_zones ? 1 : 0
  name                 = "${local.virtual_network_name}-link"
  private_dns_zone_id  = local.key_vault_dns_zone_id
  virtual_network_id   = local.virtual_network_id
  tags                 = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {}))
  registration_enabled = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault_deployment" {
  count                = local.link_dns_zones && var.deployment_vnet_name != null ? 1 : 0
  name                 = "${var.deployment_vnet_name}-deployment-link"
  private_dns_zone_id  = local.key_vault_dns_zone_id
  virtual_network_id   = data.azurerm_virtual_network.deployment_vnet[0].id
  tags                 = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {}))
  registration_enabled = false
}

resource "azurerm_private_endpoint" "key_vault" {
  count               = local.deploy_private_endpoint_managed_dns ? 1 : 0
  name                = "${var.key_vault_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.key_vault_name}-pls"
    private_connection_resource_id = azurerm_key_vault.key_vault.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.key_vault_dns_zone_id]
  }
}

resource "azurerm_private_endpoint" "key_vault_unmanaged_dns" {
  count               = local.deploy_private_endpoint_unmanaged_dns ? 1 : 0
  name                = "${var.key_vault_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.key_vault_name}-pls"
    private_connection_resource_id = azurerm_key_vault.key_vault.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}
