# ============================================================================
# modules/observability/alerts.tf
#
# Azure Monitor action group and configurable alert rules.
#
# Alert categories:
#   - AKS node CPU saturation
#   - AKS node memory saturation
#   - AKS pod restart growth
#   - Task API request failure rate
#   - PostgreSQL Flexible Server storage saturation
#   - Task API fast error-budget burn
#   - Task API slow error-budget burn
#   - PostgreSQL Flexible Server CPU saturation
#
# SLO assumption for burn-rate alerts:
#   - Availability SLO: 99.9%
#   - Error budget: 0.1%
#   - Fast burn threshold: 20x over 5 minutes
#       Equivalent sustained error rate: 2.0%
#       Approximate budget exhaustion time at constant rate: 36 hours
#   - Slow burn threshold: 5x over 1 hour
#       Equivalent sustained error rate: 0.5%
#       Approximate budget exhaustion time at constant rate: 6 days
#
# IMPORTANT:
#   These are independent fast/slow alerts. They are intentionally not a
#   Google-SRE-style multi-window AND condition. See the assumptions/contracts
#   section accompanying this rewrite.
# ============================================================================

locals {
  environment_name = lower(var.environment)

  # Azure Monitor action-group short names are limited to 12 characters.
  # Truncation is deliberate so deployment does not fail for longer
  # environment names.
  action_group_short_name = substr(
    "taskapi-${local.environment_name}",
    0,
    12
  )

  application_insights_resource_id = azurerm_application_insights.this.id
  aks_resource_id                  = var.aks_cluster_id

  # Burn-rate constants for a 99.9% availability SLO.
  # Error budget = 100 - 99.9 = 0.1 percentage points.
  slo_target_percent       = 99.9
  slo_error_budget_percent = 100.0 - local.slo_target_percent

  burn_rate_fast_threshold = 20.0
  burn_rate_slow_threshold = 5.0
}

# ------------------------------------------------------------------------------
# Action group
# ------------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-taskapi-${local.environment_name}"
  resource_group_name = var.resource_group_name
  short_name          = local.action_group_short_name
  enabled             = true

  email_receiver {
    name                    = "admin"
    email_address           = var.alert_email_address
    use_common_alert_schema = true
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# AKS node CPU
# ------------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "cpu" {
  count = var.enable_cpu_alert ? 1 : 0

  name                = "aks-cpu-${local.environment_name}"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]

  description = "Alert when average AKS node CPU usage exceeds 80 percent over 15 minutes."

  frequency     = "PT5M"
  window_size   = "PT15M"
  severity      = 2
  enabled       = true
  auto_mitigate = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# AKS node memory
# ------------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "memory" {
  count = var.enable_memory_alert ? 1 : 0

  name                = "aks-memory-${local.environment_name}"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]

  description = "Alert when average AKS node working-set memory usage exceeds 90 percent over 15 minutes."

  frequency     = "PT5M"
  window_size   = "PT15M"
  severity      = 2
  enabled       = true
  auto_mitigate = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# AKS pod restarts
# ------------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "pod_restarts" {
  count = var.enable_pod_restarts_alert ? 1 : 0

  name                = "pod-restarts-${local.environment_name}"
  display_name        = "Task API pod restarts - ${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  description = "Alert when pod restart counts increase by more than 5 across the selected AKS cluster during the last 15 minutes."

  evaluation_frequency             = "PT15M"
  window_duration                  = "PT15M"
  severity                         = 2
  enabled                          = true
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false

  scopes = [azurerm_log_analytics_workspace.this.id]

  criteria {
    query = <<-QUERY
      KubePodInventory
      | where TimeGenerated > ago(15m)
      | where _ResourceId =~ '${local.aks_resource_id}'
      | where Namespace !in ("kube-system", "gatekeeper-system")
      | where isnotempty(PodUid)
      | summarize
          FirstRestartCount = min(PodRestartCount),
          LastRestartCount = max(PodRestartCount)
        by PodUid, Name, Namespace, _ResourceId
      | extend Restarts = iff(
          LastRestartCount > FirstRestartCount,
          LastRestartCount - FirstRestartCount,
          0
        )
      | summarize TotalRestarts = sum(Restarts) by _ResourceId
      | project _ResourceId, TotalRestarts
    QUERY

    time_aggregation_method = "Maximum"
    metric_measure_column   = "TotalRestarts"
    resource_id_column      = "_ResourceId"
    operator                = "GreaterThan"
    threshold               = 5

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Task API failed requests
# ------------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "failed_requests" {
  count = var.enable_failed_requests_alert ? 1 : 0

  name                = "failed-requests-${local.environment_name}"
  display_name        = "Task API failed requests - ${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  description = "Alert when the Task API request failure rate exceeds 5 percent over the last 15 minutes."

  evaluation_frequency             = "PT5M"
  window_duration                  = "PT15M"
  severity                         = 2
  enabled                          = true
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false

  scopes = [azurerm_log_analytics_workspace.this.id]

  criteria {
    query = <<-QUERY
      AppRequests
      | where TimeGenerated > ago(15m)
      | where _ResourceId =~ '${local.application_insights_resource_id}'
      | summarize
          TotalRequests = sum(ItemCount),
          FailedRequests = sumif(ItemCount, Success == false)
        by _ResourceId
      | extend FailureRate = iff(
          TotalRequests == 0,
          0.0,
          100.0 * todouble(FailedRequests) / todouble(TotalRequests)
        )
      | project _ResourceId, FailureRate
    QUERY

    time_aggregation_method = "Maximum"
    metric_measure_column   = "FailureRate"
    resource_id_column      = "_ResourceId"
    operator                = "GreaterThan"
    threshold               = 5

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# PostgreSQL storage
# ------------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "postgres_storage" {
  count = var.enable_postgres_storage_alert ? 1 : 0

  name                = "postgres-storage-${local.environment_name}"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgresql_server_id]

  description = "Alert when PostgreSQL Flexible Server storage usage exceeds 80 percent over 15 minutes."

  frequency     = "PT5M"
  window_size   = "PT15M"
  severity      = 2
  enabled       = true
  auto_mitigate = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.postgresql_server_id != null
      error_message = "postgresql_server_id must be provided when enable_postgres_storage_alert is true."
    }
  }
}

