resource "azurerm_management_lock" "key_vault_lock" {
  count = var.protect_resources ? 1 : 0
  name       = "${var.key_vault_name}-lock"
  scope      = azurerm_key_vault.key_vault.id
  lock_level = "CanNotDelete"
  notes      = "KeyVault should not be deleted."
  depends_on = [ null_resource.health_check ]
}

resource "azurerm_management_lock" "sql_database_lock" {
  count = var.protect_resources ? 1 : 0
  name       = "${var.database_name}-lock"
  scope      = azurerm_mssql_database.database.id
  lock_level = "CanNotDelete"
  notes      = "Database should not be deleted."
  depends_on = [ null_resource.health_check ]
}

resource "azurerm_management_lock" "data_protection_storage_lock" {
  count = var.protect_resources ? 1 : 0
  name       = "${var.data_protection_storage_account_name}-lock"
  scope      = azurerm_storage_account.data_protection.id
  lock_level = "CanNotDelete"
  notes      = "StorageAccount to data protection should not be deleted."
  depends_on = [ null_resource.health_check ]
}