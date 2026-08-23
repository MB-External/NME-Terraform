data "azuread_service_principal" "current" {
  count     = var.sql_azuread_administrator == null ? 1 : 0
  client_id = data.azurerm_client_config.current.client_id
}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
}
removed {
  from = azuread_service_principal.msgraph
  # Previous versions of the module used a resource to access the Graph service principal,
  # however this isn't needed as it is only used for read access, and doing so can be 
  # destructive as it will attempt to delete the SP on destroy
  lifecycle {
    destroy = false
  }
}

data "azurerm_user_assigned_identity" "sql_server_primary" {
  count               = var.sql_server_identity.primary_user_assigned_identity_id == null ? 0 : 1
  name                = provider::azurerm::parse_resource_id(var.sql_server_identity.primary_user_assigned_identity_id)["resource_name"]
  resource_group_name = provider::azurerm::parse_resource_id(var.sql_server_identity.primary_user_assigned_identity_id)["resource_group_name"]
}

# Grant Directory.Read.All to SQL Server's Managed Identity
resource "azuread_app_role_assignment" "sql_directory_read_all" {
  count               = var.sql_server_identity.create_role_assignment ? 1 : 0
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids["Directory.Read.All"]
  principal_object_id = var.sql_server_identity.primary_user_assigned_identity_id == null ? azurerm_mssql_server.sql_server.identity[0].principal_id : data.azurerm_user_assigned_identity.sql_server_primary[0].principal_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
moved {
  from = azuread_app_role_assignment.sql_directory_read_all
  to   = azuread_app_role_assignment.sql_directory_read_all[0]
}

resource "azurerm_mssql_server" "sql_server" {
  name                          = var.sql_server_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = var.configure_private_endpoints ? false : true

  azuread_administrator {
    login_username              = var.sql_azuread_administrator == null ? data.azuread_service_principal.current[0].display_name : var.sql_azuread_administrator.login_username
    object_id                   = var.sql_azuread_administrator == null ? data.azuread_service_principal.current[0].client_id : var.sql_azuread_administrator.object_id
    tenant_id                   = var.sql_azuread_administrator == null ? data.azurerm_client_config.current.tenant_id : var.sql_azuread_administrator.tenant_id
    azuread_authentication_only = true
  }

  identity {
    type         = var.sql_server_identity.type
    identity_ids = var.sql_server_identity.identity_ids == [] ? null : var.sql_server_identity.identity_ids
  }
  primary_user_assigned_identity_id = var.sql_server_identity.primary_user_assigned_identity_id

  tags = merge(var.tags,
    {
      displayName = "SqlServer"
    },
    lookup(
      var.tags_by_resource,
      "Microsoft.Sql/servers",
      {}
    )
  )
}

resource "azurerm_mssql_database" "database" {
  name        = var.database_name
  server_id   = azurerm_mssql_server.sql_server.id
  collation   = var.sql_collation
  max_size_gb = var.database_max_size_gb

  sku_name       = var.database_sku_name
  zone_redundant = var.enable_zone_redundancy
  license_type = var.database_license_type

  tags = merge(var.tags,
    {
      displayName     = "Database"
      NMW_OBJECT_TYPE = "PAAS"
    },
    lookup(
      var.tags_by_resource,
      "Microsoft.Sql/servers/databases",
      {}
    )
  )
}

resource "azurerm_mssql_firewall_rule" "allow_azure_ips" {
  count = var.configure_private_endpoints ? 0 : 1

  name      = "AllowAllWindowsAzureIps"
  server_id = azurerm_mssql_server.sql_server.id

  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

data "http" "deployer_ip" {
  count = var.configure_private_endpoints ? 0 : 1
  url   = "https://api.ipify.org"
}

resource "azurerm_mssql_firewall_rule" "allow_deployer_ip" {
  count = var.configure_private_endpoints ? 0 : 1

  name      = "AllowDeployerIP"
  server_id = azurerm_mssql_server.sql_server.id

  start_ip_address = trimspace(data.http.deployer_ip[0].response_body)
  end_ip_address   = trimspace(data.http.deployer_ip[0].response_body)
}

resource "azurerm_private_dns_zone" "sql" {
  count               = local.create_dns_zones ? 1 : 0
  name                = local.sql_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones", {}))
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  count                = local.link_dns_zones ? 1 : 0
  name                 = "${local.virtual_network_name}-link"
  private_dns_zone_id  = azurerm_private_dns_zone.sql[0].id
  virtual_network_id   = local.virtual_network_id
  tags                 = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {}))
  registration_enabled = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_deployment" {
  count                = local.link_dns_zones && var.deployment_vnet_name != null ? 1 : 0
  name                 = "${var.deployment_vnet_name}-deployment-link"
  private_dns_zone_id  = azurerm_private_dns_zone.sql[0].id
  virtual_network_id   = data.azurerm_virtual_network.deployment_vnet[0].id
  tags                 = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {}))
  registration_enabled = false
}

