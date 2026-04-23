data "local_file" "nmw_update_run_as_script" {
  filename = "${path.module}/scripts/nmw-update-run-as.ps1"
}

resource "azurerm_automation_runbook" "nmw_update_run_as" {
  name                    = "nmwUpdateRunAs"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.automation.name

  runbook_type = "PowerShell"

  log_progress = false
  log_verbose  = true
  description  = "Update using automation Run As account"

  content = data.local_file.nmw_update_run_as_script.content

  tags = lookup(
    var.tags_by_resource,
    "Microsoft.Automation/automationAccounts/runbooks",
    {}
  )
}

