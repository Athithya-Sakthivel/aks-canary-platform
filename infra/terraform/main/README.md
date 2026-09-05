# Terraform — AKS Platform Infrastructure

This directory contains the Terraform configuration for the **Task API platform**:
a production-style, Kubernetes-based application stack running on Azure.

---

## What This Provisions

| Component                      | Description                                            |
| ------------------------------ | ------------------------------------------------------ |
| **Azure Virtual Network**      | Subnets, NAT Gateway, NSGs, private DNS zone           |
| **Azure Kubernetes Service**   | Single-node cluster, Azure CNI Overlay, Cilium         |
| **PostgreSQL Flexible Server** | Private endpoint, no public exposure                   |
| **Azure Container Registry**   | Private container image storage                        |
| **Observability**              | Log Analytics, Application Insights, alerts, workbooks |
| **Azure DevOps**               | CI/CD pipelines and variable group integration         |

---

## Architecture

```
Azure DevOps (CI/CD)
        │
        ▼
GitHub Repository
        │
        ▼
Terraform (main/)
        │
        ├── AKS Cluster
        ├── PostgreSQL Flexible Server
        ├── Azure Container Registry
        ├── Virtual Network + NAT Gateway
        ├── Observability (4 workbooks + alerts)
        └── Azure DevOps Pipelines
```

External application access is handled separately by **Cloudflare Tunnel**.

---

## Module Inventory

| Module          | Purpose                                     |
| --------------- | ------------------------------------------- |
| `state`         | Resource group and container registry       |
| `networking`    | Virtual network, subnets, NAT Gateway, DNS  |
| `aks`           | Kubernetes cluster, identity, node pool     |
| `postgresql`    | Database server, database, private endpoint |
| `observability` | Monitoring, alerting, dashboards            |
| `azure_devops`  | CI/CD pipelines and variable group          |

---

## Observability

### Workbooks

Four focused dashboards, each a **single-page, two-column grid**:

| Workbook            | Key Panels                                                                 |
| ------------------- | -------------------------------------------------------------------------- |
| **Application SLO** | Availability, P95 latency, traffic, error rate, business metrics, JVM heap |
| **Infrastructure**  | API server errors, node CPU/memory/disk, pod restarts                      |
| **Database**        | Active connections, CPU, storage                                           |
| **Canary Release**  | Traffic split, error rate, P95 latency, exceptions                         |

All workbooks are **locked** to Terraform—no portal edits.

### Alerts

| Alert                  | Type            | Threshold      |
| ---------------------- | --------------- | -------------- |
| AKS CPU                | Metric          | >80% (15m avg) |
| AKS Memory             | Metric          | >90% (15m avg) |
| Pod Restarts           | Scheduled Query | >5 in 15m      |
| Failed Requests        | Scheduled Query | >5% (15m)      |
| PostgreSQL Storage     | Metric          | >80%           |
| PostgreSQL CPU         | Metric          | >80%           |
| Fast Error Budget Burn | Scheduled Query | 20x (5m)       |
| Slow Error Budget Burn | Scheduled Query | 5x (1h)        |

---

## Environment Configuration

Environment-specific values are stored in:

```
environments/
├── staging.tfvars
└── prod.tfvars
```

Global or sensitive values are provided via `TF_VAR_*` environment variables:

```bash
export TF_VAR_owner="<owner-name>"
export TF_VAR_alert_email_address="<alert-email>"
export TF_BACKEND_AUTH_MODE="cli"
```

---

## Running Terraform

```bash
cd infra/terraform/main

# Plan
bash run.sh --plan --env staging

# Apply
bash run.sh --create --env staging

# Refresh state
bash run.sh --refresh --env staging

# Destroy
bash run.sh --destroy --env staging --yes-delete

# Validate only
bash run.sh --validate --env staging
```

`run.sh` handles:

- OpenTofu installation and provider setup
- Azure subscription/tenant resolution
- AKS service-tag feature registration
- Post-apply AKS API configuration
- Application Insights connection string storage in Key Vault

---

## Outputs

