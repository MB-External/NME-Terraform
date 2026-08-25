resource "azurerm_automation_account" "scripted_action" {
  name                          = var.scripted_action_account_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  public_network_access_enabled = false

  sku_name = "Basic"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.scripted_action.id]
  }
  encryption {
    key_vault_key_id          = azurerm_key_vault_key.scripted_action_cmk.versionless_id
    user_assigned_identity_id = azurerm_user_assigned_identity.scripted_action.id
  }

  tags = merge(var.tags,
    lookup(
      var.tags_by_resource,
      "Microsoft.Automation/automationAccounts",
      {}
    )
  )
  depends_on = [
    azurerm_role_assignment.scripted_action_cmk,
    azurerm_network_security_perimeter_association.key_vault,
  ]
}

resource "azurerm_automation_account" "automation" {
  name                          = var.automation_account_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  public_network_access_enabled = !var.configure_private_endpoints

  sku_name = "Basic"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.automation.id]
  }
  encryption {
    key_vault_key_id          = azurerm_key_vault_key.automation_cmk.versionless_id
    user_assigned_identity_id = azurerm_user_assigned_identity.automation.id
  }

  tags = merge(var.tags,
    lookup(
      var.tags_by_resource,
      "Microsoft.Automation/automationAccounts",
      {}
    )
  )
  depends_on = [
    azurerm_role_assignment.automation_cmk,
    azurerm_network_security_perimeter_association.key_vault,
  ]
}

data "azurerm_key_vault_secret" "scripted_action_cert" {
  name         = azurerm_key_vault_certificate.scripted_action_cert.name
  key_vault_id = azurerm_key_vault.key_vault.id

  depends_on = [
    null_resource.wait_for_key_vault_private_dns,
  ]
}

resource "azurerm_automation_certificate" "scripted_action" {
  name                    = "ScriptedActionRunAsCert"
  automation_account_name = azurerm_automation_account.scripted_action.name
  resource_group_name     = var.resource_group_name
  base64                  = data.azurerm_key_vault_secret.scripted_action_cert.value
  exportable              = true
}

resource "azurerm_automation_variable_string" "subscription_id" {
  name                    = "subscriptionId"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.automation.name

  value       = data.azurerm_client_config.current.subscription_id
  encrypted   = true
  description = "Azure Subscription Id"
}

resource "azurerm_automation_variable_string" "web_app_name" {
  name                    = "webAppName"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.automation.name

  value       = var.web_app_portal_name
  encrypted   = true
  description = "Web App Name"
}

resource "azurerm_automation_variable_string" "resource_group_name" {
  name                    = "resourceGroupName"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.automation.name

  value       = var.resource_group_name
  encrypted   = true
  description = "Resource group"
}

resource "azurerm_role_assignment" "automation_contributor" {
  scope = azurerm_windows_web_app.web_app_portal.id

  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.automation.principal_id
}

resource "azurerm_private_dns_zone" "automation" {
  count               = local.create_dns_zones ? 1 : 0
  name                = local.automation_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones", {}))
}

resource "azurerm_private_dns_zone_virtual_network_link" "automation" {
  count                = local.link_dns_zones ? 1 : 0
  name                 = "${local.virtual_network_name}-link"
  private_dns_zone_id  = local.automation_dns_zone_id
  virtual_network_id   = local.virtual_network_id
  tags                 = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {}))
  registration_enabled = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "automation_deployment" {
  count                = local.link_dns_zones && var.deployment_vnet_name != null ? 1 : 0
  name                 = "${var.deployment_vnet_name}-deployment-link"
  private_dns_zone_id  = local.automation_dns_zone_id
  virtual_network_id   = data.azurerm_virtual_network.deployment_vnet[0].id
  tags                 = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {}))
  registration_enabled = false
}

resource "azurerm_private_endpoint" "automation" {
  count               = local.deploy_private_endpoint_managed_dns ? 1 : 0
  name                = "${var.automation_account_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.scripted_action_account_name}-pls"
    private_connection_resource_id = azurerm_automation_account.scripted_action.id
    is_manual_connection           = false
    subresource_names              = ["Webhook"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.automation_dns_zone_id]
  }
}

resource "azurerm_private_endpoint" "automation_unmanaged_dns" {
  count               = local.deploy_private_endpoint_unmanaged_dns ? 1 : 0
  name                = "${var.automation_account_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.scripted_action_account_name}-pls"
    private_connection_resource_id = azurerm_automation_account.scripted_action.id
    is_manual_connection           = false
    subresource_names              = ["Webhook"]
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_role_assignment" "automation_cmk" {
  role_definition_name = "Key Vault Crypto Service Encryption User"
  scope                = azurerm_key_vault_key.automation_cmk.resource_versionless_id
  principal_id         = azurerm_user_assigned_identity.automation.principal_id
}

resource "azurerm_user_assigned_identity" "automation" {
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = "${var.automation_account_name}-uai"
}
resource "time_offset" "automation_encryption" {
  offset_months = 18
}

resource "azurerm_key_vault_key" "automation_cmk" {
  name         = "${var.automation_account_name}-cmk"
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
  expiration_date = time_offset.automation_encryption.rfc3339
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

resource "azurerm_role_assignment" "scripted_action_cmk" {
  role_definition_name = "Key Vault Crypto Service Encryption User"
  scope                = azurerm_key_vault_key.scripted_action_cmk.resource_versionless_id
  principal_id         = azurerm_user_assigned_identity.scripted_action.principal_id
}

resource "azurerm_user_assigned_identity" "scripted_action" {
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = "${var.scripted_action_account_name}-uai"
}
resource "time_offset" "scripted_action_encryption" {
  offset_months = 18
}

resource "azurerm_key_vault_key" "scripted_action_cmk" {
  name         = "${var.scripted_action_account_name}-cmk"
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
  expiration_date = time_offset.scripted_action_encryption.rfc3339
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
