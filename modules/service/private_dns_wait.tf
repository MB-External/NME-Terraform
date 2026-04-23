resource "null_resource" "wait_for_key_vault_private_dns" {
  count = var.configure_private_endpoints ? 1 : 0

  triggers = {
    fqdn                   = "${var.key_vault_name}${local.key_vault_suffix}"
    port                   = "443"
    private_endpoint_id    = azurerm_private_endpoint.key_vault[0].id
    dns_link_id            = azurerm_private_dns_zone_virtual_network_link.key_vault[0].id
    deployment_dns_link_id = azurerm_private_dns_zone_virtual_network_link.key_vault_deployment[0].id
    deployment_peering_id  = azurerm_virtual_network_peering.deployment_to_private[0].id
    private_peering_id     = azurerm_virtual_network_peering.private_to_deployment[0].id
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = "& '${path.module}/scripts/wait-for-private-endpoint.ps1' -Fqdn '${self.triggers.fqdn}' -Port ${self.triggers.port} -MaxAttempts 60 -DelaySeconds 10 -PostResolveDelaySeconds ${var.private_endpoint_post_resolve_delay}"
  }

  depends_on = [
    azurerm_private_endpoint.key_vault,
    azurerm_private_dns_zone_virtual_network_link.key_vault,
    azurerm_private_dns_zone_virtual_network_link.key_vault_deployment,
    azurerm_virtual_network_peering.deployment_to_private,
    azurerm_virtual_network_peering.private_to_deployment,
  ]
}

resource "null_resource" "wait_for_sql_private_dns" {
  count = var.configure_private_endpoints ? 1 : 0

  triggers = {
    fqdn                   = "${var.sql_server_name}${local.sql_server_suffix}"
    port                   = "1433"
    private_endpoint_id    = azurerm_private_endpoint.sql_server[0].id
    dns_link_id            = azurerm_private_dns_zone_virtual_network_link.sql[0].id
    deployment_dns_link_id = azurerm_private_dns_zone_virtual_network_link.sql_deployment[0].id
    deployment_peering_id  = azurerm_virtual_network_peering.deployment_to_private[0].id
    private_peering_id     = azurerm_virtual_network_peering.private_to_deployment[0].id
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = "& '${path.module}/scripts/wait-for-private-endpoint.ps1' -Fqdn '${self.triggers.fqdn}' -Port ${self.triggers.port} -MaxAttempts 60 -DelaySeconds 10 -PostResolveDelaySeconds ${var.private_endpoint_post_resolve_delay}"
  }

  depends_on = [
    azurerm_private_endpoint.sql_server,
    azurerm_private_dns_zone_virtual_network_link.sql,
    azurerm_private_dns_zone_virtual_network_link.sql_deployment,
    azurerm_virtual_network_peering.deployment_to_private,
    azurerm_virtual_network_peering.private_to_deployment,
  ]
}

resource "null_resource" "wait_for_app_service_private_dns" {
  count = var.configure_private_endpoints ? 1 : 0

  triggers = {
    fqdn                   = "${var.web_app_portal_name}${local.web_app_suffix}"
    port                   = "443"
    private_endpoint_id    = azurerm_private_endpoint.web_app[0].id
    dns_link_id            = azurerm_private_dns_zone_virtual_network_link.app_service[0].id
    deployment_dns_link_id = azurerm_private_dns_zone_virtual_network_link.app_service_deployment[0].id
    deployment_peering_id  = azurerm_virtual_network_peering.deployment_to_private[0].id
    private_peering_id     = azurerm_virtual_network_peering.private_to_deployment[0].id
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = "& '${path.module}/scripts/wait-for-private-endpoint.ps1' -Fqdn '${self.triggers.fqdn}' -Port ${self.triggers.port} -MaxAttempts 60 -DelaySeconds 10 -PostResolveDelaySeconds ${var.private_endpoint_post_resolve_delay}"
  }

  depends_on = [
    azurerm_private_endpoint.web_app,
    azurerm_private_dns_zone_virtual_network_link.app_service,
    azurerm_private_dns_zone_virtual_network_link.app_service_deployment,
    azurerm_virtual_network_peering.deployment_to_private,
    azurerm_virtual_network_peering.private_to_deployment,
  ]
}
