locals {
  sql_server_resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Sql/servers/${var.sql_server_name}"

  _production_maintenance_service_url = "https://nwp-web-app.azurewebsites.net"
  _optional_app_settings = {
    "MaintenanceService:Uri" = var.maintenance_service_url == local._production_maintenance_service_url ? null : var.maintenance_service_url
  }
  optional_app_settings = {
    for k, v in local._optional_app_settings : k => v if v != null
  }
}

resource "azurerm_service_plan" "app_service_plan" {
  name                = var.app_service_plan_name
  location            = var.location
  resource_group_name = var.resource_group_name

  os_type  = "Windows"
  sku_name = var.app_service_plan_sku_name

  tags = merge(
    {
      NMW_OBJECT_TYPE = "PAAS"
    },
    lookup(
      var.tags_by_resource,
      "Microsoft.Web/serverfarms",
      {}
    )
  )
}

resource "azurerm_windows_web_app" "web_app_portal" {
  name                = var.web_app_portal_name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.app_service_plan.id

  public_network_access_enabled = (var.configure_private_endpoints && var.private_web_app) ? false : true
  virtual_network_subnet_id     = local.app_subnet_id

  https_only              = true
  client_affinity_enabled = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    http2_enabled       = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.3"
    use_32_bit_worker   = false
    application_stack {
      current_stack  = "dotnet"
      dotnet_version = "v10.0"
    }
  }

  app_settings = merge({
    # Deployment metadata

    "AzureAd:Instance"                   = local.azuread_instance
    "Deployment:AzureType"               = var.azure_environment
    "Deployment:Region"                  = var.location
    "Deployment:ResourceGroupName"       = var.resource_group_name
    "Deployment:WebAppName"              = var.web_app_portal_name
    "Deployment:AzureTagPrefix"          = var.azure_tag_prefix
    "Deployment:KeyVaultName"            = var.key_vault_name
    "Deployment:SubscriptionId"          = data.azurerm_client_config.current.subscription_id
    "Deployment:SubscriptionDisplayName" = var.subscription_display_name
    "Deployment:TenantId"                = data.azurerm_client_config.current.tenant_id

    # Automation
    "Deployment:AutomationAccountName"        = var.automation_account_name
    "Deployment:AutomationAccountAzInstalled" = "True"
    "Deployment:AutomationEnabled"            = "True"
    "Deployment:UpdaterRunbookRunAs"          = "nmwUpdateRunAs"
    "Deployment:LogAnalyticsWorkspace"        = azurerm_log_analytics_workspace.law.id
    "Deployment:ScriptedActionAccount"        = azurerm_automation_account.scripted_action.id

    # Application Insights
    "ApplicationInsights:ConnectionString"   = azurerm_application_insights.app_insights.connection_string
    "ApplicationInsights:InstrumentationKey" = azurerm_application_insights.app_insights.instrumentation_key

    # Data Protection
    "DataProtection:Storage:Type"          = "AzureBlobStorage"
    "DataProtection:Protect:KeyIdentifier" = "https://${var.key_vault_name}${local.key_vault_suffix}/keys/${var.data_protection_key_name}"

    # SQL
    "Deployment:SqlServerId"              = local.sql_server_resource_id
    "ConnectionStrings:DefaultConnection" = "Server=tcp:${var.sql_server_name}${local.sql_server_suffix},1433;Initial Catalog=${var.database_name};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Default;"

    # Azure AD / NME application (previously set by install-az.ps1)
    "RoleAuthorization:Enabled"                                   = "True"
    "Features:CumulativeRbac"                                     = "True"
    "AzureAD:ClientId"                                            = azuread_application.nme_app.client_id
    "AzureAD:TenantId"                                            = data.azurerm_client_config.current.tenant_id
    "AzureAD:ClientCertificates:0:SourceType"                     = "KeyVault"
    "AzureAD:ClientCertificates:0:KeyVaultCertificateName"        = var.app_cert_name
    "AzureAD:ClientCertificates:0:KeyVaultUrl"                    = "https://${var.key_vault_name}${local.key_vault_suffix}"
    "AzureAD:DefaultGraphScopes"                                  = local.default_delegated_permissions
    "WVD:AadTenantId"                                             = data.azurerm_client_config.current.tenant_id
    "WVD:SubscriptionId"                                          = data.azurerm_client_config.current.subscription_id
    "Billing:Mode"                                                = "MAU"
    "Artifacts:Mode"                                              = "Local"
    "Deployment:FallbackOptions:DefaultLocalAdmin:DisableAccount" = "True"
    "Deployment:FallbackOptions:DefaultLocalAdmin:RandomPassword" = "True"

    # Deploy
    #WEBSITE_RUN_FROM_PACKAGE = 1
  }, local.optional_app_settings)

  tags = merge(
    {
      NMW_OBJECT_TYPE = "PAAS"
    },
    lookup(
      var.tags_by_resource,
      "Microsoft.Web/sites",
      {}
    )
  )

  depends_on = [
    azurerm_application_insights.app_insights
  ]
}


