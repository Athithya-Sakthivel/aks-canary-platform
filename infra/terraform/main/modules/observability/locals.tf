# ============================================================================
# modules/observability/locals.tf
#
# Four focused dashboards:
#   - Application SLO
#   - Infrastructure
#   - Database
#   - Canary Release
#
# The generic observability workbook and its query locals are intentionally
# removed.
# ============================================================================

locals {
  environment_normalized = lower(trimspace(var.environment))

  workbook_workspace_id            = lower(azurerm_log_analytics_workspace.this.id)
  workbook_application_insights_id = lower(azurerm_application_insights.this.id)
  workbook_postgresql_server_id    = lower(coalesce(var.postgresql_server_id, ""))

  # Deterministic workbook UUIDs.
  workbook_app_slo_name = uuidv5(
    "url",
    "https://taskapi.example.invalid/observability/workbook/app-slo/${local.environment_normalized}/${azurerm_application_insights.this.name}"
  )

  workbook_infra_name = uuidv5(
    "url",
    "https://taskapi.example.invalid/observability/workbook/infra/${local.environment_normalized}/${azurerm_application_insights.this.name}"
  )

  workbook_database_name = uuidv5(
    "url",
    "https://taskapi.example.invalid/observability/workbook/database/${local.environment_normalized}/${azurerm_application_insights.this.name}"
  )

  workbook_canary_name = uuidv5(
    "url",
    "https://taskapi.example.invalid/observability/workbook/canary/${local.environment_normalized}/${azurerm_application_insights.this.name}"
  )

  # ---------------------------------------------------------------------------
  # Application SLO
  # ---------------------------------------------------------------------------

  app_slo_availability_query = <<-KQL
    let Total = tolong(toscalar(
      AppRequests
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | summarize sum(ItemCount)
    ));
    let Successful = tolong(toscalar(
      AppRequests
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | where Success == true
      | summarize sum(ItemCount)
    ));
    print Value = iff(
      Total == 0,
      "No traffic",
      strcat(
        tostring(round(100.0 * todouble(Successful) / todouble(Total), 2)),
        "%"
      )
    )
  KQL

  app_slo_p95_query = <<-KQL
    let P95 = toreal(toscalar(
      AppRequests
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | where isnotnull(DurationMs)
      | where ItemCount > 0
      | summarize percentilew(DurationMs, ItemCount, 95)
    ));
    print Value = iff(
      isnull(P95),
      "No data",
      strcat(tostring(round(P95, 1)), " ms")
    )
  KQL

  app_slo_traffic_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | summarize RequestCount = sum(ItemCount) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  app_slo_errors_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | summarize
        Total = sum(ItemCount),
        Failed = sumif(ItemCount, Success == false)
      by bin(TimeGenerated, 10m)
    | extend ErrorRate = iff(
        Total == 0,
        0.0,
        100.0 * todouble(Failed) / todouble(Total)
      )
    | project TimeGenerated, ErrorRate
    | order by TimeGenerated asc
    | render timechart
  KQL

  app_slo_business_metrics_query = <<-KQL
    AppMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | where Name in (
        "task_created_total",
        "auth_success_total",
        "auth_failure_total"
      )
    | where ItemCount > 0
    | summarize MetricValue = sum(Sum) by Name, bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  # Weighted average is preferable to raw avg(Sum) when AppMetrics have been
  # batched or sampled.
  app_slo_jvm_heap_query = <<-KQL
    AppMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | where Name == "jvm_memory_used"
    | where ItemCount > 0
    | summarize
        TotalValue = sum(Sum),
        SampleCount = sum(ItemCount)
      by bin(TimeGenerated, 10m)
    | extend HeapUsed = iff(
        SampleCount == 0,
        real(null),
        todouble(TotalValue) / todouble(SampleCount)
      )
    | project TimeGenerated, HeapUsed
    | order by TimeGenerated asc
    | render timechart
  KQL

  # ---------------------------------------------------------------------------
  # Infrastructure
  # ---------------------------------------------------------------------------

  infra_aks_api_errors_query = <<-KQL
    AKSControlPlane
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where Category =~ "kube-apiserver"
    | where Level in~ ("Error", "Fatal")
    | summarize ErrorCount = count() by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  infra_node_cpu_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where MetricName == "node_cpu_usage_percentage"
    | summarize AvgCPU = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  infra_node_memory_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where MetricName == "node_memory_working_set_percentage"
    | summarize AvgMemory = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  infra_node_disk_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where MetricName == "node_disk_usage_percentage"
    | summarize AvgDisk = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  infra_pod_restarts_query = <<-KQL
    KubePodInventory
    | where TimeGenerated > ago(15m)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where Namespace !in ("kube-system", "gatekeeper-system")
    | where isnotempty(PodUid)
    | summarize
        FirstRestartCount = min(PodRestartCount),
        LastRestartCount = max(PodRestartCount)
      by PodUid, Name, Namespace
    | extend Restarts = max_of(LastRestartCount - FirstRestartCount, 0)
    | where Restarts > 0
    | project Name, Namespace, Restarts
    | order by Restarts desc, Name asc
    | take 20
  KQL

  # ---------------------------------------------------------------------------
  # Database
  # ---------------------------------------------------------------------------

  database_connections_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
    | where MetricName == "active_connections"
    | summarize AvgConnections = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  database_cpu_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
    | where MetricName == "cpu_percent"
    | summarize AvgCPU = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  database_storage_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
    | where MetricName == "storage_percent"
    | summarize AvgStorage = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
    | render timechart
  KQL


  # ---------------------------------------------------------------------------
  # Canary release
  # ---------------------------------------------------------------------------

  # "UNVERSIONED" is deliberate: it makes a telemetry-contract failure visible
  # rather than silently losing traffic from the dashboard.
  canary_traffic_split_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | extend Version = iff(isempty(AppVersion), "UNVERSIONED", AppVersion)
    | summarize RequestCount = sum(ItemCount) by Version, bin(TimeGenerated, 5m)
    | order by TimeGenerated asc
    | render areachart
  KQL

  canary_error_rate_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | extend Version = iff(isempty(AppVersion), "UNVERSIONED", AppVersion)
    | summarize
        Total = sum(ItemCount),
        Failed = sumif(ItemCount, Success == false)
      by Version, bin(TimeGenerated, 5m)
    | extend ErrorRate = iff(
        Total == 0,
        0.0,
        100.0 * todouble(Failed) / todouble(Total)
      )
    | project TimeGenerated, Version, ErrorRate
    | order by TimeGenerated asc
    | render timechart
  KQL

  canary_latency_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | where isnotnull(DurationMs)
    | where ItemCount > 0
    | extend Version = iff(isempty(AppVersion), "UNVERSIONED", AppVersion)
    | summarize
        P95 = percentilew(DurationMs, ItemCount, 95)
      by Version, bin(TimeGenerated, 5m)
    | order by TimeGenerated asc
    | render timechart
  KQL

  canary_exceptions_query = <<-KQL
    AppExceptions
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | extend Version = iff(isempty(AppVersion), "UNVERSIONED", AppVersion)
    | project
        TimeGenerated,
        Version,
        OuterType,
        OuterMessage,
        ProblemId,
        OperationId,
        AppRoleName,
        AppRoleInstance
    | order by TimeGenerated desc
    | take 50
  KQL
}
