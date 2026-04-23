# Web App outputs
output "web_app_id" {
  description = "The ID of the Windows Web App"
  value       = azurerm_windows_web_app.web_app_portal.id
}

output "web_app_name" {
  description = "The name of the Windows Web App"
  value       = azurerm_windows_web_app.web_app_portal.name
}

output "web_app_default_hostname" {
  description = "The default hostname of the Windows Web App"
  value       = azurerm_windows_web_app.web_app_portal.default_hostname
}

output "web_app_identity_principal_id" {
  description = "The Principal ID of the Windows Web App's managed identity"
  value       = azurerm_windows_web_app.web_app_portal.identity[0].principal_id
}

output "web_app_identity_tenant_id" {
  description = "The Tenant ID of the Windows Web App's managed identity"
  value       = azurerm_windows_web_app.web_app_portal.identity[0].tenant_id
}

# App Service Plan outputs
output "app_service_plan_id" {
  description = "The ID of the App Service Plan"
  value       = azurerm_service_plan.app_service_plan.id
}

output "app_service_plan_name" {
  description = "The name of the App Service Plan"
  value       = azurerm_service_plan.app_service_plan.name
}

# SQL Server outputs
output "sql_server_id" {
  description = "The ID of the SQL Server"
  value       = azurerm_mssql_server.sql_server.id
}

output "sql_server_name" {
  description = "The name of the SQL Server"
  value       = azurerm_mssql_server.sql_server.name
}

output "sql_server_fqdn" {
  description = "The fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.sql_server.fully_qualified_domain_name
}

# SQL Database outputs
output "sql_database_id" {
  description = "The ID of the SQL Database"
  value       = azurerm_mssql_database.database.id
}

output "sql_database_name" {
  description = "The name of the SQL Database"
  value       = azurerm_mssql_database.database.name
}

# Key Vault outputs
output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.key_vault.id
}

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.key_vault.name
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.key_vault.vault_uri
}

# Storage Account outputs
output "storage_account_id" {
  description = "The ID of the Data Protection Storage Account"
  value       = azurerm_storage_account.data_protection.id
}

output "storage_account_name" {
  description = "The name of the Data Protection Storage Account"
  value       = azurerm_storage_account.data_protection.name
}

output "storage_account_primary_blob_endpoint" {
  description = "The primary blob endpoint of the Data Protection Storage Account"
  value       = azurerm_storage_account.data_protection.primary_blob_endpoint
}

# Application Insights outputs
output "app_insights_id" {
  description = "The ID of Application Insights"
  value       = azurerm_application_insights.app_insights.id
}

output "app_insights_name" {
  description = "The name of Application Insights"
  value       = azurerm_application_insights.app_insights.name
}

output "app_insights_connection_string" {
  description = "The connection string of Application Insights"
  value       = azurerm_application_insights.app_insights.connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "The instrumentation key of Application Insights"
  value       = azurerm_application_insights.app_insights.instrumentation_key
  sensitive   = true
}

output "app_insights_app_id" {
  description = "The App ID of Application Insights"
  value       = azurerm_application_insights.app_insights.app_id
}

# Log Analytics Workspace outputs
output "law_id" {
  description = "The ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.id
}

output "law_name" {
  description = "The name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.name
}

output "law_workspace_id" {
  description = "The Workspace ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.workspace_id
}

output "logs_law_id" {
  description = "The ID of the Logs Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.logs_law.id
}

output "logs_law_name" {
  description = "The name of the Logs Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.logs_law.name
}

output "logs_law_workspace_id" {
  description = "The Workspace ID of the Logs Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.logs_law.workspace_id
}

# Automation Account outputs
output "automation_account_id" {
  description = "The ID of the Automation Account"
  value       = azurerm_automation_account.automation.id
}

output "automation_account_name" {
  description = "The name of the Automation Account"
  value       = azurerm_automation_account.automation.name
}

output "automation_account_identity_principal_id" {
  description = "The Principal ID of the Automation Account's managed identity"
  value       = azurerm_automation_account.automation.identity[0].principal_id
}

output "scripted_action_account_id" {
  description = "The ID of the Scripted Action Automation Account"
  value       = azurerm_automation_account.scripted_action.id
}

output "scripted_action_account_name" {
  description = "The name of the Scripted Action Automation Account"
  value       = azurerm_automation_account.scripted_action.name
}

# Network outputs (conditional based on private endpoints)
output "private_endpoints_vnet_id" {
  description = "The ID of the Private Endpoints Virtual Network"
  value       = var.configure_private_endpoints ? azurerm_virtual_network.private_endpoints_vnet[0].id : null
}

output "private_endpoints_vnet_name" {
  description = "The name of the Private Endpoints Virtual Network"
  value       = var.configure_private_endpoints ? azurerm_virtual_network.private_endpoints_vnet[0].name : null
}

output "private_endpoints_subnet_id" {
  description = "The ID of the Private Endpoints Subnet"
  value       = var.configure_private_endpoints ? azurerm_subnet.private_endpoints[0].id : null
}

output "app_subnet_id" {
  description = "The ID of the App Subnet"
  value       = var.configure_private_endpoints ? azurerm_subnet.app[0].id : null
}

# Data Collection outputs
output "data_collection_endpoint_id" {
  description = "The ID of the Data Collection Endpoint"
  value       = azurerm_monitor_data_collection_endpoint.dce.id
}

output "data_collection_rule_id" {
  description = "The ID of the Data Collection Rule"
  value       = azurerm_monitor_data_collection_rule.dcr.id
}

# Resource Group output (for reference)
output "resource_group_name" {
  description = "The name of the Resource Group"
  value       = var.resource_group_name
}

output "location" {
  description = "The Azure location where resources are deployed"
  value       = var.location
}

# Azure AD Application outputs
output "azuread_app_client_id" {
  description = "The Client ID (Application ID) of the NME Azure AD application"
  value       = azuread_application.nme_app.client_id
}

output "azuread_app_object_id" {
  description = "The Object ID of the NME Azure AD application"
  value       = azuread_application.nme_app.object_id
}

output "azuread_service_principal_id" {
  description = "The Object ID of the NME service principal"
  value       = azuread_service_principal.nme_app.object_id
}
