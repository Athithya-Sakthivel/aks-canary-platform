# ============================================================================
# modules/observability/workbooks.tf
#
# All Azure Monitor Workbooks for the Task API platform:
#   - Application SLO (golden signals)
#   - Infrastructure (AKS control-plane and node metrics)
#   - Database (PostgreSQL health and performance)
#   - Canary Release (rollout monitoring)
# ============================================================================

resource "azurerm_application_insights_workbook" "app_slo" {
  count = var.enable_app_slo_workbook ? 1 : 0

  name                = local.workbook_app_slo_name
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Task API Application SLO - ${var.environment}"
  category            = "workbook"
  source_id           = local.workbook_workspace_id

  data_json = templatefile("${path.module}/workbook_app_slo.json.tftpl", {
    environment             = var.environment
    workspace_id            = local.workbook_workspace_id
    application_insights_id = local.workbook_application_insights_id
    availability_query      = local.app_slo_availability_query
    p95_query               = local.app_slo_p95_query
    traffic_query           = local.app_slo_traffic_query
    errors_query            = local.app_slo_errors_query
    business_metrics_query  = local.app_slo_business_metrics_query
    jvm_heap_query          = local.app_slo_jvm_heap_query
  })

  tags = var.tags
}

resource "azurerm_application_insights_workbook" "infra" {
  count = var.enable_infra_workbook ? 1 : 0

  name                = local.workbook_infra_name
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Task API Infrastructure - ${var.environment}"
  category            = "workbook"
  source_id           = local.workbook_workspace_id

  data_json = templatefile("${path.module}/workbook_infra.json.tftpl", {
    environment        = var.environment
    workspace_id       = local.workbook_workspace_id
    api_errors_query   = local.infra_aks_api_errors_query
    node_cpu_query     = local.infra_node_cpu_query
    node_memory_query  = local.infra_node_memory_query
    node_disk_query    = local.infra_node_disk_query
    pod_restarts_query = local.infra_pod_restarts_query
  })

  tags = var.tags
}

resource "azurerm_application_insights_workbook" "database" {
  count = var.enable_database_workbook ? 1 : 0

  name                = local.workbook_database_name
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Task API Database - ${var.environment}"
  category            = "workbook"
  source_id           = local.workbook_workspace_id

  data_json = templatefile("${path.module}/workbook_database.json.tftpl", {
    environment       = var.environment
    workspace_id      = local.workbook_workspace_id
    connections_query = local.database_connections_query
    cpu_query         = local.database_cpu_query
    storage_query     = local.database_storage_query
  })

  lifecycle {
    precondition {
      condition     = var.postgresql_server_id != null
      error_message = "enable_database_workbook=true requires postgresql_server_id to be set."
    }
  }

  tags = var.tags
}

resource "azurerm_application_insights_workbook" "canary" {
  count = var.enable_canary_workbook ? 1 : 0

  name                = local.workbook_canary_name
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Task API Canary Release - ${var.environment}"
  category            = "workbook"
  source_id           = local.workbook_workspace_id

  data_json = templatefile("${path.module}/workbook_canary.json.tftpl", {
    environment         = var.environment
    workspace_id        = local.workbook_workspace_id
    traffic_split_query = local.canary_traffic_split_query
    error_rate_query    = local.canary_error_rate_query
    latency_query       = local.canary_latency_query
    exceptions_query    = local.canary_exceptions_query
  })

  tags = var.tags
}
