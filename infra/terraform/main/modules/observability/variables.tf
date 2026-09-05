variable "resource_group_name" {
  description = "Name of the Azure resource group containing the observability resources."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for the observability resources."
  type        = string
  default     = "centralindia"
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  nullable    = false

  validation {
    condition = contains(
      ["staging", "prod"],
      lower(trimspace(var.environment))
    )
    error_message = "environment must be either staging or prod."
  }
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace."
  type        = string
  nullable    = false

  validation {
    condition = can(
      regex(
        "^[A-Za-z0-9][A-Za-z0-9-]{2,61}[A-Za-z0-9]$",
        trimspace(var.log_analytics_workspace_name)
      )
    )
    error_message = "log_analytics_workspace_name must be 4-63 characters and contain only letters, digits, and hyphens, without a leading or trailing hyphen."
  }
}

variable "log_analytics_retention_days" {
  description = "Log Analytics retention period in days."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition = (
      var.log_analytics_retention_days >= 30 &&
      var.log_analytics_retention_days <= 730 &&
      floor(var.log_analytics_retention_days) == var.log_analytics_retention_days
    )
    error_message = "log_analytics_retention_days must be an integer between 30 and 730."
  }
}

variable "application_insights_name" {
  description = "Name of the Application Insights component."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.application_insights_name)) > 0
    error_message = "application_insights_name must not be empty."
  }
}

variable "alert_email_address" {
  description = "Email address used by the Azure Monitor action group."
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition = can(
      regex(
        "^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$",
        trimspace(var.alert_email_address)
      )
    )
    error_message = "alert_email_address must be a valid email address."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Server-side Application Insights sampling percentage."
  type        = number
  default     = 100
  nullable    = false

  validation {
    condition = (
      var.application_insights_sampling_percentage >= 1 &&
      var.application_insights_sampling_percentage <= 100 &&
      floor(var.application_insights_sampling_percentage) == var.application_insights_sampling_percentage
    )
    error_message = "application_insights_sampling_percentage must be an integer between 1 and 100."
  }
}

variable "aks_cluster_id" {
  description = "ARM resource ID of the AKS managed cluster."
  type        = string
  nullable    = false

  validation {
    condition = can(
      regex(
        "^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerService/managedClusters/[^/]+$",
        trimspace(var.aks_cluster_id)
      )
    )
    error_message = "aks_cluster_id must be a Microsoft.ContainerService/managedClusters resource ID."
  }
}

variable "postgresql_server_id" {
  description = "ARM resource ID of the PostgreSQL Flexible Server. Required when the Database workbook is enabled."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.postgresql_server_id == null ||
      can(
        regex(
          "^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.DBforPostgreSQL/flexibleServers/[^/]+$",
          trimspace(var.postgresql_server_id)
        )
      )
    )
    error_message = "postgresql_server_id must be null or a Microsoft.DBforPostgreSQL/flexibleServers resource ID."
  }
}

variable "enable_cpu_alert" {
  description = "Enable the AKS node CPU metric alert."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_memory_alert" {
  description = "Enable the AKS node memory metric alert."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_pod_restarts_alert" {
  description = "Enable the pod restart scheduled query alert."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_failed_requests_alert" {
  description = "Enable the Application Insights failed request rate alert."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_postgres_storage_alert" {
  description = "Enable the PostgreSQL storage percentage metric alert."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_aks_diagnostics" {
  description = "Enable Azure Monitor diagnostics for AKS control-plane logs and metrics."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_postgresql_diagnostics" {
  description = "Enable Azure Monitor diagnostics for PostgreSQL Flexible Server logs and metrics."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_app_slo_workbook" {
  description = "Enable the Application SLO workbook."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_infra_workbook" {
  description = "Enable the Infrastructure workbook."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_database_workbook" {
  description = "Enable the Database workbook. Requires postgresql_server_id."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_canary_workbook" {
  description = "Enable the Canary Release workbook."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Tags applied to observability resources."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "enable_burn_rate_fast_alert" {
  description = "Enable the fast error-budget burn-rate scheduled query alert using a 5-minute evaluation window."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_burn_rate_slow_alert" {
  description = "Enable the slow error-budget burn-rate scheduled query alert using a 1-hour evaluation window."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_postgres_cpu_alert" {
  description = "Enable the PostgreSQL Flexible Server CPU metric alert. Requires postgresql_server_id to be non-null."
  type        = bool
  default     = true
  nullable    = false
}