resource "null_resource" "download_package" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $ProgressPreference    = 'SilentlyContinue'

      # --- Prepare temp directory ------------------------------------------ #
      $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) 'nmw_terraform_package'
      if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
      New-Item -Path $tempDir -ItemType Directory | Out-Null
      $zipPath = Join-Path $tempDir 'package.zip'

      $localPackagePath = '${replace(coalesce(var.app_package_local_path, ""), "'", "''")}'

      if (-not [string]::IsNullOrWhiteSpace($localPackagePath)) {
          # --- Offline install: use pre-downloaded local package ----------- #
          # app_package_version is ignored; the maintenance service is not contacted.
          if (-not (Test-Path -LiteralPath $localPackagePath)) {
              throw "Local package not found at '$localPackagePath'"
          }
          Write-Host "Using local package: $localPackagePath (maintenance service skipped)"
          Copy-Item -LiteralPath $localPackagePath -Destination $zipPath -Force
      }
      else {
          # --- Get package download URL ------------------------------------ #
          $version  = '${var.app_package_version}'
          if ($version -eq 'latest') {
              Write-Host "Resolving latest package version..."

              $listUrl = "${var.maintenance_service_url}/api/package"
              $packages = Invoke-RestMethod -Uri $listUrl -Method Get

              if (-not $packages) {
                  throw "No packages returned from maintenance service"
              }

              $latestPackage = $packages |
                  Where-Object { $_.status -eq 2 -and $_.version } |
                  Sort-Object { [version]$_.version } -Descending |
                  Select-Object -First 1

              if (-not $latestPackage) {
                  throw "No eligible package found with status GeneralAvailability"
              }

              $version = $latestPackage.version
              Write-Host "Latest version resolved: $version"
          }

          $apiUrl   = '${var.maintenance_service_url}/api/package/' + $version + '/link?standalone=false'

          Write-Host "Requesting package link from $apiUrl ..."
          $response = Invoke-RestMethod -Uri $apiUrl -Method Post -ContentType 'application/json'
          $packageUri = $response.packageUri

          if ([string]::IsNullOrWhiteSpace($packageUri)) {
              throw "Maintenance service returned empty packageUri"
          }
          Write-Host "Package URI received."

          # --- Download package -------------------------------------------- #
          Write-Host "Downloading package into temporary file ..."
          Invoke-WebRequest -Uri $packageUri -OutFile $zipPath
          $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
          Write-Host "Package downloaded: $sizeMB MB -> $zipPath"
      }

      # --- Extract package ------------------------------------------------- #
      Write-Host "Extracting package ..."
      Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
      Write-Host "Package extracted to $tempDir"

      if(-not [string]::IsNullOrWhiteSpace($localPackagePath)){
        # --- Validated extracted offline package --------------------------- #
        # The package archive must contain app.zip and related deployment files.
        $appZipPath = Join-Path $tempDir 'app.zip'
        if (-not (Test-Path $appZipPath)) {
            throw "app.zip not found after extraction. The package at $zipPath must be the NME package archive containing app.zip and related deployment files."
        }
      } 
      
      # --- Remove downloaded zip ------------------------------------------- #
      Remove-Item -Path $zipPath -Force
      Write-Host "Removed temporary zip archive"
    EOT
  }
}

