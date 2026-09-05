#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# One-time AKS cluster bootstrap — idempotent, safe to rerun
#
# Uses local-proven Argo Rollouts versions (v1.9.1 / chart 2.41.1)
# with the Gateway API plugin init container.
#
# Gateway API controller: Envoy Gateway v1.9.1
# GatewayClass name: eg
#
# Components:
#   - Gateway API CRDs
#   - Envoy Gateway
#   - GatewayClass `eg`
#   - Gateway `gateway` in namespace `gateway`
#   - Argo Rollouts (Helm) + Gateway API plugin
#   - External Secrets Operator
#   - Cloudflared
# ==============================================================================

TF_DIR="${TF_DIR:-infra/terraform/main}"

NAMESPACE="${NAMESPACE:-task-api}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.6.1}"
ENVOY_GATEWAY_VERSION="${ENVOY_GATEWAY_VERSION:-v1.9.1}"
ARGO_ROLLOUTS_VERSION="${ARGO_ROLLOUTS_VERSION:-v1.9.1}"
ARGO_ROLLOUTS_CHART_VERSION="${ARGO_ROLLOUTS_CHART_VERSION:-2.41.1}"
GATEWAY_API_PLUGIN_VERSION="${GATEWAY_API_PLUGIN_VERSION:-v0.16.0}"
ESO_VERSION="2.8.0"