| Output                                    | Purpose                      |
| ----------------------------------------- | ---------------------------- |
| `resource_group_name` / `id`              | Resource group references    |
| `acr_name`, `acr_login_server`, `acr_id`  | Container registry access    |
| `aks_cluster_name`, `aks_cluster_id`      | AKS identification           |
| `aks_oidc_issuer_url`                     | Workload identity federation |
| `aks_kubelet_identity_object_id`          | ACR pull validation          |
| `postgresql_server_fqdn`, `database_name` | Backend configuration        |
| `application_insights_connection_string`  | Telemetry (sensitive)        |
| `log_analytics_workspace_customer_id`     | Log querying                 |
| Workbook IDs                              | Dashboard references         |
| Pipeline IDs                              | CI/CD pipeline management    |

---

## File Structure

```sh
infra/terraform/main
├── .bootstrap.generated.env              # Bootstrap environment values (auto-generated)
├── .terraform.lock.hcl                   # Pinned provider versions
├── README.md                             # Module documentation
├── environments
│   ├── prod.tfvars                       # Production environment values
│   └── staging.tfvars                    # Staging environment values
├── locals.tf                             # Derived names, tags, and common locals
├── main.tf                               # Root orchestration and module wiring
├── modules
│   ├── aks
│   │   ├── main.tf                       # AKS cluster, identity, node pool
│   │   ├── outputs.tf                    # AKS module outputs
│   │   ├── variables.tf                  # AKS module inputs
│   │   └── versions.tf                   # AKS provider constraints
│   ├── azure_devops
│   │   ├── outputs.tf                    # Azure DevOps module outputs
│   │   ├── pipelines.tf                  # CI/CD pipeline definitions
│   │   ├── variable_group.tf             # Variable group configuration
│   │   ├── variables.tf                  # Azure DevOps module inputs
│   │   └── versions.tf                   # Azure DevOps provider constraints
│   ├── networking
│   │   ├── main.tf                       # VNet, subnets, NAT Gateway, DNS
│   │   ├── outputs.tf                    # Networking module outputs
│   │   ├── variables.tf                  # Networking module inputs
│   │   └── versions.tf                   # Networking provider constraints
│   ├── observability
│   │   ├── alerts.tf                     # Metric alerts, scheduled query rules
│   │   ├── diagnostic_settings.tf        # AKS/PostgreSQL diagnostic logging
│   │   ├── locals.tf                     # KQL queries and workbook names
│   │   ├── main.tf                       # Log Analytics + Application Insights
│   │   ├── outputs.tf                    # Observability module outputs
│   │   ├── variables.tf                  # Observability module inputs
│   │   ├── versions.tf                   # Observability provider constraints
│   │   ├── workbook_app_slo.json.tftpl   # Application SLO dashboard template
│   │   ├── workbook_canary.json.tftpl    # Canary release dashboard template
│   │   ├── workbook_database.json.tftpl  # Database dashboard template
│   │   ├── workbook_infra.json.tftpl     # Infrastructure dashboard template
│   │   └── workbooks.tf                  # All four workbook resources
│   ├── postgresql
│   │   ├── main.tf                       # PostgreSQL server, database, endpoint
│   │   ├── outputs.tf                    # PostgreSQL module outputs
│   │   ├── variables.tf                  # PostgreSQL module inputs
│   │   └── versions.tf                   # PostgreSQL provider constraints
│   └── state
│       ├── acr.tf                        # Azure Container Registry
│       ├── main.tf                       # Resource group creation
│       ├── outputs.tf                    # State module outputs
│       ├── variables.tf                  # State module inputs
│       └── versions.tf                   # State provider constraints
├── outputs.tf                            # Root module outputs
├── providers.tf                          # AzureRM, AzureAD, Azure DevOps providers
├── run.sh                                # Terraform runner (plan/apply/destroy)
├── variables.tf                          # Root module inputs
└── versions.tf                           # Root provider constraints and backend
```

---

## Related Directories

- `infra/terraform/bootstrap/` — Azure DevOps bootstrap and remote state storage
- `infra/terraform/edge/` — Cloudflare Tunnel and DNS
- `azure-pipelines/` — CI/CD pipeline definitions
- `infra/k8s/` — Helm charts for in-cluster components

---

## Design Notes

- **Single-node AKS**: Cost-optimised for development; production should scale out.
- **Private PostgreSQL**: Accessible only via Private Link.
- **Workload Identity**: OIDC federation for AKS and Azure DevOps.
- **Remote State**: Stored in Azure Storage, backend configured dynamically.
- **IaC-only Workbooks**: Dashboards are locked and managed entirely via Terraform.
