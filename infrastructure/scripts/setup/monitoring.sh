#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
GRAFANA_USER="admin"

# Get password from Secrets Manager
SECRET_NAME="unicornstore-ide-password-lambda"
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
helm repo add grafana https://grafana.github.io/helm-charts || true
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
EOF

log "🚀 Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

# Wait for Prometheus to be ready
log "⏳ Waiting for Prometheus to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/prometheus-server -n "$NAMESPACE"

# Verify Prometheus is responding
kubectl port-forward -n "$NAMESPACE" svc/prometheus-server 9090:80 &
PF_PID=$!
sleep 5
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    log "✅ Prometheus is healthy"
else
    log "❌ Prometheus health check failed"
    kubectl logs -n "$NAMESPACE" deployment/prometheus-server -c prometheus-server --tail=10
    kill $PF_PID 2>/dev/null
    exit 1
fi
kill $PF_PID 2>/dev/null

# Grafana values
cat > "$GRAFANA_VALUES_FILE" <<EOF
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

sidecar:
  dashboards:
    enabled: true
    label: grafana_dashboard
    searchNamespace: ALL
  datasources:
    enabled: true
    label: grafana_datasource
    searchNamespace: ALL
EOF

log "🚀 Deploying Grafana..."
helm upgrade --install grafana grafana/grafana \
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
  log "⏳ Waiting for Grafana LB... ($i/30)"
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

# Wait for Grafana health
GRAFANA_URL="http://$GRAFANA_LB"
for i in {1..20}; do
  STATUS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" | jq -r .database 2>/dev/null || true)
  if [[ "$STATUS" == "ok" ]]; then
    break
  fi
  log "⏳ Waiting for Grafana... ($i/20)"
  sleep 5
done

log "✅ Monitoring stack deployed"
log "🌍 Grafana: http://$GRAFANA_LB"
log "👤 Username: $GRAFANA_USER"
log "🔑 Password: $GRAFANA_PASSWORD"
log "📊 Prometheus: http://prometheus-server.monitoring.svc.cluster.local (internal)"