log()   { printf '==> %s\n' "$*"; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for cmd in kubectl helm tofu az curl; do
  command -v "$cmd" >/dev/null || die "$cmd not found"
done

# ------------------------------------------------------------------------------
# 0. Resolve Terraform outputs
# ------------------------------------------------------------------------------
log "Resolving Terraform outputs..."

cd "$TF_DIR"

ESO_CLIENT_ID="$(tofu output -raw eso_identity_client_id)"
ESO_PRINCIPAL_ID="$(tofu output -raw eso_identity_principal_id)"
AKS_CLUSTER_NAME="$(tofu output -raw aks_cluster_name)"
RESOURCE_GROUP_NAME="$(tofu output -raw resource_group_name)"
KEY_VAULT_NAME="$(tofu output -raw bootstrap_key_vault_name 2>/dev/null || true)"

cd - >/dev/null

[[ -n "$ESO_CLIENT_ID" ]] || die "Missing eso_identity_client_id"
[[ -n "$ESO_PRINCIPAL_ID" ]] || die "Missing eso_identity_principal_id"
[[ -n "$AKS_CLUSTER_NAME" ]] || die "Missing aks_cluster_name"
[[ -n "$RESOURCE_GROUP_NAME" ]] || die "Missing resource_group_name"

TENANT_ID="$(az account show --query tenantId -o tsv)"
AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

log "ESO_CLIENT_ID=$ESO_CLIENT_ID"
log "TENANT_ID=$TENANT_ID"

# ------------------------------------------------------------------------------
# 1. Ensure AKS credentials
# ------------------------------------------------------------------------------
if ! kubectl get nodes >/dev/null 2>&1; then
  log "Getting AKS credentials..."

  CURRENT_IP="$(curl -s https://ifconfig.me || true)"

  if [[ -n "$CURRENT_IP" ]]; then
    log "Adding current public IP ${CURRENT_IP}/32 to AKS authorized IP ranges..."
    az aks update \
      --resource-group "$RESOURCE_GROUP_NAME" \
      --name "$AKS_CLUSTER_NAME" \
      --api-server-authorized-ip-ranges "AzureCloud,${CURRENT_IP}/32" \
      --output none
    sleep 60
  fi

  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$AKS_CLUSTER_NAME" \
    --overwrite-existing
fi

if ! kubectl get nodes >/dev/null 2>&1; then
  die "Cannot connect to AKS cluster"
fi

# ------------------------------------------------------------------------------
# 2. Gateway API CRDs
# ------------------------------------------------------------------------------
if ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  log "Installing Gateway API ${GATEWAY_API_VERSION}..."
  kubectl apply --server-side -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
  kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=120s
else
  log "Gateway API CRDs already present"
fi

# ------------------------------------------------------------------------------
# 3. Envoy Gateway
# ------------------------------------------------------------------------------
if ! kubectl get deployment envoy-gateway -n envoy-gateway-system >/dev/null 2>&1; then
  log "Installing Envoy Gateway ${ENVOY_GATEWAY_VERSION}..."
  helm upgrade --install eg \
    oci://docker.io/envoyproxy/gateway-helm \
    --version "${ENVOY_GATEWAY_VERSION}" \
    --namespace envoy-gateway-system \
    --create-namespace \
    --set crds.enabled=false
else
  log "Envoy Gateway already installed"
fi

kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available || true

# ------------------------------------------------------------------------------
# 4. GatewayClass `eg`
# ------------------------------------------------------------------------------
if ! kubectl get gatewayclass eg >/dev/null 2>&1; then
  log "Creating GatewayClass eg..."
  kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
else
  log "GatewayClass eg already exists"
fi

log "Waiting for GatewayClass acceptance..."
kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s || true

# ------------------------------------------------------------------------------
# 5. Namespaces
# ------------------------------------------------------------------------------
log "Creating namespaces..."
for ns in "$NAMESPACE" argo-rollouts external-secrets cloudflared gateway; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# ------------------------------------------------------------------------------
# 6. Gateway `gateway` in namespace `gateway`
# ------------------------------------------------------------------------------
if ! kubectl get gateway gateway -n gateway >/dev/null 2>&1; then
  log "Creating Gateway 'gateway'..."
  kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway
  namespace: gateway
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
EOF
else
  log "Gateway 'gateway' already exists"
fi

# ------------------------------------------------------------------------------
# 7. Argo Rollouts with Gateway API plugin — LOCAL-PROVEN VERSIONS
# ------------------------------------------------------------------------------
log "Installing Argo Rollouts ${ARGO_ROLLOUTS_VERSION}..."

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update

cat > /tmp/argo-values.yaml <<YAML
controller:
  image:
    registry: quay.io
    repository: argoproj/argo-rollouts
    tag: ${ARGO_ROLLOUTS_VERSION}
  initContainers:
    - name: copy-gateway-api-plugin
      image: ghcr.io/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi:${GATEWAY_API_PLUGIN_VERSION}
      imagePullPolicy: IfNotPresent
      command: ["/bin/sh", "-c"]
      args:
        - cp /bin/rollouts-plugin-trafficrouter-gatewayapi /plugins/rollouts-plugin-trafficrouter-gatewayapi
      volumeMounts:
        - name: gateway-api-plugin
          mountPath: /plugins
  trafficRouterPlugins:
    - name: argoproj-labs/gatewayAPI
      location: file:///plugins/rollouts-plugin-trafficrouter-gatewayapi
  volumes:
    - name: gateway-api-plugin
      emptyDir: {}
  volumeMounts:
    - name: gateway-api-plugin
      mountPath: /plugins
providerRBAC:
  enabled: true
  providers:
    gatewayAPI: true
YAML

helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --version "${ARGO_ROLLOUTS_CHART_VERSION}" \
  --values /tmp/argo-values.yaml \
  --wait --timeout 300s

kubectl rollout status deployment/argo-rollouts -n argo-rollouts --timeout=300s

# ------------------------------------------------------------------------------
# 8. External Secrets Operator
# ------------------------------------------------------------------------------
log "Installing External Secrets Operator..."

helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --version "${ESO_VERSION}" \
  --set image.tag="v${ESO_VERSION}" \
  --wait

# ------------------------------------------------------------------------------
# 9. ESO configuration with Workload Identity
# ------------------------------------------------------------------------------
log "Deploying ESO configuration..."

cat > /tmp/eso-values.yaml <<EOF
keyVault:
  url: "https://${KEY_VAULT_NAME}.vault.azure.net"
  tenantId: "${TENANT_ID}"

auth:
  mode: WorkloadIdentity

  workloadIdentity:
    serviceAccountName: eso-azure-kv
    serviceAccountNamespace: external-secrets
    createServiceAccount: true

    annotations:
      azure.workload.identity/client-id: "${ESO_CLIENT_ID}"
      azure.workload.identity/tenant-id: "${TENANT_ID}"
EOF

helm upgrade --install eso-config infra/k8s/externalsecrets \
  --namespace external-secrets \
  --values /tmp/eso-values.yaml \
  --wait

# ------------------------------------------------------------------------------
# 10. Cloudflared
# ------------------------------------------------------------------------------
log "Installing cloudflared..."

helm upgrade --install cloudflared infra/k8s/cloudflared \
  --namespace cloudflared \
  --create-namespace

log "Cluster bootstrap complete."
log ""
log "Next steps:"
log "  - Deploy stable applications:"
log "      bash azure-pipelines/scripts/backend-deploy.sh --stable --stable-tag <v1-tag>"
log "      bash azure-pipelines/scripts/frontend-deploy.sh --stable --stable-tag <v1-tag>"
log "  - Simulate canary:"
log "      bash azure-pipelines/scripts/backend-deploy.sh --canary --image <image> ..."