resource "null_resource" "stop_webjobs" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $ProgressPreference    = 'SilentlyContinue'

      # --- Authenticate --------------------------------------------------- #
      . '${path.module}/scripts/connect-azure.ps1' -Environment '${var.azure_environment}' -SubscriptionId '${data.azurerm_client_config.current.subscription_id}'

      # --- Stop all WebJobs ----------------------------------------------- #
      Write-Host "Stopping all WebJobs for '${var.web_app_portal_name}'..."
      $webJobs = Get-AzWebAppContinuousWebJob -ResourceGroupName '${var.resource_group_name}' -AppName '${var.web_app_portal_name}' -ErrorAction SilentlyContinue
      $runningJobs = $webJobs | Where-Object Status -EQ "Running"
      
      if ($runningJobs) {
          Write-Host "Found $($runningJobs.Count) running WebJob(s)"
          foreach ($job in $runningJobs) {
              Write-Host "Stopping WebJob: $($job.Name)"
              try {
                  Stop-AzWebAppContinuousWebJob -ResourceGroupName '${var.resource_group_name}' -AppName '${var.web_app_portal_name}' -Name $job.Name -ErrorAction SilentlyContinue
              }
              catch {
                  Write-Host "Warning: Failed to stop WebJob $($job.Name): $($_.Exception.Message)"
              }
          }
          Write-Host "All WebJobs stopped successfully."
      }
      else {
          Write-Host "No running WebJobs found"
      }
    EOT
  }

  depends_on = [
    azurerm_windows_web_app.web_app_portal,
    azurerm_mssql_database.database,
    azurerm_mssql_server.sql_server,
    azurerm_key_vault.key_vault,
    azurerm_automation_account.automation,
    azurerm_log_analytics_workspace.law,
    azurerm_automation_account.scripted_action,
    azurerm_storage_account.data_protection,
    azurerm_storage_container.dp_keys,
    azurerm_storage_container.dp_locks,
    azuread_application.nme_app,
    azuread_service_principal.nme_app,
    azurerm_key_vault_certificate.scripted_action_cert,
    azuread_application_certificate.scripted_action,
    azurerm_role_assignment.nme_sp_reader,
    azurerm_role_assignment.nme_sp_contributor,
    azurerm_role_assignment.nme_sp_backup_reader,
    null_resource.sql_user_setup,
    azurerm_automation_certificate.scripted_action,
    null_resource.wait_for_app_service_private_dns,
  ]
}

resource "null_resource" "deploy_package" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $ProgressPreference    = 'SilentlyContinue'

      # --- Authenticate --------------------------------------------------- #
      . '${path.module}/scripts/connect-azure.ps1' -Environment '${var.azure_environment}' -SubscriptionId '${data.azurerm_client_config.current.subscription_id}'

      # --- Publish to Web App --------------------------------------------- #
      $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) 'nmw_terraform_package'
      $appZipPath = Join-Path $tempDir 'app.zip'

      if (-not (Test-Path $appZipPath)) {
          throw "Package not found at $appZipPath. Ensure download_package ran successfully."
      }

      try {
          Write-Host "Publishing to web app '${var.web_app_portal_name}' ..."
          Publish-AzWebApp -ResourceGroupName '${var.resource_group_name}' -Name '${var.web_app_portal_name}' -ArchivePath $appZipPath -Force -Timeout 600000

          Write-Host "Package published successfully."
      }
      finally {
          Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
      }
    EOT
  }

  depends_on = [
    null_resource.download_package,
    null_resource.stop_webjobs
  ]
}

