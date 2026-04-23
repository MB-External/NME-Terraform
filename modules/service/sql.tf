data "azuread_service_principal" "current" {
  client_id = data.azurerm_client_config.current.client_id
}

data "azuread_application_published_app_ids" "well_known" {}

resource "azuread_service_principal" "msgraph" {
  client_id    = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
  use_existing = true
}

# Grant Directory.Read.All to SQL Server's Managed Identity
resource "azuread_app_role_assignment" "sql_directory_read_all" {
  app_role_id         = azuread_service_principal.msgraph.app_role_ids["Directory.Read.All"]
  principal_object_id = azurerm_mssql_server.sql_server.identity[0].principal_id
  resource_object_id  = azuread_service_principal.msgraph.object_id
}

resource "azurerm_mssql_server" "sql_server" {
  name                         = var.sql_server_name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  minimum_tls_version          = "1.2"
  public_network_access_enabled = var.configure_private_endpoints ? false : true

  azuread_administrator {
    login_username              = data.azuread_service_principal.current.display_name
    object_id                   = data.azurerm_client_config.current.client_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
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
  name           = var.database_name
  server_id     = azurerm_mssql_server.sql_server.id
  collation     = var.sql_collation
  max_size_gb   = var.database_max_size_gb

  sku_name = var.database_sku_name

  tags = merge(
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
  count               = var.configure_private_endpoints ? 1 : 0
  name                = local.sql_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones", {})
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  count                 = var.configure_private_endpoints ? 1 : 0
  name                  = "${var.network_config.vnet_name}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql[0].name
  virtual_network_id    = azurerm_virtual_network.private_endpoints_vnet[0].id
  tags                  = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {})
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_deployment" {
  count                 = var.configure_private_endpoints && var.deployment_vnet_name != null ? 1 : 0
  name                  = "${var.deployment_vnet_name}-deployment-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql[0].name
  virtual_network_id    = data.azurerm_virtual_network.deployment_vnet[0].id
  tags                  = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {})
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "sql_server" {
  count               = var.configure_private_endpoints ? 1 : 0
  name                = "${var.sql_server_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {})

  private_service_connection {
    name                           = "${var.sql_server_name}-pls"
    private_connection_resource_id = azurerm_mssql_server.sql_server.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql[0].id]
  }
}

resource "null_resource" "sql_user_setup" {
  triggers = {
    sp_id       = azuread_service_principal.nme_app.object_id
    sp_name     = azuread_service_principal.nme_app.display_name
    sql_server  = azurerm_mssql_server.sql_server.fully_qualified_domain_name
    database    = azurerm_mssql_database.database.name
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'

      # Authenticate to Azure using ARM env vars
      if ($env:ARM_CLIENT_SECRET) {
          $securePassword = ConvertTo-SecureString $env:ARM_CLIENT_SECRET -AsPlainText -Force
          $credential = New-Object System.Management.Automation.PSCredential($env:ARM_CLIENT_ID, $securePassword)
          Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $env:ARM_TENANT_ID -Environment '${var.azure_environment}' | Out-Null
      }
      elseif ($env:ARM_OIDC_TOKEN) {
          Connect-AzAccount -ServicePrincipal -ApplicationId $env:ARM_CLIENT_ID -FederatedToken $env:ARM_OIDC_TOKEN -Tenant $env:ARM_TENANT_ID -Environment '${var.azure_environment}' | Out-Null
      }

      Set-AzContext -Subscription '${data.azurerm_client_config.current.subscription_id}' | Out-Null

      # Get token for database scope
      if (-not (Get-Command Get-AzAccessToken).Parameters.AsSecureString) {
          $sqlToken = (Get-AzAccessToken -ResourceUrl '${local.database_scope}').Token
      } else {
          $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Get-AzAccessToken -AsSecureString -ResourceUrl '${local.database_scope}').Token)
          try { $sqlToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
      }

      $spName = '${azuread_service_principal.nme_app.display_name}'
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
