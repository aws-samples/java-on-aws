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
helm repo add grafana https://grafana.github.io/helm-charts || true   # pyroscope chart
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
    # Let a ConfigMap choose its Grafana folder via the grafana_folder annotation
    # (perf-optimizer.sh ships the Optimization dashboard into "Workshop Dashboards").
    # foldersFromFilesStructure makes the sidecar create/route by that folder name.
    folderAnnotation: grafana_folder
    provider:
      foldersFromFilesStructure: true
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

# =============================================================================
# Pyroscope (S3-backed) + Grafana profiling/CloudWatch wiring
# Shared by both workshops (java-on-aws and java-on-amazon-eks). Runs here, in
# monitoring.sh, so the profiling backend and Grafana datasources come up with
# the monitoring stack. Grafana is already up (checked above) before we install
# the plugin / provision datasources. No dashboards are created here — only the
# shared folder above; module scripts (analysis.sh, perf-platform.sh) and the
# perf-optimizer deploy add their own dashboards.
# =============================================================================

CLUSTER_NAME="${PREFIX}-eks"
WORKSHOP_BUCKET=$(aws ssm get-parameter --name workshop-bucket-name \
    --query 'Parameter.Value' --output text --no-cli-pager)
if [[ -z "${WORKSHOP_BUCKET}" || "${WORKSHOP_BUCKET}" == "None" ]]; then
    log_error "SSM parameter workshop-bucket-name is not set. Aborting."
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$VALUES_FILE" "$DATASOURCE_FILE" "$GRAFANA_VALUES_FILE"' EXIT

# -----------------------------------------------------------------------------
# Pyroscope Pod Identity — bind the Pyroscope ServiceAccount to the CDK-managed
# pyroscope-eks-pod-role BEFORE installing Pyroscope, so the very first pod boot
# has S3 creds. Pyroscope writes blocks to S3 from boot, so it cannot follow the
# Grafana pattern (install first, attach identity, restart) — it would fail
# health checks before the restart.
# -----------------------------------------------------------------------------
log_info "Binding Pyroscope ServiceAccount to pyroscope-eks-pod-role..."
# Pre-create the SA with Helm 3 adoption metadata so `helm install pyroscope`
# adopts it instead of erroring on missing app.kubernetes.io/managed-by.
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pyroscope
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: pyroscope
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: pyroscope
    meta.helm.sh/release-namespace: ${NAMESPACE}
EOF

if ! aws eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" \
        --query "associations[?serviceAccount=='pyroscope' && namespace=='${NAMESPACE}']" \
        --output text --no-cli-pager | grep -q .; then
    aws eks create-pod-identity-association \
        --cluster-name "${CLUSTER_NAME}" \
        --namespace "${NAMESPACE}" \
        --service-account pyroscope \
        --role-arn "$(aws iam get-role --role-name pyroscope-eks-pod-role \
            --query 'Role.Arn' --output text --no-cli-pager)" \
        --no-cli-pager
    log_success "Pyroscope pod identity association created"
    sleep 10
else
    log_info "Pyroscope pod identity association already exists"
fi

# -----------------------------------------------------------------------------
# Pyroscope install (S3-backed single-binary; blocks under s3://<bucket>/pyroscope/)
# -----------------------------------------------------------------------------
log_info "Installing Pyroscope..."
cat > "${WORK}/pyroscope-values.yaml" <<EOF
pyroscope:
  service:
    type: ClusterIP
    port: 4040
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "4040"
      prometheus.io/path: /metrics
  persistence:
    enabled: false
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 2Gi
  # Pyroscope 2.x top-level keys only (1.x auth_enabled/recording_rules removed).
  structuredConfig:
    storage:
      backend: s3
      prefix: pyroscope
      s3:
        bucket_name: ${WORKSHOP_BUCKET}
        region: ${AWS_REGION}
        endpoint: s3.${AWS_REGION}.amazonaws.com
        native_aws_auth_enabled: true
    limits:
      retention_period: 168h
EOF

