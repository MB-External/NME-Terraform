locals {
  data_protection_storage_blob_container = "dataprotectionkeys"
  blob_lease_container                   = "locks"

  # From Bicep: contains(unpairedRegions, toLower(location)) ? 'Standard_ZRS' : 'Standard_GRS'
  unpaired_regions = toset([
    "austriaeast",
    "belgiumcentral",
    "chilecentral",
    "indonesiacentral",
    "israelcentral",
    "italynorth",
    "malaysiawest",
    "mexicocentral",
    "newzealandnorth",
    "polandcentral",
    "qatarcentral",
    "spaincentral",
  ])

  storage_replication_type = contains(local.unpaired_regions, lower(var.location)) ? "ZRS" : "GRS"
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

  infrastructure_encryption_enabled = false

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = lookup(
    var.tags_by_resource,
    "Microsoft.Storage/storageAccounts",
    {}
  )
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

resource "azurerm_private_dns_zone" "data_protection" {
  count               = var.configure_private_endpoints ? 1 : 0
  name                = local.blob_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones", {})
}

resource "azurerm_private_dns_zone_virtual_network_link" "data_protection" {
  count                = var.configure_private_endpoints ? 1 : 0
  name                 = "${var.network_config.vnet_name}-link"
  private_dns_zone_id  = azurerm_private_dns_zone.data_protection[0].id
  virtual_network_id   = azurerm_virtual_network.private_endpoints_vnet[0].id
  tags                 = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {})
  registration_enabled = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "data_protection_deployment" {
  count                = var.configure_private_endpoints && var.deployment_vnet_name != null ? 1 : 0
  name                 = "${var.deployment_vnet_name}-deployment-link"
  private_dns_zone_id  = azurerm_private_dns_zone.data_protection[0].id
  virtual_network_id   = data.azurerm_virtual_network.deployment_vnet[0].id
  tags                 = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {})
  registration_enabled = false
}

resource "azurerm_private_endpoint" "storage_blob" {
  count               = var.configure_private_endpoints ? 1 : 0
  name                = "${azurerm_storage_account.data_protection.name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {})

  private_service_connection {
    name                           = "${var.data_protection_storage_account_name}-blob-pls"
    private_connection_resource_id = azurerm_storage_account.data_protection.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.data_protection[0].id]
  }
}
