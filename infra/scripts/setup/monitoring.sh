#!/bin/bash

# =============================================================================
# Monitoring Stack Setup (Prometheus + Grafana)
# =============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Starting monitoring stack setup..."

# Source environment variables
source /etc/profile.d/workshop.sh

PREFIX="${PREFIX:-workshop}"
NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
GRAFANA_USER="admin"

# Get password from Secrets Manager
SECRET_NAME="${PREFIX}-ide-password"
SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query 'SecretString' \
    --output text)

GRAFANA_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')

if [[ -z "$GRAFANA_PASSWORD" || "$GRAFANA_PASSWORD" == "null" ]]; then
    log "❌ Failed to retrieve password from $SECRET_NAME"
    exit 1
fi

VALUES_FILE="prometheus-values.yaml"
DATASOURCE_FILE="grafana-datasource.yaml"
GRAFANA_VALUES_FILE="grafana-values.yaml"

cleanup() {
  rm -f "$VALUES_FILE" "$DATASOURCE_FILE" "$GRAFANA_VALUES_FILE"
}
trap cleanup EXIT

# Setup
kubectl create namespace "$NAMESPACE" 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts || true
helm repo update

# Grafana secret
kubectl delete secret "$GRAFANA_SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true
kubectl create secret generic "$GRAFANA_SECRET_NAME" \
  --from-literal=username="$GRAFANA_USER" \
  --from-literal=password="$GRAFANA_PASSWORD" \
  -n "$NAMESPACE"

# Prometheus values - ClusterIP only (no external access needed)
cat > "$VALUES_FILE" <<EOF
alertmanager:
  enabled: false
server:
  service:
    type: ClusterIP
  retention: 24h
  global:
    scrape_interval: 15s
  resources:
    requests:
      cpu: 200m
      memory: 1Gi
    limits:
      cpu: 500m
      memory: 2Gi
EOF

log_info "Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

# Wait for Prometheus to be ready
log_info "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/prometheus-server -n "$NAMESPACE"

# Verify Prometheus is responding
kubectl port-forward -n "$NAMESPACE" svc/prometheus-server 9090:80 &
PF_PID=$!
# Ensure port-forward is killed on exit
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 5
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    log_success "Prometheus is healthy"
else
    log_error "Prometheus health check failed"
    kubectl logs -n "$NAMESPACE" deployment/prometheus-server -c prometheus-server --tail=10
    exit 1
fi
kill $PF_PID 2>/dev/null || true
trap - EXIT

# Grafana values
cat > "$GRAFANA_VALUES_FILE" <<EOF
# Pin Grafana to 12.x (React 18). Grafana 13 moved to React 19, which breaks
# the grafana-pyroscope-app 1.x plugin (it reads a React 18 internal removed
# in React 19). We must stay on the 1.x plugin because the 2.x line calls
# crypto.randomUUID(), unavailable over plain HTTP (the workshop serves
# Grafana over HTTP, not a browser secure context). Grafana 12.x + plugin
# 1.17.0 is the combination that loads over HTTP.
image:
  tag: "12.3.1"

admin:
  existingSecret: grafana-admin
  userKey: username
  passwordKey: password

service:
  enabled: true
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing

persistence:
  enabled: true
  storageClassName: gp3
  size: 10Gi

# The PVC above is ReadWriteOnce (EBS). RollingUpdate (the chart default)
# starts the new pod before the old one is deleted, so the new pod cannot
# attach the volume still held by the old pod and the upgrade deadlocks.
# Recreate terminates the old pod first, releasing the volume.
deploymentStrategy:
  type: Recreate

resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi

sidecar:
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    limits:
      cpu: 200m
      memory: 512Mi
  dashboards:
    enabled: true
    label: grafana_dashboard
    searchNamespace: ALL
    env:
      HEALTH_PORT: "8081"
  datasources:
    enabled: true
    label: grafana_datasource
    searchNamespace: ALL
    env:
      HEALTH_PORT: "8082"