helm upgrade --install pyroscope grafana/pyroscope \
    --namespace "${NAMESPACE}" \
    --values "${WORK}/pyroscope-values.yaml" \
    --wait --timeout 10m

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=pyroscope \
    -n "${NAMESPACE}" --timeout=600s
log_success "Pyroscope installed"

# -----------------------------------------------------------------------------
# Grafana Profiles Drilldown plugin (pinned) + Pyroscope datasource
# -----------------------------------------------------------------------------
log_info "Installing Grafana Profiles Drilldown plugin..."
# Pin grafana-pyroscope-app to 1.17.0. The workshop serves Grafana over plain
# HTTP (not a secure context); the 2.x plugin line calls crypto.randomUUID() at
# load, which browsers only expose over HTTPS/localhost, so 2.x fails with
# "crypto.randomUUID is not a function". 1.17.0 is the last release whose entry
# bundle avoids that call. It targets React 18 -> requires Grafana 12.x (see the
# image.tag pin above); Grafana 13 ships React 19 and breaks the 1.x plugin.
helm upgrade --install grafana grafana-community/grafana \
    --namespace "${NAMESPACE}" \
    --reuse-values \
    --set "plugins={grafana-pyroscope-app@1.17.0}" \
    --wait --timeout 10m
log_success "Profiles Drilldown plugin installed"

log_info "Waiting for Grafana API after plugin upgrade..."
for i in {1..40}; do
    STATUS=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${GRAFANA_URL}/api/health" \
        | jq -r .database 2>/dev/null || true)
    [[ "${STATUS}" == "ok" ]] && break
    [[ $i -eq 40 ]] && { log_error "Grafana API not ready after 200s"; exit 1; }
    sleep 5
done

log_info "Provisioning Grafana Pyroscope datasource..."
cat > "${WORK}/pyroscope-datasource.yaml" <<EOF
apiVersion: 1
datasources:
  - uid: pyroscope
    name: Pyroscope
    type: grafana-pyroscope-datasource
    access: proxy
    url: http://pyroscope.${NAMESPACE}.svc.cluster.local:4040
    isDefault: false
    editable: true
EOF
kubectl create configmap monitoring-pyroscope-datasource \
    --from-file="${WORK}/pyroscope-datasource.yaml" -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap monitoring-pyroscope-datasource \
    -n "${NAMESPACE}" grafana_datasource=1 --overwrite
log_success "Grafana Pyroscope datasource provisioned"

# -----------------------------------------------------------------------------
# Grafana CloudWatch — Pod Identity for read-only metrics access + datasource.
# Used by the perf-platform Latency Metrics dashboard and ServiceLatency alert
# (immersion day); harmless for CON405 (its dashboards use Prometheus).
# -----------------------------------------------------------------------------
log_info "Binding Grafana ServiceAccount to grafana-eks-pod-role..."
if ! aws eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" \
        --query "associations[?serviceAccount=='grafana' && namespace=='${NAMESPACE}']" \
        --output text --no-cli-pager | grep -q .; then
    aws eks create-pod-identity-association \
        --cluster-name "${CLUSTER_NAME}" \
        --namespace "${NAMESPACE}" \
        --service-account grafana \
        --role-arn "$(aws iam get-role --role-name grafana-eks-pod-role \
            --query 'Role.Arn' --output text --no-cli-pager)" \
        --no-cli-pager
    log_success "Grafana CloudWatch pod identity association created"
else
    log_info "Grafana CloudWatch pod identity association already exists"
fi

# EKS Pod Identity associations are eventually consistent. Recreate Grafana until
# the current Running/Ready pod has the injected credential endpoint. This also
# repairs an existing pod that predates its association.
GRAFANA_POD=""
for i in {1..6}; do
    if (( i > 1 )); then
        log_info "Pod Identity credentials not injected yet; waiting before retry ${i}/6..."
        sleep 10
    fi
    log_info "Restarting Grafana to pick up Pod Identity credentials (${i}/6)..."
    kubectl rollout restart deployment/grafana -n "${NAMESPACE}"
    kubectl rollout status deployment/grafana -n "${NAMESPACE}" --timeout=180s
    GRAFANA_POD=$(kubectl get pods -n "${NAMESPACE}" \
        -l app.kubernetes.io/name=grafana -o json \
        | jq -r '[.items[]
            | select(.metadata.deletionTimestamp == null and .status.phase == "Running")
            | select([.status.containerStatuses[]?.ready] | all)
            | select([.spec.containers[].env[]?.name]
                | index("AWS_CONTAINER_CREDENTIALS_FULL_URI"))
            | .metadata.name] | first // empty')
    [[ -n "${GRAFANA_POD}" ]] && break
