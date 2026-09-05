#!/usr/bin/env bash
# ==============================================================================
# local/deploy-postgres.sh – Deploy local PostgreSQL for kind and ensure
# backend-secrets are set to local database values with REAL Azure App Insights.
#
# This script:
#   1. Deletes any existing ExternalSecret `backend-secrets` to prevent ESO
#      from overwriting our local secret.
#   2. Fetches the real Application Insights connection string from Azure Key Vault.
#   3. Creates/patches the Kubernetes Secret `backend-secrets` with:
#      - Local DatabaseUrl (points to in-cluster PostgreSQL)
#      - Local database credentials
#      - Random JWT secret
#      - REAL Application Insights connection string (for observability)
#   4. Deploys a local PostgreSQL Deployment + Service + PVC using the same
#      credentials.
#
# Idempotent – safe to run multiple times.
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

NAMESPACE="${NAMESPACE:-task-api}"
POSTGRES_USER="${POSTGRES_USER:-taskuser}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-local-dev-password}"
POSTGRES_DB="${POSTGRES_DB:-taskdb}"
STORAGE_SIZE="${STORAGE_SIZE:-1Gi}"

log()   { printf '[%s] %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }
fail()  { log "ERROR: $*" >&2; exit 1; }

# ------------------------------------------------------------------------------
# 0. Fetch real Application Insights connection string from Azure Key Vault
# ------------------------------------------------------------------------------
fetch_app_insights_connection_string() {
  local subscription_id suffix kv_name conn_str

  # Try Azure CLI if available
  if command -v az >/dev/null 2>&1; then
    subscription_id="$(az account show --query id -o tsv 2>/dev/null || true)"
    
    if [[ -n "$subscription_id" ]]; then
      suffix="${subscription_id: -6}"
      kv_name="kv-azdo-bootstrap-${suffix}"
      
      log "Fetching Application Insights connection string from Key Vault: $kv_name"
      
      conn_str="$(az keyvault secret show \
        --vault-name "$kv_name" \
        --name "ApplicationInsightsConnectionString" \
        --query value \
        -o tsv 2>/dev/null || true)"
      
      if [[ -n "$conn_str" && "$conn_str" != "null" ]]; then
        log "Successfully fetched real Application Insights connection string"
        echo "$conn_str"
        return 0
      fi
    fi
  fi
  
  # Fallback: use dummy connection string (telemetry will be lost)
  log "WARNING: Could not fetch real Application Insights connection string"
  log "WARNING: Using dummy connection string (no telemetry will be exported)"
  echo "InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://localhost;LiveEndpoint=https://localhost"
}

# ------------------------------------------------------------------------------
# 1. Ensure namespace exists
# ------------------------------------------------------------------------------
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ------------------------------------------------------------------------------
# 2. Remove any existing ExternalSecret that would overwrite our local secret
# ------------------------------------------------------------------------------
log "Removing external secret (if any) to prevent Azure sync..."
kubectl delete externalsecret backend-secrets -n "$NAMESPACE" --ignore-not-found=true

# Wait for ExternalSecret cleanup to complete (prevents race condition)
kubectl wait --for=delete externalsecret/backend-secrets -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Create/update the backend-secrets Secret with local database + real AI
# ------------------------------------------------------------------------------
# Generate a random JWT secret if not provided
JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 64)}"

# Fetch real Application Insights connection string
APPINSIGHTS_CS="$(fetch_app_insights_connection_string)"

log "Creating backend-secrets with local database + real Application Insights..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: backend-secrets
  namespace: $NAMESPACE
  labels:
    app: backend
    managed-by: deploy-postgres-script
type: Opaque
stringData:
  DATABASEURL: "jdbc:postgresql://postgres:5432/$POSTGRES_DB"
  DATABASEUSERNAME: "$POSTGRES_USER"
  DATABASEPASSWORD: "$POSTGRES_PASSWORD"
  JWTSECRET: "$JWT_SECRET"
  APPLICATIONINSIGHTS_CONNECTION_STRING: "$APPINSIGHTS_CS"
EOF


# After creating backend-secrets
APPINSIGHTS_CS="$(az keyvault secret show \
  --vault-name "kv-azdo-bootstrap-${SUFFIX}" \
  --name "ApplicationInsightsConnectionString" \
  --query value -o tsv)"

kubectl create secret generic frontend-secrets \
  --namespace task-api \
  --from-literal=APPLICATIONINSIGHTS_CONNECTION_STRING="$APPINSIGHTS_CS" \
  --dry-run=client -o yaml | kubectl apply -f -
  
# ------------------------------------------------------------------------------
# 4. Deploy local PostgreSQL
# ------------------------------------------------------------------------------
log "Deploying local PostgreSQL..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $STORAGE_SIZE
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: $NAMESPACE
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
      protocol: TCP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:18.6-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: "$POSTGRES_DB"
            - name: POSTGRES_USER
              value: "$POSTGRES_USER"
            - name: POSTGRES_PASSWORD
              value: "$POSTGRES_PASSWORD"
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
          readinessProbe:
            exec:
              command: ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:
            exec:
              command: ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            initialDelaySeconds: 15
            periodSeconds: 15
            failureThreshold: 3
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: postgres-pvc
EOF

log "Waiting for PostgreSQL to be ready..."
kubectl rollout status deployment/postgres -n "$NAMESPACE" --timeout=180s

log "Local PostgreSQL deployed successfully."
log "Backend-secrets now contain:"
log "  - Local DatabaseUrl: jdbc:postgresql://postgres:5432/$POSTGRES_DB"
log "  - Real Application Insights connection string: ${APPINSIGHTS_CS:0:50}..."
log ""
log "Verify with:"
log "  kubectl get secret backend-secrets -n $NAMESPACE -o jsonpath='{.data.APPLICATIONINSIGHTS_CONNECTION_STRING}' | base64 -d"