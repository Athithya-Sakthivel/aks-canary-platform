# Azure Pipelines – Task API CI/CD

Continuous integration and delivery for the **Task API** platform.

CI validates each service independently. CD builds immutable images, scans them, and deploys to AKS using **Argo Rollouts canary releases** for both backend and frontend. Terraform has a separate plan/apply pipeline.

## Directory layout

```sh
azure-pipelines/
├── ci/
│   ├── ci-backend.yaml
│   ├── ci-frontend.yaml
│   ├── ci-terraform.yaml
│   └── full_repo_security_scan.yaml
├── cd/
│   ├── cd-backend.yaml
│   ├── cd-frontend.yaml
│   └── cd-terraform.yaml
├── templates/
│   └── docker-build-push.yaml
├── scripts/
│   ├── backend-deploy.sh
│   ├── frontend-deploy.sh
│   └── trivy_report.py
├── tests/
│   ├── k6/
│   │   ├── backend-load.ts
│   │   └── frontend-load.ts
│   └── playwright/
│       ├── playwright.config.ts
│       └── task-api.spec.ts
└── README.md
```

## CI pipelines

All CI pipelines run on Microsoft-hosted `ubuntu-24.04` agents. CI does **not** build Docker images or deploy.

| Pipeline                       | Trigger                   | Purpose                                                                                   |
| ------------------------------ | ------------------------- | ----------------------------------------------------------------------------------------- |
| `ci-backend.yaml`              | `services/backend/**`     | Maven build, unit tests, Testcontainers integration tests, SpotBugs, package verification |
| `ci-frontend.yaml`             | `services/frontend/**`    | `npm ci`, TypeScript type check, ESLint, unit tests, production Vite build                |
| `ci-terraform.yaml`            | `infra/terraform/main/**` | `tofu fmt -check`, `tofu validate`, `tofu plan`, publish plan artifact                    |
| `full_repo_security_scan.yaml` | Push to `main`            | OpenGrep SAST, Gitleaks secrets, Trivy vulnerability scan                                 |

## CD pipelines

CD runs only after the corresponding CI succeeds on `main`, or manually for Terraform apply.

| Pipeline            | Trigger                         | Purpose                                                                               |
| ------------------- | ------------------------------- | ------------------------------------------------------------------------------------- |
| `cd-backend.yaml`   | `ci-backend` success on `main`  | Build backend image, Trivy scan, push to ACR, canary deploy via `backend-deploy.sh`   |
| `cd-frontend.yaml`  | `ci-frontend` success on `main` | Build frontend image, Trivy scan, push to ACR, canary deploy via `frontend-deploy.sh` |
| `cd-terraform.yaml` | Manual                          | Apply the exact Terraform plan artifact produced by `ci-terraform`                    |

Both application CD pipelines use the **Argo Rollouts canary strategy**. The backend and frontend `*-deploy.sh` scripts manage stable and canary rollouts, traffic shifting, k6 load testing, Playwright UI validation, and automatic rollback.

## Environment variables and secrets

### Application runtime — Kubernetes Secrets

The application containers consume these environment variables from Kubernetes Secrets. In AKS, the Secrets are synced from Azure Key Vault by External Secrets Operator.

#### `backend-secrets` namespace `task-api`

| Environment variable                    | Required | Purpose                                      |
| --------------------------------------- | -------- | -------------------------------------------- |
| `DATABASEURL`                           | yes      | PostgreSQL JDBC URL                          |
| `DATABASEUSERNAME`                      | yes      | PostgreSQL user                              |
| `DATABASEPASSWORD`                      | yes      | PostgreSQL password                          |
| `JWTSECRET`                             | yes      | JWT signing key                              |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | yes      | Azure Application Insights connection string |

#### `frontend-secrets` namespace `task-api`

| Environment variable                    | Required | Purpose                                |
| --------------------------------------- | -------- | -------------------------------------- |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | yes      | Browser Application Insights telemetry |

#### `cloudflared-token` namespace `cloudflared`

