# ==============================================================================
# main.tf – Root module orchestration
# ==============================================================================

# ------------------------------------------------------------------------------
# Fetch secrets from bootstrap Key Vault
# ------------------------------------------------------------------------------
data "azurerm_key_vault" "bootstrap" {
  name                = local.bootstrap_key_vault_name
  resource_group_name = local.bootstrap_state_rg
}

data "azurerm_key_vault_secret" "database_password" {
  name         = "DatabasePassword"
  key_vault_id = data.azurerm_key_vault.bootstrap.id
}

# ------------------------------------------------------------------------------
# State / ACR
# ------------------------------------------------------------------------------
module "state" {
  source = "./modules/state"

  resource_group_name = local.resource_group_name
  location            = var.location
  acr_name            = local.acr_name
  acr_sku             = var.acr_sku
  acr_admin_enabled   = false
  tags                = local.common_tags
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  resource_group_name            = module.state.resource_group_name
  location                       = var.location
  vnet_name                      = local.vnet_name
  vnet_address_space             = local.vnet_address_space
  aks_subnet_name                = local.aks_subnet_name
  aks_subnet_address_prefix      = local.aks_subnet_address_prefix
  pe_subnet_name                 = local.pe_subnet_name
  pe_subnet_address_prefix       = local.pe_subnet_address_prefix
  reserved_subnet_name           = local.reserved_subnet_name
  reserved_subnet_address_prefix = local.reserved_subnet_address_prefix
  nat_gateway_name               = local.nat_gateway_name
  nat_public_ip_name             = local.nat_public_ip_name
  aks_nsg_name                   = local.aks_nsg_name
  pe_nsg_name                    = local.pe_nsg_name
  private_dns_zone_name          = local.private_dns_zone_name
  private_dns_zone_link_name     = local.private_dns_zone_link_name
  tags                           = local.common_tags
}

# ------------------------------------------------------------------------------
# AKS with ESO Workload Identity
# ------------------------------------------------------------------------------
module "aks" {
  source = "./modules/aks"

  resource_group_name = module.state.resource_group_name
  location            = var.location
  cluster_name        = local.aks_cluster_name
  kubernetes_version  = var.aks_kubernetes_version
  vm_size             = var.aks_vm_size
  node_count          = var.aks_node_count
  os_disk_size_gb     = var.aks_os_disk_size_gb
  aks_subnet_id       = module.networking.aks_subnet_id
  acr_id              = module.state.acr_id
  service_cidr        = var.aks_service_cidr
  dns_service_ip      = var.aks_dns_service_ip
  pod_cidr            = var.aks_pod_cidr

  # Add these three lines
  eso_identity_name             = "eso-${local.project_abbr}-${local.env_abbr}-${local.sub_suffix}"
  eso_service_account_namespace = "external-secrets"
  eso_service_account_name      = "eso-azure-kv"

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Key Vault access for ESO Workload Identity
# ------------------------------------------------------------------------------
resource "azurerm_role_assignment" "eso_keyvault_secrets_user" {
  scope                = data.azurerm_key_vault.bootstrap.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.aks.eso_identity_principal_id
}

# ------------------------------------------------------------------------------
# PostgreSQL Flexible Server with Private Link
# ------------------------------------------------------------------------------
module "postgresql" {
  source = "./modules/postgresql"

  resource_group_name        = module.state.resource_group_name
  location                   = var.location
  server_name                = local.postgresql_server_name
  postgresql_version         = var.postgresql_version
  sku_name                   = var.postgresql_sku_name
  storage_mb                 = var.postgresql_storage_mb
  backup_retention_days      = var.postgresql_backup_retention_days
  administrator_login        = var.postgresql_administrator_login
  administrator_password     = data.azurerm_key_vault_secret.database_password.value
  database_name              = var.postgresql_database_name
  private_endpoint_subnet_id = module.networking.pe_subnet_id
  private_dns_zone_id        = module.networking.private_dns_zone_id
  tags                       = local.common_tags
}

# ------------------------------------------------------------------------------
# Observability
# ------------------------------------------------------------------------------
module "observability" {
  source = "./modules/observability"

  resource_group_name = module.state.resource_group_name
  location            = var.location
  environment         = var.environment

  log_analytics_workspace_name = local.log_analytics_workspace_name
  log_analytics_retention_days = var.log_analytics_retention_days

  application_insights_name = local.application_insights_name

  alert_email_address = var.alert_email_address

  aks_cluster_id       = module.aks.cluster_id
  postgresql_server_id = module.postgresql.server_id

  enable_cpu_alert              = var.enable_cpu_alert
  enable_memory_alert           = var.enable_memory_alert
  enable_pod_restarts_alert     = var.enable_pod_restarts_alert
  enable_failed_requests_alert  = var.enable_failed_requests_alert
  enable_postgres_storage_alert = var.enable_postgres_storage_alert

  enable_burn_rate_fast_alert = var.enable_burn_rate_fast_alert
  enable_burn_rate_slow_alert = var.enable_burn_rate_slow_alert
  enable_postgres_cpu_alert   = var.enable_postgres_cpu_alert

  enable_aks_diagnostics        = var.enable_aks_diagnostics
  enable_postgresql_diagnostics = var.enable_postgresql_diagnostics

  enable_app_slo_workbook  = var.enable_app_slo_workbook
  enable_infra_workbook    = var.enable_infra_workbook
  enable_database_workbook = var.enable_database_workbook
  enable_canary_workbook   = var.enable_canary_workbook

  application_insights_sampling_percentage = var.application_insights_sampling_percentage

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Azure DevOps application pipelines
# ------------------------------------------------------------------------------
module "azure_devops" {
  source = "./modules/azure_devops"

  project_name                    = var.ado_project_name
  github_service_connection_name  = var.ado_github_service_connection_name
  azure_service_connection_name   = var.ado_azure_service_connection_name
  github_owner                    = var.github_owner
  github_repo                     = var.github_repo
  branch                          = var.branch
  terraform_vars_group_name       = var.terraform_vars_group_name
  authorize_variable_group_for_ci = var.authorize_variable_group_for_ci
}
