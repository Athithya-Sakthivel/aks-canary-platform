# ==============================================================================
# variables.tf – Root module input variables for Task API AKS platform
# ==============================================================================

variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a valid Azure subscription GUID."
  }
}

variable "tenant_id" {
  description = "Azure tenant ID."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "tenant_id must be a valid Azure tenant GUID."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralindia"
}

variable "environment" {
  description = "Deployment environment (staging or prod)."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "owner" {
  description = "Owner tag value. Provided via TF_VAR_owner environment variable, not in .tfvars."
  type        = string
}

variable "tags" {
  description = "Additional tags merged with common tags."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# AKS
# ------------------------------------------------------------------------------

variable "aks_vm_size" {
  description = "VM size for the AKS node pool."
  type        = string
  default     = "Standard_D4s_v4"
}

variable "aks_node_count" {
  description = "Number of nodes (must be 1)."
  type        = number
  default     = 1
  validation {
    condition     = var.aks_node_count == 1
    error_message = "aks_node_count must be exactly 1."
  }
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "aks_os_disk_size_gb" {
  description = "OS disk size in GB."
  type        = number
  default     = 50
}

variable "aks_service_cidr" {
  description = "Kubernetes service CIDR."
  type        = string
  default     = "10.240.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "DNS service IP within service CIDR."
  type        = string
  default     = "10.240.0.10"
}

variable "aks_pod_cidr" {
  description = "Pod CIDR for Azure CNI Overlay."
  type        = string
  default     = "10.244.0.0/16"
}

# ------------------------------------------------------------------------------
# PostgreSQL
# ------------------------------------------------------------------------------

variable "postgresql_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "18"
}

variable "postgresql_sku_name" {
  description = "SKU name."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgresql_storage_mb" {
  description = "Storage size in MB."
  type        = number
  default     = 32768
}

variable "postgresql_backup_retention_days" {
  description = "Backup retention days (7-35)."
  type        = number
  default     = 7
}

variable "postgresql_administrator_login" {
  description = "Administrator username."
  type        = string
  default     = "taskuser"
}

variable "postgresql_database_name" {
  description = "Database name."
  type        = string
  default     = "taskdb"
}

# ------------------------------------------------------------------------------
# ACR
# ------------------------------------------------------------------------------

variable "acr_sku" {
  description = "ACR SKU."
  type        = string
  default     = "Basic"
}
# ------------------------------------------------------------------------------
# Observability
# ------------------------------------------------------------------------------

variable "alert_email_address" {
  description = "Email address used by the Azure Monitor observability action group."
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

variable "log_analytics_retention_days" {
  description = "Default Log Analytics workspace analytics retention period in days."
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

variable "enable_cpu_alert" {
  description = "Enable the AKS node CPU alert."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_memory_alert" {
  description = "Enable the AKS node memory alert."
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
  description = "Enable the Application Insights failed-request alert."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_postgres_storage_alert" {
  description = "Enable the PostgreSQL storage percentage alert."
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
  description = "Enable the Database workbook."
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

# ------------------------------------------------------------------------------
# Azure DevOps
# ------------------------------------------------------------------------------

variable "ado_project_name" {
  description = "Azure DevOps project name (created by bootstrap)."
  type        = string
}

variable "ado_github_service_connection_name" {
  description = "GitHub service connection name."
  type        = string
  default     = "github-pat"
}

variable "ado_azure_service_connection_name" {
  description = "Azure service connection name."
  type        = string
  default     = "azdo-oidc-cd"
}

variable "github_owner" {
  description = "GitHub repository owner."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "branch" {
  description = "Default branch."
  type        = string
  default     = "main"
}

variable "terraform_vars_group_name" {
  description = "Existing variable group name."
  type        = string
  default     = "terraform-vars"
}

variable "authorize_variable_group_for_ci" {
  description = "Authorize variable group for CI pipelines."
  type        = bool
  default     = false
}