grafana.ini:
  unified_alerting:
    min_interval: 20s
    evaluation_timeout: 10s
EOF

log_info "Deploying Grafana..."
helm upgrade --install grafana grafana-community/grafana \
  --namespace "$NAMESPACE" \
  --values "$GRAFANA_VALUES_FILE"

# Wait for Grafana LB
for i in {1..30}; do
  GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
  if [[ -n "$GRAFANA_LB" && "$GRAFANA_LB" != "<no value>" ]]; then
    if dig +short "$GRAFANA_LB" | grep -qE "^[0-9.]+$"; then
      break
    fi
  fi
  log_info "Waiting for Grafana LB... ($i/30)"
  sleep 10
done

# Prometheus datasource
cat > "$DATASOURCE_FILE" <<EOF
apiVersion: 1
datasources:
  - uid: promds
    name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-server.monitoring.svc.cluster.local
    isDefault: true
    editable: true
EOF

kubectl create configmap prometheus-datasource --from-file="$DATASOURCE_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap prometheus-datasource -n "$NAMESPACE" grafana_datasource=1 --overwrite

# Wait for Grafana health. A freshly provisioned LoadBalancer can take several
# minutes to start accepting traffic, so poll up to ~5 min with per-request
# timeouts (so a not-yet-ready endpoint fails fast instead of hanging), and gate:
# abort clearly if Grafana never comes up rather than pressing on into a hang.
GRAFANA_URL="http://$GRAFANA_LB"
STATUS=""
for i in {1..60}; do
  STATUS=$(curl -s --connect-timeout 5 --max-time 10 -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" | jq -r .database 2>/dev/null || true)
  if [[ "$STATUS" == "ok" ]]; then
    break
  fi
  log_info "Waiting for Grafana... ($i/60)"
  sleep 5
done
if [[ "$STATUS" != "ok" ]]; then
  log_error "Grafana API not reachable at $GRAFANA_URL after ~5 minutes"
  exit 1
fi

# Shared "Workshop Dashboards" Grafana folder. All analysis modules
# (analysis.sh, perf-platform.sh) drop their dashboards and alert rules
# here. Created once, here, so each downstream script can simply look
# up the UID by title — no SSM, no env file. Retried with per-request timeouts
# so a transient LB/API hiccup doesn't abort the bootstrap.
log_info "Creating shared Grafana folder 'Workshop Dashboards'..."
FOLDER_UID=""
for i in {1..12}; do
  FOLDER_RESPONSE=$(curl -s --connect-timeout 5 --max-time 15 -X POST -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d '{"title": "Workshop Dashboards"}' \
    "$GRAFANA_URL/api/folders" || true)
  FOLDER_UID=$(echo "$FOLDER_RESPONSE" | jq -r '.uid // empty' 2>/dev/null)
  if [[ -z "$FOLDER_UID" ]]; then
    # Already exists (409) or transient — look it up by title.
    FOLDER_UID=$(curl -s --connect-timeout 5 --max-time 15 -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/folders" 2>/dev/null \
      | jq -r '.[] | select(.title == "Workshop Dashboards") | .uid' 2>/dev/null || true)
  fi
  [[ -n "$FOLDER_UID" ]] && break
  log_info "Grafana folder not ready, retrying... ($i/12)"
  sleep 5
done
if [[ -z "$FOLDER_UID" ]]; then
  log_error "Failed to create or look up 'Workshop Dashboards' folder"
  exit 1
fi
log_success "Workshop Dashboards folder ready: $FOLDER_UID"

log_success "Monitoring stack deployed"
log_info "Grafana: http://$GRAFANA_LB"
log_info "Username: $GRAFANA_USER"
log_info "Password: $GRAFANA_PASSWORD"
log_info "Prometheus: http://prometheus-server.monitoring.svc.cluster.local (internal)"

# Emit for bootstrap summary
echo "✅ Success: Monitoring (Prometheus + Grafana)"
