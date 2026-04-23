resource "azurerm_log_analytics_workspace" "law" {
  name                = var.law_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(
    {
      NMW_OBJECT_TYPE = "LOG_ANALYTICS_WORKSPACE"
    },
    lookup(
      var.tags_by_resource,
      "Microsoft.OperationalInsights/workspaces",
      {}
    )
  )
}

resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "dce-${var.law_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  public_network_access_enabled = true

  tags = merge(
    {
      NMW_OBJECT_TYPE = "DATA_COLLECTION_ENDPOINT"
    },
    lookup(
      var.tags_by_resource,
      "Microsoft.Insights/dataCollectionEndpoints",
      {}
    )
  )

  depends_on = [
    azurerm_log_analytics_workspace.law
  ]
}

resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                = "microsoft-avdi-${var.law_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  kind = "Windows"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = var.law_name
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Event"]
    destinations = [var.law_name]
  }

  # -----------------
  # Performance Counters (60s)
  # -----------------
  data_sources {
    performance_counter {
      name                          = "DS_WindowsPerformanceCounter_1"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\LogicalDisk(C:)\\% Free Space",
        "\\LogicalDisk(C:)\\Avg. Disk sec/Transfer",
        "\\Terminal Services(*)\\Active Sessions",
        "\\Terminal Services(*)\\Inactive Sessions",
        "\\Terminal Services(*)\\Total Sessions",
      ]
    }

    # -----------------
    # Performance Counters (30s)
    # -----------------
    performance_counter {
      name                          = "DS_WindowsPerformanceCounter_2"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 30
      counter_specifiers = [
        "\\LogicalDisk(C:)\\Avg. Disk Queue Length",
        "\\LogicalDisk(C:)\\Current Disk Queue Length",
        "\\Memory\\Available Mbytes",
        "\\Memory\\Page Faults/sec",
        "\\Memory\\Pages/sec",
        "\\Memory\\% Committed Bytes In Use",
        "\\PhysicalDisk(*)\\Avg. Disk Queue Length",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Read",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Transfer",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Write",
        "\\Processor Information(_Total)\\% Processor Time",
        "\\User Input Delay per Process(*)\\Max Input Delay",
        "\\User Input Delay per Session(*)\\Max Input Delay",
        "\\RemoteFX Network(*)\\Current TCP RTT",
        "\\RemoteFX Network(*)\\Current UDP Bandwidth",
      ]
    }

    # -----------------
    # Windows Event Logs
    # -----------------
    windows_event_log {
      name    = "DS_WindowsEventLogs"
      streams = ["Microsoft-Event"]
      x_path_queries = [
        "System!*[System[(Level=2 or Level=3)]]",
        "Application!*[System[(Level=2 or Level=3)]]",
        "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-FSLogix-Apps/Operational!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-FSLogix-Apps/Admin!*[System[(Level=2 or Level=3 or Level=4 or Level=0)]]",
      ]
    }
  }

  tags = merge(
    {
      NMW_OBJECT_TYPE = "DATA_COLLECTION_RULE"
    },
    lookup(
      var.tags_by_resource,
      "Microsoft.Insights/dataCollectionRules",
      {}
    )
  )
}