| Secret key | Required | Purpose                 |
| ---------- | -------- | ----------------------- |
| `token`    | yes      | Cloudflare Tunnel token |

### Azure Key Vault secrets

All secrets are stored in the bootstrap Key Vault (`kv-azdo-bootstrap-<subscription-suffix>`) and fetched at runtime using the `AzureKeyVault@2` task in Azure Pipelines.

| Key Vault secret name                 | Used by                                                         |
| ------------------------------------- | --------------------------------------------------------------- |
| `azdo-pat`                            | Terraform CD pipeline to authenticate the Azure DevOps provider |
| `DatabaseUrl`                         | ESO → `backend-secrets`                                         |
| `DatabaseUsername`                    | ESO → `backend-secrets`                                         |
| `DatabasePassword`                    | ESO → `backend-secrets`                                         |
| `JwtSecret`                           | ESO → `backend-secrets`                                         |
| `ApplicationInsightsConnectionString` | ESO → `backend-secrets` and `frontend-secrets`                  |
| `CloudflareTunnelToken`               | ESO → `cloudflared-token`                                       |

### Azure DevOps variable group — `terraform-vars`

The `terraform-vars` variable group contains **non-secret** values only. Secrets are not stored in variable groups.

| Variable                        | Purpose                                         |
| ------------------------------- | ----------------------------------------------- |
| `TF_VAR_location`               | Azure region                                    |
| `TF_VAR_alert_email_address`    | Azure Monitor alert email                       |
| `TF_VAR_owner`                  | Owner tag                                       |
| `TF_VAR_DOMAIN`                 | Public domain for Cloudflare/Tunnel DNS         |
| `AZDO_ORG_SERVICE_URL`          | Azure DevOps organization URL                   |
| `TF_VAR_cloudflare_tunnel_name` | Cloudflare Tunnel name                          |
| `TF_VAR_cloudflare_tunnel_id`   | Cloudflare Tunnel ID (optional, may be derived) |

Environment-specific values live in `.tfvars` files:

```text
infra/terraform/main/environments/staging.tfvars
infra/terraform/main/environments/prod.tfvars
```

Those files are not secrets and are not stored in variable groups.

## Authentication model

- **Azure-to-Azure** uses OIDC federation. No client secrets or connection strings are stored in pipeline variables.
- **Terraform state** is stored in Azure Blob Storage with Azure AD authentication (`storage_use_azuread = true`).
- **AKS workloads** use Workload Identity for Azure Key Vault and ACR access, not static credentials.

## Key design decisions

- **CI per service** – independent path filters for fast feedback.
- **CD builds images** – CI never builds; CD builds, scans, pushes, and deploys.
- **Canary for both backend and frontend** – Argo Rollouts with Gateway API traffic splitting, k6 load testing, Playwright UI tests, and automatic rollback.
- **Immutable images** – Git commit SHA tags, pinned by digest.
- **Plan/apply separation** – `ci-terraform` plans, `cd-terraform` applies.
- **Secrets in Key Vault, config in variable group** – clear boundary.
- **External Secrets Operator** – syncs Azure Key Vault secrets into Kubernetes.
- **No dummy telemetry** – Application Insights connection string is real; missing values disable telemetry instead of pointing at localhost.

## How a deployment works

1. Push to `services/backend/**` → `ci-backend` runs tests.
2. Push to `services/frontend/**` → `ci-frontend` runs lint/typecheck/build.
3. Merge to `main` → relevant CD pipeline builds image, scans, pushes, then `backend-deploy.sh` or `frontend-deploy.sh` performs a canary rollout.
4. Terraform changes are planned automatically and applied manually via `cd-terraform`.
5. Security scan runs on every push to `main`.

## Adding a new service

1. Add code under `services/<new-service>/`.
2. Create `ci-<service>.yaml` and `cd-<service>.yaml`.
3. Reuse `docker-build-push.yaml`.
4. Add required variables to `terraform-vars` via Terraform bootstrap.
5. Add required Key Vault secrets and ESO `ExternalSecret` entries if needed.
6. Update this README.
