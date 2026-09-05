# ============================================================================
# modules/observability/diagnostic_settings.tf
#
# Azure Monitor diagnostic settings for:
#   - Azure Kubernetes Service (AKS) control-plane/resource logs
#   - Azure Database for PostgreSQL Flexible Server resource logs
#
# Diagnostics are routed to the module-managed Log Analytics workspace.
#
# Resource-specific ("Dedicated") mode is intentional. With this mode,
# supported resource logs are written to service-specific Log Analytics
# tables rather than the legacy AzureDiagnostics table.
#
# IMPORTANT:
#   - AKS kube-apiserver / controller-manager / scheduler logs are represented
#     in the resource-specific AKSControlPlane table.
#   - AKS kube-audit logs are represented in AKSAudit.
#   - AKS kube-audit-admin logs, when enabled, are represented in
#     AKSAuditAdmin.
#   - PostgreSQLLogs is represented in PGSQLServerLogs.
#   - PostgreSQLFlexQueryStoreRuntime is represented in
#     PGSQLQueryStoreRuntime.
#   - ContainerLogV2, KubeEvents, and Perf are Container Insights outputs and
#     are NOT produced by these diagnostic settings alone.
# ============================================================================

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count = var.enable_aks_diagnostics ? 1 : 0

  name                           = "aks-diagnostics-${lower(trimspace(var.environment))}"
  target_resource_id             = var.aks_cluster_id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  # Kubernetes API server logs.
  enabled_log {
    category = "kube-apiserver"
  }

  # Kubernetes controller manager logs.
  enabled_log {
    category = "kube-controller-manager"
  }

  # Kubernetes scheduler logs.
  enabled_log {
    category = "kube-scheduler"
  }

  # Full Kubernetes audit stream.
  #
  # This includes get/list audit events and can generate substantial ingestion
  # volume. Microsoft recommends kube-audit-admin when the full audit stream is
  # not required.
  enabled_log {
    category = "kube-audit"
  }

  # AKS platform metrics.
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  count = var.enable_postgresql_diagnostics ? 1 : 0

  name                           = "postgresql-diagnostics-${lower(trimspace(var.environment))}"
  target_resource_id             = var.postgresql_server_id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = "Dedicated"

  # PostgreSQL Flexible Server logs.
  enabled_log {
    category = "PostgreSQLLogs"
  }

  # PostgreSQL Query Store runtime statistics.
  #
  # This category only becomes useful when Query Store is separately enabled
  # on the PostgreSQL Flexible Server.
  enabled_log {
    category = "PostgreSQLFlexQueryStoreRuntime"
  }

  # PostgreSQL platform metrics.
  enabled_metric {
    category = "AllMetrics"
  }

  lifecycle {
    precondition {
      condition     = var.postgresql_server_id != null
      error_message = "postgresql_server_id must be provided when enable_postgresql_diagnostics is true."
    }
  }
}