done
if [[ -z "${GRAFANA_POD}" ]]; then
    log_error "Grafana did not receive EKS Pod Identity credentials after 6 restarts"
    exit 1
fi
log_success "Grafana pod ${GRAFANA_POD} received EKS Pod Identity credentials"

log_info "Waiting for Grafana API after pod restart..."
for i in {1..40}; do
    STATUS=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${GRAFANA_URL}/api/health" \
        | jq -r .database 2>/dev/null || true)
    [[ "${STATUS}" == "ok" ]] && break
    [[ $i -eq 40 ]] && { log_error "Grafana API not ready after 200s"; exit 1; }
    sleep 5
done

log_info "Provisioning Grafana CloudWatch datasource..."
cat > "${WORK}/cloudwatch-datasource.yaml" <<EOF
apiVersion: 1
datasources:
  - uid: cloudwatch
    name: CloudWatch
    type: cloudwatch
    access: proxy
    isDefault: false
    editable: true
    jsonData:
      authType: default
      defaultRegion: ${AWS_REGION}
EOF
kubectl create configmap monitoring-cloudwatch-datasource \
    --from-file="${WORK}/cloudwatch-datasource.yaml" -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap monitoring-cloudwatch-datasource \
    -n "${NAMESPACE}" grafana_datasource=1 --overwrite

log_info "Verifying Grafana CloudWatch datasource credentials..."
for i in {1..12}; do
    CLOUDWATCH_RESPONSE=$(curl -sS -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        -w $'\n%{http_code}' \
        "${GRAFANA_URL}/api/datasources/uid/cloudwatch/health" 2>&1 || true)
    CLOUDWATCH_HTTP_STATUS="${CLOUDWATCH_RESPONSE##*$'\n'}"
    CLOUDWATCH_HEALTH="${CLOUDWATCH_RESPONSE%$'\n'*}"
    if [[ "${CLOUDWATCH_HTTP_STATUS}" == "200" ]] \
            && jq -e '
                .status == "OK"
                or ((.message // "")
                    | contains("Successfully queried the CloudWatch metrics API."))
            ' <<<"${CLOUDWATCH_HEALTH}" >/dev/null 2>&1; then
        break
    fi
    [[ $i -eq 12 ]] && {
        CLOUDWATCH_MESSAGE=$(jq -r '.message // empty' <<<"${CLOUDWATCH_HEALTH}" 2>/dev/null || true)
        [[ -z "${CLOUDWATCH_MESSAGE}" ]] && CLOUDWATCH_MESSAGE="${CLOUDWATCH_HEALTH:-empty response}"
        log_error "Grafana CloudWatch datasource is unhealthy (HTTP ${CLOUDWATCH_HTTP_STATUS}): ${CLOUDWATCH_MESSAGE}"
        exit 1
    }
    sleep 5
done
log_success "Grafana CloudWatch metrics access verified"

log_success "Monitoring stack deployed"
log_info "Grafana: http://$GRAFANA_LB"
log_info "Username: $GRAFANA_USER"
log_info "Password: $GRAFANA_PASSWORD"
log_info "Prometheus: http://prometheus-server.monitoring.svc.cluster.local (internal)"
log_info "Pyroscope: http://pyroscope.monitoring.svc.cluster.local:4040 (S3-backed, prefix s3://${WORKSHOP_BUCKET}/pyroscope/)"
log_info "Grafana datasources: Prometheus (promds), Pyroscope, CloudWatch (via grafana-eks-pod-role)"

# Emit for bootstrap summary
echo "✅ Success: Monitoring (Prometheus + Grafana + Pyroscope)"