resource "null_resource" "start_webjobs" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $ProgressPreference    = 'SilentlyContinue'

      # --- Authenticate --------------------------------------------------- #
      . '${path.module}/scripts/connect-azure.ps1' -Environment '${var.azure_environment}' -SubscriptionId '${data.azurerm_client_config.current.subscription_id}'

      # --- Start all WebJobs ---------------------------------------------- #
      Write-Host "Starting all WebJobs for '${var.web_app_portal_name}'..."
      $webJobs = Get-AzWebAppContinuousWebJob -ResourceGroupName '${var.resource_group_name}' -AppName '${var.web_app_portal_name}' -ErrorAction SilentlyContinue
      $stoppedJobs = $webJobs | Where-Object Status -EQ "Stopped"
      
      if ($stoppedJobs) {
          Write-Host "Found $($stoppedJobs.Count) stopped WebJob(s)"
          foreach ($job in $stoppedJobs) {
              Write-Host "Starting WebJob: $($job.Name)"
              try {
                  Start-AzWebAppContinuousWebJob -ResourceGroupName '${var.resource_group_name}' -AppName '${var.web_app_portal_name}' -Name $job.Name -ErrorAction SilentlyContinue
              }
              catch {
                  Write-Host "Warning: Failed to start WebJob $($job.Name): $($_.Exception.Message)"
              }
          }
          Write-Host "All WebJobs started successfully."
      }
      else {
          Write-Host "No stopped WebJobs found"
      }
    EOT
  }

  depends_on = [
    null_resource.deploy_package
  ]
}

resource "null_resource" "health_check" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $ProgressPreference    = 'SilentlyContinue'

      # --- Wait for site to become available ------------------------------ #
      $healthEndpoint = "${local.web_app_url}/public/health/ping"
      $maxAttempts = 60
      $delaySeconds = 10

      Write-Host "Waiting for site to become available at $healthEndpoint ..."
      
      for ($i = 1; $i -le $maxAttempts; $i++) {
          try {
              Write-Host "Attempt $i/$maxAttempts : Checking health endpoint..."
              $response = Invoke-WebRequest -Uri $healthEndpoint -Method Get -UseBasicParsing -TimeoutSec 30
              
              if ($response.StatusCode -eq 200) {
                  Write-Host "SUCCESS: Site is available and returned 200 OK"
                  exit 0
              }
              else {
                  Write-Host "Received status code: $($response.StatusCode), retrying..."
              }
          }
          catch {
              Write-Host "Health check failed: $($_.Exception.Message)"
          }
          
          if ($i -lt $maxAttempts) {
              Write-Host "Waiting $delaySeconds seconds before next attempt..."
              Start-Sleep -Seconds $delaySeconds
          }
      }
      
      throw "Site did not become available after $maxAttempts attempts"
    EOT
  }

  depends_on = [
    null_resource.deploy_package,
    null_resource.start_webjobs,
    null_resource.wait_for_app_service_private_dns,
  ]
}

resource "azurerm_private_endpoint" "web_app" {
  count               = local.deploy_private_endpoint_managed_dns ? 1 : 0
  name                = "${var.web_app_portal_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {})

  private_service_connection {
    name                           = "${var.web_app_portal_name}-pls"
    private_connection_resource_id = azurerm_windows_web_app.web_app_portal.id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.app_service[0].id]
  }
}

resource "azurerm_private_endpoint" "web_app_unmanaged_dns" {
  count               = local.deploy_private_endpoint_unmanaged_dns ? 1 : 0
  name                = "${var.web_app_portal_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.private_endpoints_subnet_id
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateEndpoints", {})

  private_service_connection {
    name                           = "${var.web_app_portal_name}-pls"
    private_connection_resource_id = azurerm_windows_web_app.web_app_portal.id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_private_dns_zone" "app_service" {
  count               = local.create_dns_zones ? 1 : 0
  name                = local.app_service_private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones", {})
}

resource "azurerm_private_dns_zone_virtual_network_link" "app_service" {
  count                = local.link_dns_zones ? 1 : 0
  name                 = "${var.network_config.vnet_name}-link"
  private_dns_zone_id  = local.app_service_dns_zone_id
  virtual_network_id   = local.virtual_network_id
  tags                 = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {})
  registration_enabled = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "app_service_deployment" {
  count                = local.link_dns_zones && var.deployment_vnet_name != null ? 1 : 0
  name                 = "${var.deployment_vnet_name}-deployment-link"
  private_dns_zone_id  = local.app_service_dns_zone_id
  virtual_network_id   = data.azurerm_virtual_network.deployment_vnet[0].id
  tags                 = lookup(var.tags_by_resource, "Microsoft.Network/privateDnsZones/virtualNetworkLinks", {})
  registration_enabled = false
}
