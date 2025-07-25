#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

# --- Configuration ---
NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
GRAFANA_USER="admin"

# Generate random password for Grafana admin (can be overridden by external scripts)
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-$(openssl rand -base64 16 | tr -d '\n')}"
log "🔑 Using Grafana password: ${GRAFANA_PASSWORD:0:4}****"

VALUES_FILE="prometheus-values.yaml"
EXTRA_SCRAPE_FILE="extra-scrape-configs.yaml"
DATASOURCE_FILE="grafana-datasource.yaml"
GRAFANA_VALUES_FILE="grafana-values.yaml"

cleanup() {
  log "🧹 Cleaning up temporary files..."
  rm -f "$VALUES_FILE" "$EXTRA_SCRAPE_FILE" "$DATASOURCE_FILE" "$GRAFANA_VALUES_FILE"
}
trap cleanup EXIT

# --- Namespace & Helm setup ---
kubectl create namespace "$NAMESPACE" 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

# --- Grafana secret ---
kubectl delete secret "$GRAFANA_SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true
kubectl create secret generic "$GRAFANA_SECRET_NAME" \
  --from-literal=username="$GRAFANA_USER" \
  --from-literal=password="$GRAFANA_PASSWORD" \
  -n "$NAMESPACE"

# --- Prometheus extra scrape configs (empty by default) ---
cat > "$EXTRA_SCRAPE_FILE" <<EOF
# Add custom scrape configs here
# Example:
# - job_name: "my-app"
#   static_configs:
#     - targets: ["my-app.default.svc.cluster.local:8080"]
EOF

kubectl create configmap prometheus-extra-scrape --from-file="$EXTRA_SCRAPE_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# --- Prometheus values ---
cat > "$VALUES_FILE" <<EOF
alertmanager:
  enabled: false
server:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal
  retention: 24h
  extraFlags:
    - web.enable-remote-write-receiver
  extraScrapeConfigs: |
    # Additional scrape configs will be loaded from ConfigMap
EOF

log "🚀 Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

# --- Grafana Helm values ---
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

grafana.ini:
  server:
    http_port: 3000
  log:
    level: info
  unified_alerting:
    enabled: true
  alerting:
    enabled: false

provisioning:
  enabled: true
  alerting:
    enabled: true
    path: /etc/grafana/provisioning/policies
  dashboards:
    enabled: true
    path: /etc/grafana/provisioning/dashboards
  datasources:
    enabled: true
    path: /etc/grafana/provisioning/datasources
  policy:
    enabled: true

sidecar:
  image:
    repository: kiwigrid/k8s-sidecar
    tag: 1.23.1
  dashboards:
    enabled: true
    label: grafana_dashboard
    folder: /etc/grafana/provisioning/dashboards
    searchNamespace: ALL
  datasources:
    enabled: true
    label: grafana_datasource
    folder: /etc/grafana/provisioning/datasources
    searchNamespace: ALL
  notifiers:
    enabled: true
    label: grafana_notifier
    folder: /etc/grafana/provisioning/notifiers
    searchNamespace: ALL
  policies:
    enabled: true
    label: grafana_policy
    folder: /etc/grafana/provisioning/policies
    searchNamespace: ALL
EOF

log "🚀 Deploying Grafana..."
helm upgrade --install grafana grafana/grafana \
  --namespace "$NAMESPACE" \
  --values "$GRAFANA_VALUES_FILE"

# --- Wait for Grafana LB ---
for i in {1..30}; do
  GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
  if [[ -n "$GRAFANA_LB" && "$GRAFANA_LB" != "<no value>" ]]; then
    if dig +short "$GRAFANA_LB" | grep -qE "^[0-9.]+$"; then
      log "✅ Grafana LB: http://$GRAFANA_LB"
      break
    fi
  fi
  log "⏳ Waiting for Grafana LB DNS... ($i/30)"
  sleep 10
done

# --- Datasource ConfigMap ---
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

GRAFANA_URL="http://$GRAFANA_LB"

log "⏳ Waiting for Grafana to become healthy..."
for i in {1..20}; do
  STATUS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" | jq -r .database 2>/dev/null || true)
  if [[ "$STATUS" == "ok" ]]; then
    log "✅ Grafana is healthy"
    break
  fi
  log "⏳ ($i/20) Grafana not ready yet..."
  sleep 5
done

# --- Get Prometheus LoadBalancer Hostname ---
PROM_LB_HOSTNAME=$(kubectl get svc prometheus-server -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)

if [[ -z "$PROM_LB_HOSTNAME" ]]; then
  log "❌ Prometheus Load Balancer Hostname not found"
  exit 1
fi

log "✅ Prometheus Internal URL: http://$PROM_LB_HOSTNAME:9090"

# --- Allow VPC access to Prometheus LoadBalancer on port 9090 ---
log "🔐 Configuring Prometheus ILB Security Group..."

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" --query "Vpcs[0].VpcId" --output text 2>/dev/null || true)
if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
  VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlock" --output text 2>/dev/null || true)

  LB_ARN=$(aws elbv2 describe-load-balancers \
    --output json 2>/dev/null | jq -r \
    --arg dns "$PROM_LB_HOSTNAME" '
      .LoadBalancers[] | select(.DNSName == $dns) | .LoadBalancerArn' \
  )

  if [[ -n "$LB_ARN" ]]; then
    ILB_SG_ID=$(aws elbv2 describe-load-balancers \
      --load-balancer-arns "$LB_ARN" \
      --query "LoadBalancers[0].SecurityGroups[0]" \
      --output text 2>/dev/null || true)

    if [[ -n "$ILB_SG_ID" && "$ILB_SG_ID" != "None" ]]; then
      log "🔐 ILB Security Group: $ILB_SG_ID"
      aws ec2 authorize-security-group-ingress \
        --group-id "$ILB_SG_ID" \
        --protocol tcp \
        --port 9090 \
        --cidr "$VPC_CIDR" \
        --output text 2>/dev/null || log "ℹ️ Security group rule may already exist"
    fi
  fi
else
  log "ℹ️ VPC not found or not accessible, skipping security group configuration"
fi

# --- Final output ---
echo -e "\n✅ Generic Monitoring Stack Setup Complete!"
echo "🌍 Grafana URL: http://$GRAFANA_LB"
echo "👤 Username: $GRAFANA_USER"
echo "🔑 Password: $GRAFANA_PASSWORD"
echo "📊 Prometheus URL: http://$PROM_LB_HOSTNAME:9090 (VPC internal)"

log "✅ Monitoring stack is ready for use"
log "ℹ️ Add custom dashboards and alerts as ConfigMaps with appropriate labels"
log "ℹ️ grafana_dashboard=1 for dashboards"
log "ℹ️ grafana_datasource=1 for datasources"
