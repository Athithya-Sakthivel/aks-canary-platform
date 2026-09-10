# Task API Canary Platform

A production-style, end-to-end platform demonstrating **progressive delivery (canary deployments)** on Azure Kubernetes Service with full **observability**, **GitOps-driven CI/CD**, and **zero-trust secret management**.

The system deploys a React frontend and Spring Boot backend on AKS, routes external traffic through a Cloudflare Tunnel (no public IPs on nodes), and uses Argo Rollouts with Envoy Gateway to perform canary releases with automated validation and rollback.

---

## Table of Contents

- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Deployment Guide](#deployment-guide)
  - [PHASE 0: Local Environment Setup](#phase-0-local-environment-setup)
  - [PHASE 1: Cloud Infrastructure](#phase-1-cloud-infrastructure)
  - [PHASE 2: Canary Deployment](#phase-2-canary-deployment)
  - [PHASE 3: Validation](#phase-3-validation)
- [Observability](#observability)
- [Local Development with Kind](#local-development-with-kind)
- [Cleanup](#cleanup)

---

## Architecture

```
                          ┌────────────────────┐
                          │    Internet        │
                          └──────────┬─────────┘
                                     │
                                     ▼
                          ┌────────────────────┐
                          │  Cloudflare Edge   │
                          └──────────┬─────────┘
                                     │ (Tunnel — outbound only)
                                     ▼
                    ┌────────────────────────────────┐
                    │   AKS Cluster (private)        │
                    │                                │
                    │   ┌──────────────────────┐     │
                    │   │   cloudflared        │     │
                    │   └──────────┬───────────┘     │
                    │              ▼                 │
                    │   ┌──────────────────────┐     │
                    │   │   Envoy Gateway      │     │
                    │   │   (Gateway API)      │     │
                    │   └──────────┬───────────┘     │
                    │              ▼                 │
                    │   ┌──────────────────────┐     │
                    │   │   Argo Rollouts      │     │
                    │   │  (frontend/backend)  │     │
                    │   └────┬─────────────┬───┘     │
                    │        ▼             ▼         │
                    │   ┌─────────┐   ┌──────────┐   │
                    │   │Frontend │   │ Backend  │   │
                    │   │(React)  │   │(Spring)  │   │
                    │   └─────────┘   └────┬─────┘   │
                    │                      ▼         │
                    │              ┌────────────┐    │
                    │              │ PostgreSQL │    │
                    │              │ (private)  │    │
                    │              └────────────┘    │
                    └────────────────────────────────┘

   Telemetry ────► Application Insights (workspace-based) ────► Log Analytics
                                                                     │
                                                                     ▼
                                                            Azure Monitor Workbooks
                                                            + Burn-Rate Alerts
```

**Key design decisions:**

- **Cloudflare Tunnel** — Cluster is fully private; no inbound ports or public IPs.
- **Envoy Gateway (Gateway API)** — Provides `GatewayClass: eg` for Argo Rollouts traffic routing on AKS.
- **Argo Rollouts** — Canary with 0% → validate → 10% → observe → 100% promotion flow.
- **External Secrets Operator** — Workload Identity Federation to Azure Key Vault; no long-lived credentials.
- **OIDC everywhere** — Azure DevOps service connections use federated identity.
- **Immutable image tags** — Every deployment uses a commit SHA, never `latest` or `v1/v2`.

---

## Tech Stack

| Layer                   | Technology                                                                     |
| ----------------------- | ------------------------------------------------------------------------------ |
| Frontend                | React 19, Vite, nginx-unprivileged, Application Insights browser SDK           |
| Backend                 | Spring Boot 3.5 (Java 21), Flyway, Micrometer, App Insights Java agent         |
| Database                | Azure Database for PostgreSQL Flexible Server (private endpoint)               |
| Container Orchestration | AKS with Azure CNI Overlay + Cilium dataplane                                  |
| Ingress                 | Cloudflare Tunnel + Envoy Gateway (Gateway API)                                |
| Progressive Delivery    | Argo Rollouts (Gateway API plugin) + HPA                                       |
| Secrets                 | Azure Key Vault + External Secrets Operator (Workload Identity)                |
| CI/CD                   | Azure DevOps Pipelines (OIDC, SHA-tagged images)                               |
| IaC                     | OpenTofu (Terraform-compatible) with AzureRM 5.x                               |
| Observability           | Application Insights, Log Analytics, Azure Monitor Workbooks, Burn-Rate Alerts |
| Testing                 | Playwright (UI), k6 (load), Trivy (security scan)                              |

---

## Prerequisites

1. **Docker** installed and running without `sudo`:

   ```bash
   sudo usermod -aG docker $USER && newgrp docker
   ```

2. **VS Code + Dev Containers extension** — for reproducible toolchain (recommended):
   - [Install Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)

3. **Azure subscription** with permissions to create:
   - AKS, Azure Monitor, Storage Account, Key Vault, PostgreSQL Flexible Server
   - Entra ID, managed identities, Workload Identity Federation, RBAC

4. **Cloudflare account** with a registered domain (DNS + Tunnel permissions).

5. **Azure DevOps organization** — must be created manually via [portal](https://learn.microsoft.com/azure/devops/organizations/accounts/create-organization) if not already present.

---

## Repository Structure

```
aks-canary-platform/
├── azure-pipelines/           # CI/CD pipelines + deploy scripts + tests
│   ├── ci/                    # ci-backend, ci-frontend, ci-terraform, security scan
│   ├── cd/                    # cd-backend, cd-frontend, cd-terraform
│   ├── scripts/               # backend-deploy.sh, frontend-deploy.sh, trivy_report.py
│   └── tests/                 # k6 load tests, Playwright UI tests
├── infra/
│   ├── terraform/
│   │   ├── bootstrap/         # Azure DevOps project, pipelines, service connections
│   │   ├── main/              # AKS, networking, PostgreSQL, ACR, observability
│   │   └── edge/              # Cloudflare Tunnel + DNS
│   └── k8s/
│       ├── cloudflared/       # Cloudflared Helm chart
│       ├── externalsecrets/   # ESO ClusterSecretStore + ExternalSecrets
│       ├── cilium/            # NetworkPolicies (kind parity)
│       └── generated/         # Rollouts, services, configmaps (from deploy scripts)
├── scripts/
│   ├── aks/                   # cluster_bootstrap, auth, force-sync-secrets
│   └── local/                 # kind bootstrap + canary simulation
└── services/
    ├── backend/               # Spring Boot (Java 21) + custom metrics
    └── frontend/              # React 19 + Application Insights browser SDK
```

---

## Deployment Guide

### PHASE 0: Local Environment Setup

#### 0.1 — Clone and open in Dev Container

```sh
cd $HOME && rm -rf aks-canary-platform
git clone https://github.com/Athithya-Sakthivel/aks-canary-platform.git
cd aks-canary-platform
code .
```

In VS Code: `Ctrl+Shift+P` → **Dev Containers: Rebuild Container Without Cache**

> First-time build takes **10–20 minutes**.

#### 0.2 — Configure Git and GitHub CLI

```sh
git config --global user.name "Your Name"
git config --global user.email you@example.com
gh auth login
```

Choose:

- Account: **GitHub.com**
- Protocol: **SSH**
- SSH key: **No** (reuse existing)
- Authentication: **Login with a web browser**

#### 0.3 — Create your private repo

```sh
export REPO_NAME="aks-canary-platform"
git remote remove origin 2>/dev/null || true
gh repo create "$REPO_NAME" --private >/dev/null 2>&1
REMOTE_URL="https://github.com/$(gh api user | jq -r .login)/$REPO_NAME.git"
git remote add origin "$REMOTE_URL" 2>/dev/null || true
git branch -M main 2>/dev/null || true
git push -u origin main
git pull
git remote -v
```

#### 0.4 — Log in to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: Azure login success -->

</details>

---

### PHASE 1: Cloud Infrastructure

#### 1.1 — Cloudflare Tunnel + DNS

Creates a Cloudflare Tunnel and a DNS CNAME that routes `app.<domain>` to the AKS cluster without any public IP.

```sh
export CLOUDFLARE_ACCOUNT_ID=      # Cloudflare dashboard → Account Home → "Copy account ID"
export CLOUDFLARE_GLOBAL_API_KEY=  # https://dash.cloudflare.com/profile/api-tokens → Global API Key
export CLOUDFLARE_EMAIL=           # your@email.com
export DOMAIN=                     # example: athithya.site

bash infra/terraform/edge/run.sh --apply
```

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: Cloudflare login, tunnel outputs, DNS record -->

</details>

#### 1.2 — Azure DevOps Organization (Manual)

Automated organization creation is not supported. Create one via the [official guide](https://learn.microsoft.com/azure/devops/organizations/accounts/create-organization).

Microsoft recommends **GitHub as the source of truth** and Azure DevOps for **CI/CD orchestration**. This guide follows that pattern.

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: Azure DevOps organization + PAT creation -->

</details>

#### 1.3 — Bootstrap Azure DevOps + Terraform Backend

One-time bootstrap. Creates:

- Azure DevOps project + 3 pipelines (security scan, Terraform CI, Terraform CD)
- OIDC service connections (`azdo-oidc-ci`, `azdo-oidc-cd`)
- GitHub PAT service connection
- Key Vault (`kv-azdo-bootstrap-<suffix>`) for `azdo-pat`
- Remote state storage account
- Variable group for Terraform

```bash
# One-time PATs
export TF_VAR_AZDO_ORG_SERVICE_URL="https://dev.azure.com/<organization_name>"
export TF_VAR_AZDO_GITHUB_SERVICE_CONNECTION_PAT="<github-pat>"    # https://github.com/settings/tokens/new
export TF_VAR_AZDO_PERSONAL_ACCESS_TOKEN="<azure-devops-pat>"      # Azure DevOps → User Settings → Tokens

# Environment values
export TF_VAR_location=centralindia
export TF_VAR_alert_email_address=your@email.com
export TF_VAR_DOMAIN=athithya.site
export TF_VAR_owner=<your-username>

bash infra/terraform/bootstrap/bootstrap.sh --create
sleep 5
git add . && git commit -m "bootstrap complete" && git push origin main
```

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: bootstrap success, pipeline URLs -->

</details>

#### 1.4 — Apply Main Azure Infrastructure

Trigger the `aks-canary-platform-terraform-cd` pipeline **manually** from Azure DevOps UI.

**Branch:** `main`

This provisions AKS, PostgreSQL, ACR, VNet, Log Analytics, Application Insights, workbooks, and alerts.

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: Terraform CD success, all resources provisioned -->

</details>

---

### PHASE 2: Canary Deployment

#### 2.1 — Trigger Stable Deployment

Modify both services to trigger their CI pipelines:

```sh
echo "--" >> services/backend/src/trigger.txt
echo "--" >> services/frontend/src/trigger.txt
git add services && git commit -m "Trigger stable deployment" && git push origin main
```

CI builds image → pushes to ACR with SHA tag → CD deploys stable Rollout.

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: CI success, stable rollout healthy -->

</details>

#### 2.2 — Trigger Backend Canary

```sh
echo "--" >> services/backend/src/trigger.txt
git add . && git commit -m "Trigger canary deployment" && git push origin main
```

Watch live:

```bash
kubectl argo rollouts get rollout backend -n task-api -w
```

The canary progresses through:

1. **0%** → k6 validation against canary pods
2. **10%** → 2-minute observation
3. **100%** → promoted to stable

If validation fails, the script auto-rolls back to the previous stable image.

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: Argo Rollouts canary progression -->

</details>

#### 2.3 — (Optional) Trigger Frontend Canary

```sh
echo "--" >> services/frontend/src/trigger.txt
git add . && git commit -m "Trigger frontend canary" && git push origin main
```

Watch:

```bash
kubectl argo rollouts get rollout frontend -n task-api -w
```

Frontend canary runs **Playwright** + **k6** validation against the canary service before promotion.

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: frontend canary progression -->

</details>

---

### PHASE 3: Validation

#### 3.1 — Observability Dashboards

Four Azure Monitor Workbooks are deployed automatically by Terraform:

| Workbook            | Focus                                                                            |
| ------------------- | -------------------------------------------------------------------------------- |
| **Application SLO** | Availability, P95 latency, request count, error rate, business metrics, JVM heap |
| **Infrastructure**  | AKS API errors, node CPU/memory/disk, pod restarts                               |
| **Database**        | PostgreSQL connections, CPU, storage                                             |
| **Canary Release**  | Stable vs canary traffic split, error rate, P95 latency, exceptions              |

**Access:**

1. Open [Azure Portal](https://portal.azure.com)
2. Go to resource group **`rg-taskapi-stg`**
3. Select a workbook, e.g. **Task API Canary Release**
4. Click **Open Workbook**

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: workbook dashboards -->

</details>

#### 3.2 — End-to-End User Flow

Open `https://app.<your-domain>` in a browser:

1. Click **Register** → create a new user
2. Log in
3. Create a task
4. Refresh the page — the task should persist

<details>
<summary>▶ Expected output</summary>

<!-- Insert screenshot: working app -->

</details>

---

## Observability

The platform emits telemetry from **three layers** into a single Application Insights resource (workspace-based):

```
Browser (JS SDK)     Backend (Java agent)     Kubernetes (diagnostic logs)
      │                     │                          │
      ▼                     ▼                          ▼
┌─────────────────────────────────────────────────────────┐
│        Application Insights + Log Analytics             │
│  AppRequests · AppDependencies · AppExceptions          │
│  AppTraces · AppMetrics · AKSControlPlane               │
│  AzureMetrics · KubePodInventory · PGSQLServerLogs      │
└─────────────────────────────────────────────────────────┘
      │                                    │
      ▼                                    ▼
  Workbooks                          Burn-Rate Alerts
  (4 dashboards)                     (99.9% SLO)
```

### Key Signals

| Signal                     | Source               | Used by                 |
| -------------------------- | -------------------- | ----------------------- |
| Request volume & latency   | Browser + backend    | Application SLO         |
| Error rate                 | Both                 | Application SLO, Canary |
| Custom business metrics    | `MetricsConfig.java` | Application SLO         |
| Dependency calls           | JDBC + fetch         | Canary                  |
| Exceptions                 | Both                 | Canary                  |
| Node CPU/memory/disk       | AzureMetrics         | Infrastructure          |
| Pod restarts               | KubePodInventory     | Infrastructure          |
| DB connections/CPU/storage | AzureMetrics         | Database                |
| API server errors          | AKSControlPlane      | Infrastructure          |

### SLO and Burn-Rate Alerts

| Parameter        | Value                                |
| ---------------- | ------------------------------------ |
| Availability SLO | 99.9%                                |
| Error budget     | 0.1%                                 |
| Fast burn alert  | 20× (2.0% error over 5 min)          |
| Slow burn alert  | 5× (0.5% error over 1 hour)          |
| Alert target     | Email via Azure Monitor Action Group |

All alerts fire on **burn rate**, not raw thresholds, minimizing false positives while catching real SLO erosion.

---

## Local Development with Kind

You can simulate the entire platform locally (without Azure) using a **kind** cluster. The local setup mirrors the AKS configuration: Cilium + Gateway API + Argo Rollouts + ESO.

```bash
# 1. Bootstrap kind cluster with Cilium, Gateway API, Argo Rollouts, ESO
bash scripts/local/cluster_bootstrap.sh

# 2. Install Helm charts (ESO config, cloudflared, cilium)
bash scripts/local/setup_charts.sh

# 3. Deploy apps + PostgreSQL
bash scripts/local/setup_apps.sh
bash scripts/local/deploy-postgres.sh

# 4. Deploy stable rollouts
bash azure-pipelines/scripts/backend-deploy.sh --stable --stable-tag v1
bash azure-pipelines/scripts/frontend-deploy.sh --stable --stable-tag v1

# 5. Simulate full canary lifecycle with auto-rollback
bash scripts/local/simulate_canary_lifecycle.sh
```

Local canary uses tuned thresholds for single-node kind (QPS=2, P95=20s) to avoid resource contention.

---

## Cleanup

Destroy all infrastructure in reverse order:

```bash
# 1. Cloudflare edge
bash infra/terraform/edge/run.sh --destroy

# 2. Main Azure infrastructure
export TF_BACKEND_AUTH_MODE=cli
bash infra/terraform/main/run.sh --destroy --env staging --yes-delete

# 3. Bootstrap resources + Azure DevOps
bash infra/terraform/bootstrap/bootstrap.sh --delete --force
```

Then manually delete the Azure DevOps organization if no longer needed.

---

## Security Notes

- **No long-lived credentials**: OIDC for Azure DevOps, Workload Identity for ESO → Key Vault.
- **Private AKS**: No public IPs; API server restricted to `AzureCloud` service tag + engineer IPs.
- **Private PostgreSQL**: Only reachable via Private Endpoint.
- **Non-root containers**: All pods run as non-root with read-only root filesystems where supported.
- **Immutable image tags**: Deployments reference commit SHAs, never mutable tags.
- **Network policies**: Cilium NetworkPolicies enforce default-deny within the cluster.

---

## Troubleshooting

| Symptom                           | Likely cause                          | Fix                                                       |
| --------------------------------- | ------------------------------------- | --------------------------------------------------------- |
| `kubectl` timeout to AKS API      | Your IP not in authorized ranges      | Add via `az aks update --api-server-authorized-ip-ranges` |
| Backend `CrashLoopBackOff`        | Wrong DB credentials in Key Vault     | Verify `DatabaseUsername` = `taskuser`                    |
| Canary stuck at `Paused`          | Pause step hit, waiting for promotion | `kubectl argo rollouts promote <rollout> -n task-api`     |
| `UNVERSIONED` in canary dashboard | `AppVersion` not set on pods          | Verify `OTEL_RESOURCE_ATTRIBUTES` env in rollout          |
| `ImagePullBackOff`                | ACR auth missing                      | Verify kubelet identity has `AcrPull` on ACR              |

---
