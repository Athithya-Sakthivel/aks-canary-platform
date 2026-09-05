# ============================================================================
# modules/observability/locals.tf
# ============================================================================

locals {
  environment_normalized = lower(trimspace(var.environment))

  workbook_name = uuidv5(
    "url",
    "https://taskapi.example.invalid/observability/workbook/${local.environment_normalized}/${azurerm_application_insights.this.name}"
  )

  workbook_workspace_id            = lower(azurerm_log_analytics_workspace.this.id)
  workbook_application_insights_id = lower(azurerm_application_insights.this.id)
  workbook_postgresql_server_id    = lower(coalesce(var.postgresql_server_id, ""))

  # ---------------------------------------------------------------------------
  # Existing generic workbook queries
  # ---------------------------------------------------------------------------

  workbook_request_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | summarize
        RequestCount = sum(ItemCount),
        FailedCount = sumif(ItemCount, Success == false)
      by bin(TimeGenerated, 1h)
    | extend FailureRate = iff(
        RequestCount == 0,
        0.0,
        100.0 * todouble(FailedCount) / todouble(RequestCount)
      )
    | project TimeGenerated, RequestCount, FailedCount, FailureRate
    | order by TimeGenerated asc
  KQL

  workbook_dependency_query = <<-KQL
    AppDependencies
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | summarize
        DependencyCount = sum(ItemCount),
        FailedCount = sumif(ItemCount, Success == false)
      by bin(TimeGenerated, 1h)
    | extend FailureRate = iff(
        DependencyCount == 0,
        0.0,
        100.0 * todouble(FailedCount) / todouble(DependencyCount)
      )
    | project TimeGenerated, DependencyCount, FailedCount, FailureRate
    | order by TimeGenerated asc
  KQL

  workbook_exception_query = <<-KQL
    AppExceptions
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | summarize ExceptionCount = sum(ItemCount) by bin(TimeGenerated, 1h)
    | project TimeGenerated, ExceptionCount
    | order by TimeGenerated asc
  KQL

  workbook_metric_query = <<-KQL
    AppMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | where ItemCount > 0
    | summarize
        TotalValue = sum(Sum),
        SampleCount = sum(ItemCount)
      by Name, bin(TimeGenerated, 5m)
    | extend AverageValue = iff(
        SampleCount == 0,
        real(null),
        todouble(TotalValue) / todouble(SampleCount)
      )
    | project TimeGenerated, Name, AverageValue
    | order by TimeGenerated asc
  KQL

  workbook_snapshot_query = <<-KQL
    let TotalRequests = toscalar(
      AppRequests
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | summarize sum(ItemCount)
    );

    let FailedRequests = toscalar(
      AppRequests
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | where Success == false
      | summarize sum(ItemCount)
    );

    let Dependencies = toscalar(
      AppDependencies
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | summarize sum(ItemCount)
    );

    let Exceptions = toscalar(
      AppExceptions
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | summarize sum(ItemCount)
    );

    let SafeRequests = tolong(coalesce(TotalRequests, 0));
    let SafeFailedRequests = tolong(coalesce(FailedRequests, 0));
    let SafeDependencies = tolong(coalesce(Dependencies, 0));
    let SafeExceptions = tolong(coalesce(Exceptions, 0));

    print
      Requests24h = SafeRequests,
      FailedRequests24h = SafeFailedRequests,
      FailureRate24h = iff(
        SafeRequests == 0,
        0.0,
        100.0 * todouble(SafeFailedRequests) / todouble(SafeRequests)
      ),
      Dependencies24h = SafeDependencies,
      Exceptions24h = SafeExceptions
  KQL

  # ---------------------------------------------------------------------------
  # Workbook identifiers
  # ---------------------------------------------------------------------------

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
  # Application SLO dashboard queries
  #
  # ItemCount is the telemetry weight for sampled Application Insights records.
  # percentilew() therefore preserves the intended weighting.
  # ---------------------------------------------------------------------------

  app_slo_snapshot_query = <<-KQL
    let Total = toscalar(
      AppRequests
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | summarize sum(ItemCount)
    );

    let Failed = toscalar(
      AppRequests
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | where Success == false
      | summarize sum(ItemCount)
    );

    let P95 = toscalar(
      AppRequests
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_application_insights_id}'
      | where isnotnull(DurationMs)
      | where ItemCount > 0
      | summarize percentilew(DurationMs, ItemCount, 95)
    );

    let SafeTotal = tolong(coalesce(Total, 0));
    let SafeFailed = tolong(coalesce(Failed, 0));

    print
      Availability = iff(
        SafeTotal == 0,
        100.0,
        100.0 * (1.0 - todouble(SafeFailed) / todouble(SafeTotal))
      ),
      RequestCount24h = SafeTotal,
      P95LatencyMs = todouble(coalesce(P95, 0.0)),
      ErrorRate = iff(
        SafeTotal == 0,
        0.0,
        100.0 * todouble(SafeFailed) / todouble(SafeTotal)
      )
  KQL

  app_slo_latency_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | where isnotnull(DurationMs)
    | where ItemCount > 0
    | summarize
        P95 = percentilew(DurationMs, ItemCount, 95),
        P50 = percentilew(DurationMs, ItemCount, 50)
      by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  app_slo_traffic_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | summarize RequestCount = sum(ItemCount) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
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
  KQL

  app_slo_custom_metrics_query = <<-KQL
    AppMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | where Name in (
        "task_created_total",
        "auth_success_total",
        "auth_failure_total"
      )
    | summarize MetricSum = sum(Sum) by Name, bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  # ---------------------------------------------------------------------------
  # Infrastructure dashboard queries
  # ---------------------------------------------------------------------------

  infra_aks_control_plane_query = <<-KQL
    AKSControlPlane
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | summarize EventCount = count() by Category, bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  infra_aks_api_errors_query = <<-KQL
    AKSControlPlane
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where Level in~ ("Error", "Fatal")
    | summarize ErrorCount = count() by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  infra_node_cpu_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where MetricName in~ (
        "CPU Usage Percentage",
        "node_cpu_usage_percentage"
      )
    | summarize AvgCPU = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  infra_node_memory_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where MetricName in~ (
        "Memory Working Set Percentage",
        "node_memory_working_set_percentage"
      )
    | summarize AvgMemory = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  infra_node_disk_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${lower(var.aks_cluster_id)}'
    | where MetricName in~ (
        "Disk Used Percentage",
        "node_disk_usage_percentage"
      )
    | summarize AvgDisk = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  # ---------------------------------------------------------------------------
  # Database dashboard queries
  # ---------------------------------------------------------------------------

  database_connections_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
    | where MetricName in~ (
        "Active Connections",
        "active_connections"
      )
    | summarize AvgConnections = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  database_cpu_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
    | where MetricName in~ (
        "CPU percent",
        "cpu_percent"
      )
    | summarize AvgCPU = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  database_storage_query = <<-KQL
    AzureMetrics
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
    | where MetricName in~ (
        "Storage percent",
        "storage_percent"
      )
    | summarize AvgStorage = avg(Average) by bin(TimeGenerated, 10m)
    | order by TimeGenerated asc
  KQL

  # Query Store is the appropriate source for query-performance analysis.
  database_slow_queries_query = <<-KQL
    let Runtime =
      PGSQLQueryStoreRuntime
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
      | where isnotempty(QueryId)
      | summarize
          AvgExecDurationMs = avg(MeanExecDurationMs),
          MaxExecDurationMs = max(MaxExecDurationMs),
          TotalExecDurationMs = sum(TotalExecDurationMs)
        by _ResourceId, QueryId, QueryType;

    let QueryText =
      PGSQLQueryStoreQueryText
      | where TimeGenerated > ago(24h)
      | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
      | where isnotempty(QueryId)
      | summarize arg_max(TimeGenerated, QueryText) by _ResourceId, QueryId;

    Runtime
    | join kind=leftouter QueryText on _ResourceId, QueryId
    | project
        QueryId,
        QueryType,
        AvgExecDurationMs,
        MaxExecDurationMs,
        TotalExecDurationMs,
        QueryText
    | top 20 by AvgExecDurationMs desc
  KQL

  database_errors_query = <<-KQL
    PGSQLServerLogs
    | where TimeGenerated > ago(24h)
    | where _ResourceId =~ '${local.workbook_postgresql_server_id}'
    | where ErrorLevel in~ ("ERROR", "FATAL", "PANIC")
    | project
        TimeGenerated,
        ErrorLevel,
        Message,
        Detail,
        SqlErrorCode,
        Query,
        Statement
    | order by TimeGenerated desc
    | take 100
  KQL

  # ---------------------------------------------------------------------------
  # Canary release dashboard queries
  # ---------------------------------------------------------------------------

  canary_failure_rate_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | summarize
        Total = sum(ItemCount),
        Failed = sumif(ItemCount, Success == false)
      by bin(TimeGenerated, 5m)
    | extend ErrorRate = iff(
        Total == 0,
        0.0,
        100.0 * todouble(Failed) / todouble(Total)
      )
    | project TimeGenerated, ErrorRate
    | order by TimeGenerated asc
  KQL

  canary_latency_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | where isnotnull(DurationMs)
    | where ItemCount > 0
    | summarize P95 = percentilew(DurationMs, ItemCount, 95) by bin(TimeGenerated, 5m)
    | order by TimeGenerated asc
  KQL

  canary_exceptions_query = <<-KQL
    AppExceptions
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | project
        TimeGenerated,
        OuterType,
        OuterMessage,
        ProblemId,
        OperationId,
        AppRoleName,
        AppRoleInstance,
        AppVersion
    | order by TimeGenerated desc
    | take 50
  KQL

  canary_instance_split_query = <<-KQL
    AppRequests
    | where TimeGenerated > ago(1h)
    | where _ResourceId =~ '${local.workbook_application_insights_id}'
    | summarize RequestCount = sum(ItemCount)
      by AppVersion, AppRoleInstance, bin(TimeGenerated, 5m)
    | order by TimeGenerated asc
  KQL
}
