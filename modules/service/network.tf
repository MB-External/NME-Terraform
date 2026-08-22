
resource "azurerm_virtual_network" "private_endpoints_vnet" {
  count               = var.configure_private_endpoints && var.network_config != null ? 1 : 0
  name                = var.network_config.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name

  address_space = [var.network_config.vnet_cidr]
  tags = merge(var.tags,
    lookup(
      var.tags_by_resource,
      "Microsoft.Network/virtualNetworks",
      {}
    )
  )
}

data "azurerm_virtual_network" "private_endpoints_vnet" {
  count               = var.configure_private_endpoints && var.existing_network_config != null ? 1 : 0
  name                = var.existing_network_config.vnet_name
  resource_group_name = var.existing_network_config.resource_group_name
}

resource "azurerm_subnet" "private_endpoints" {
  count                = var.configure_private_endpoints && var.network_config != null ? 1 : 0
  name                 = var.network_config.pe_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.private_endpoints_vnet[0].name

  address_prefixes                  = [var.network_config.pe_subnet_cidr]
  private_endpoint_network_policies = "RouteTableEnabled"
}

data "azurerm_subnet" "private_endpoints" {
  count                = var.configure_private_endpoints && var.existing_network_config != null ? 1 : 0
  name                 = var.existing_network_config.pe_subnet_name
  resource_group_name  = var.existing_network_config.resource_group_name
  virtual_network_name = var.existing_network_config.vnet_name
}
resource "azurerm_subnet" "app" {
  count                = var.configure_private_endpoints && var.network_config != null ? 1 : 0
  name                 = var.network_config.app_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.private_endpoints_vnet[0].name

  address_prefixes = [var.network_config.app_subnet_cidr]
  delegation {
    name = "serverFarmsDelegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
  service_endpoint {
    service = "Microsoft.KeyVault"
  }
  private_endpoint_network_policies = "RouteTableEnabled"
}
data "azurerm_subnet" "app" {
  count                = var.configure_private_endpoints && var.existing_network_config != null ? 1 : 0
  name                 = var.existing_network_config.app_subnet_name
  resource_group_name  = var.existing_network_config.resource_group_name
  virtual_network_name = var.existing_network_config.vnet_name
}

data "azurerm_virtual_network" "deployment_vnet" {
  count               = var.configure_private_endpoints && var.deployment_vnet_name != null ? 1 : 0
  name                = var.deployment_vnet_name
  resource_group_name = var.deployment_resource_group_name
}

resource "azurerm_virtual_network_peering" "deployment_to_private" {
  count                        = var.configure_private_endpoints && var.deployment_vnet_name != null ? 1 : 0
  name                         = "deployment-to-private-${local.virtual_network_name}"
  resource_group_name          = var.deployment_resource_group_name
  virtual_network_name         = data.azurerm_virtual_network.deployment_vnet[0].name
  remote_virtual_network_id    = local.virtual_network_id
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "private_to_deployment" {
  count                        = var.configure_private_endpoints && var.deployment_vnet_name != null ? 1 : 0
  name                         = "private-to-deployment-${local.virtual_network_name}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = local.virtual_network_name
  remote_virtual_network_id    = data.azurerm_virtual_network.deployment_vnet[0].id
  allow_virtual_network_access = true
}