resource "azurerm_private_endpoint" "sql_server" {
  count               = local.deploy_private_endpoint_managed_dns ? 1 : 0
  name                = "${var.sql_server_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.sql_server_name}-pls"
    private_connection_resource_id = azurerm_mssql_server.sql_server.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.sql_dns_zone_id]
  }
}

resource "azurerm_private_endpoint" "sql_server_unmanaged_dns" {
  count               = local.deploy_private_endpoint_unmanaged_dns ? 1 : 0
  name                = "${var.sql_server_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = merge(var.tags, lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {}))

  private_service_connection {
    name                           = "${var.sql_server_name}-pls"
    private_connection_resource_id = azurerm_mssql_server.sql_server.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "null_resource" "sql_user_setup" {
  triggers = {
    sp_id      = azuread_service_principal.nme_app.object_id
    sp_name    = azuread_service_principal.nme_app.display_name
    sql_server = azurerm_mssql_server.sql_server.fully_qualified_domain_name
    database   = azurerm_mssql_database.database.name
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'

      $spName = '${azuread_service_principal.nme_app.display_name}'
      if ($spName.Contains('[') -or $spName.Contains(']') -or $spName.Contains("'")) {
        throw "Service Principal name contains invalid characters"
      }

      $miName = '${var.web_app_portal_name}'
      if ($miName.Contains('[') -or $miName.Contains(']') -or $miName.Contains("'")) {
        throw "Web App name contains invalid characters"
      }

      # Ensure Invoke-Sqlcmd is available (provided by the SqlServer module)
      if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
        Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
      }

      # Authenticate to Azure using ARM env vars
      . '${path.module}/scripts/connect-azure.ps1' -Environment '${var.azure_environment}' -SubscriptionId '${data.azurerm_client_config.current.subscription_id}'

      # Get token for database scope
      if (-not (Get-Command Get-AzAccessToken).Parameters.AsSecureString) {
          $sqlToken = (Get-AzAccessToken -ResourceUrl '${local.database_scope}').Token
      } else {
          $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Get-AzAccessToken -AsSecureString -ResourceUrl '${local.database_scope}').Token)
          try { $sqlToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
      }

      $query = @"
      IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$spName')
      BEGIN
        CREATE USER [$spName] FROM EXTERNAL PROVIDER;
      END
      ALTER ROLE db_ddladmin ADD MEMBER [$spName];
      ALTER ROLE db_datareader ADD MEMBER [$spName];
      ALTER ROLE db_datawriter ADD MEMBER [$spName];
      "@

      Invoke-Sqlcmd -ConnectionString "Data Source=tcp:${azurerm_mssql_server.sql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.database.name};Persist Security Info=False;Multiple Active Result Sets=False;Connect Timeout=30;Encrypt=True;Trust Server Certificate=False" -AccessToken $sqlToken -Query $query

      Write-Host "SQL user setup completed for '$spName'"

      # Create SQL user for web app managed identity (when enabled)
      
      $miQuery = @"
      IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$miName')
      BEGIN
        CREATE USER [$miName] FROM EXTERNAL PROVIDER;
      END
      ALTER ROLE db_ddladmin ADD MEMBER [$miName];
      ALTER ROLE db_datareader ADD MEMBER [$miName];
      ALTER ROLE db_datawriter ADD MEMBER [$miName];
      "@

      Invoke-Sqlcmd -ConnectionString "Data Source=tcp:${azurerm_mssql_server.sql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.database.name};Persist Security Info=False;Multiple Active Result Sets=False;Connect Timeout=30;Encrypt=True;Trust Server Certificate=False" -AccessToken $sqlToken -Query $miQuery

      Write-Host "SQL user setup completed for managed identity '$miName'"
    EOT
  }

  depends_on = [
    azuread_service_principal.nme_app,
    azurerm_mssql_server.sql_server,
    azurerm_mssql_database.database,
    azurerm_mssql_firewall_rule.allow_azure_ips,
    azurerm_mssql_firewall_rule.allow_deployer_ip,
    azuread_app_role_assignment.sql_directory_read_all,
    null_resource.wait_for_sql_private_dns,
  ]
}
