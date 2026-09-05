# ============================================================================
# modules/observability/workbooks.tf
#
# All Azure Monitor Workbooks for the Task API platform:
#   - Generic observability overview (original)
#   - Application SLO (golden signals)
#   - Infrastructure (AKS control-plane and node metrics)
#   - Database (PostgreSQL health and performance)
#   - Canary Release (rollout monitoring)
# ============================================================================

# ------------------------------------------------------------------------------
# Generic Observability Workbook
# ------------------------------------------------------------------------------

resource "azurerm_application_insights_workbook" "this" {
  name                = local.workbook_name
  resource_group_name = var.resource_group_name
  location            = var.location

  display_name = "Task API Observability - ${var.environment}"
  category     = "workbook"

  source_id = local.workbook_workspace_id

  data_json = templatefile("${path.module}/workbook.json.tftpl", {
    environment             = var.environment
    workspace_id            = local.workbook_workspace_id
    application_insights_id = local.workbook_application_insights_id
    request_query           = local.workbook_request_query
    dependency_query        = local.workbook_dependency_query
    exception_query         = local.workbook_exception_query
    metric_query            = local.workbook_metric_query
    snapshot_query          = local.workbook_snapshot_query
  })

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Application SLO Workbook
# ------------------------------------------------------------------------------

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
    snapshot_query          = local.app_slo_snapshot_query
    latency_query           = local.app_slo_latency_query
    traffic_query           = local.app_slo_traffic_query
    errors_query            = local.app_slo_errors_query
    custom_metrics_query    = local.app_slo_custom_metrics_query
  })

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Infrastructure Workbook
# ------------------------------------------------------------------------------

resource "azurerm_application_insights_workbook" "infra" {
  count = var.enable_infra_workbook ? 1 : 0

  name                = local.workbook_infra_name
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Task API Infrastructure - ${var.environment}"
  category            = "workbook"
  source_id           = local.workbook_workspace_id

  data_json = templatefile("${path.module}/workbook_infra.json.tftpl", {
    environment         = var.environment
    workspace_id        = local.workbook_workspace_id
    control_plane_query = local.infra_aks_control_plane_query
    api_errors_query    = local.infra_aks_api_errors_query
    node_cpu_query      = local.infra_node_cpu_query
    node_memory_query   = local.infra_node_memory_query
    node_disk_query     = local.infra_node_disk_query
  })

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Database Workbook
# ------------------------------------------------------------------------------

resource "azurerm_application_insights_workbook" "database" {
  count = var.enable_database_workbook ? 1 : 0

  name                = local.workbook_database_name
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Task API Database - ${var.environment}"
  category            = "workbook"
  source_id           = local.workbook_workspace_id

  lifecycle {
    precondition {
      condition     = var.postgresql_server_id != null
      error_message = "enable_database_workbook=true requires postgresql_server_id to be set."
    }
  }

  data_json = templatefile("${path.module}/workbook_database.json.tftpl", {
    environment        = var.environment
    workspace_id       = local.workbook_workspace_id
    connections_query  = local.database_connections_query
    cpu_query          = local.database_cpu_query
    storage_query      = local.database_storage_query
    slow_queries_query = local.database_slow_queries_query
    errors_query       = local.database_errors_query
  })

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Canary Release Workbook
# ------------------------------------------------------------------------------

resource "azurerm_application_insights_workbook" "canary" {
  count = var.enable_canary_workbook ? 1 : 0

  name                = local.workbook_canary_name
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Task API Canary Release - ${var.environment}"
  category            = "workbook"
  source_id           = local.workbook_workspace_id

  data_json = templatefile("${path.module}/workbook_canary.json.tftpl", {
    environment             = var.environment
    workspace_id            = local.workbook_workspace_id
    application_insights_id = local.workbook_application_insights_id
    failure_rate_query      = local.canary_failure_rate_query
    latency_query           = local.canary_latency_query
    exceptions_query        = local.canary_exceptions_query
    instance_split_query    = local.canary_instance_split_query
  })

  tags = var.tags
}