# ------------------------------------------------------------------------------
# Fast error-budget burn
#
# 99.9% SLO => 0.1% error budget.
#
# Burn rate = observed error rate / allowed error rate.
# 20x burn = 2.0% observed error rate.
#
# This is an intentionally independent 5-minute fast-burn alert.
# ------------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "burn_rate_fast" {
  count = var.enable_burn_rate_fast_alert ? 1 : 0

  name                = "burn-rate-fast-${local.environment_name}"
  display_name        = "Task API fast error budget burn - ${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  description = "Alert when the Task API error-budget burn rate exceeds 20x during the last 5 minutes for a 99.9 percent availability SLO."

  evaluation_frequency             = "PT5M"
  window_duration                  = "PT5M"
  severity                         = 1
  enabled                          = true
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false

  scopes = [azurerm_log_analytics_workspace.this.id]

  criteria {
    query = <<-QUERY
      AppRequests
      | where TimeGenerated > ago(5m)
      | where _ResourceId =~ '${local.application_insights_resource_id}'
      | summarize
          TotalRequests = sum(ItemCount),
          FailedRequests = sumif(ItemCount, Success == false)
        by _ResourceId
      | extend ErrorRatePercent = iff(
          TotalRequests == 0,
          0.0,
          100.0 * todouble(FailedRequests) / todouble(TotalRequests)
        )
      | extend BurnRate = iff(
          ${local.slo_error_budget_percent} == 0,
          0.0,
          ErrorRatePercent / ${local.slo_error_budget_percent}
        )
      | project _ResourceId, BurnRate
    QUERY

    time_aggregation_method = "Maximum"
    metric_measure_column   = "BurnRate"
    resource_id_column      = "_ResourceId"
    operator                = "GreaterThan"
    threshold               = local.burn_rate_fast_threshold

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Slow error-budget burn
#
# 99.9% SLO => 0.1% error budget.
#
# Burn rate = observed error rate / allowed error rate.
# 5x burn = 0.5% observed error rate.
#
# This is an intentionally independent 1-hour slow-burn alert.
# ------------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "burn_rate_slow" {
  count = var.enable_burn_rate_slow_alert ? 1 : 0

  name                = "burn-rate-slow-${local.environment_name}"
  display_name        = "Task API slow error budget burn - ${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  description = "Alert when the Task API error-budget burn rate exceeds 5x during the last hour for a 99.9 percent availability SLO."

  evaluation_frequency             = "PT15M"
  window_duration                  = "PT1H"
  severity                         = 2
  enabled                          = true
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false

  scopes = [azurerm_log_analytics_workspace.this.id]

  criteria {
    query = <<-QUERY
      AppRequests
      | where TimeGenerated > ago(1h)
      | where _ResourceId =~ '${local.application_insights_resource_id}'
      | summarize
          TotalRequests = sum(ItemCount),
          FailedRequests = sumif(ItemCount, Success == false)
        by _ResourceId
      | extend ErrorRatePercent = iff(
          TotalRequests == 0,
          0.0,
          100.0 * todouble(FailedRequests) / todouble(TotalRequests)
        )
      | extend BurnRate = iff(
          ${local.slo_error_budget_percent} == 0,
          0.0,
          ErrorRatePercent / ${local.slo_error_budget_percent}
        )
      | project _ResourceId, BurnRate
    QUERY

    time_aggregation_method = "Maximum"
    metric_measure_column   = "BurnRate"
    resource_id_column      = "_ResourceId"
    operator                = "GreaterThan"
    threshold               = local.burn_rate_slow_threshold

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# PostgreSQL CPU
# ------------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "postgres_cpu" {
  count = var.enable_postgres_cpu_alert ? 1 : 0

  name                = "postgres-cpu-${local.environment_name}"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgresql_server_id]

  description = "Alert when PostgreSQL Flexible Server CPU usage exceeds 80 percent over 15 minutes."

  frequency     = "PT5M"
  window_size   = "PT15M"
  severity      = 2
  enabled       = true
  auto_mitigate = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.postgresql_server_id != null
      error_message = "postgresql_server_id must be provided when enable_postgres_cpu_alert is true."
    }
  }
}