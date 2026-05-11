#!/bin/bash

# =============================================================================
# Agentic Performance Platform Setup
# Installs Pyroscope (with native recording rules), Kyverno JFR policy,
# Grafana alert wiring, internal NLB, and RBAC used by the perf-analyzer module.
#
# Runs in workshop bootstrap, after monitoring.sh (requires Prometheus+Grafana).
# Does not modify existing scripts or modules.
# =============================================================================

set -eo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

log_info "Starting agentic performance platform setup..."

# Source environment variables
source /etc/profile.d/workshop.sh

PREFIX="${PREFIX:-workshop}"
NAMESPACE="monitoring"
GRAFANA_USER="admin"

ALERT_RULE_TITLE="PerfProfileRegression"
CONTACT_POINT_NAME="perf-analyzer-webhook"
ANALYZER_WEBHOOK_URL="http://perf-analyzer.${NAMESPACE}.svc.cluster.local:8080/api/v1/grafana-webhook"

# Working files (cleaned up on exit)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# =============================================================================
# Prerequisites
# =============================================================================

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || {
    log_error "Namespace ${NAMESPACE} not found. Run monitoring.sh first."
    exit 1
}

helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

# =============================================================================
# Pyroscope (with native recording-rules -> Prometheus-scrapable metrics)
# =============================================================================

log_info "Installing Pyroscope..."
cat > "${WORK}/pyroscope-values.yaml" <<'EOF'
pyroscope:
  service:
    type: ClusterIP
    port: 4040
    # Expose /metrics on the same port; prometheus.io annotations below.
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "4040"
      prometheus.io/path: /metrics
  persistence:
    enabled: true
    size: 10Gi
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 2Gi
  # structuredConfig uses Pyroscope 2.x top-level keys only.
  # 1.x fields `auth_enabled` and `recording_rules` were removed in 2.x
  # and cause CrashLoopBackOff if included.
  structuredConfig:
    storage:
      backend: filesystem
      filesystem:
        dir: /data/blocks
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

# =============================================================================
# Pyroscope recording rule -> emits profile_cpu_self_seconds metric
# =============================================================================

log_info "Registering Pyroscope recording rule (profile_cpu_self_seconds)..."

# Pyroscope exposes a Connect/gRPC-Gateway JSON API for recording rules via
# settings.v1.RecordingRulesService. The call below upserts a rule that
# aggregates CPU self-time per service/version/pod into a Prometheus metric.
PYROSCOPE_SVC="http://pyroscope.${NAMESPACE}.svc.cluster.local:4040"

# Port-forward so the call runs from the IDE host.
pkill -f "port-forward.*pyroscope.*24040" >/dev/null 2>&1 || true
kubectl port-forward -n "${NAMESPACE}" svc/pyroscope 24040:4040 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null || true; rm -rf "${WORK}"' EXIT
sleep 3

RULE_BODY=$(cat <<'EOF'
{
  "rule": {
    "metricName": "profile_cpu_self_seconds",
    "matchers": ["{__profile_type__=\"process_cpu:cpu:nanoseconds:cpu:nanoseconds\"}"],
    "groupBy": ["service_name", "version", "pod"],
    "externalLabels": []
  }
}
EOF
)

curl -s -X POST -H "Content-Type: application/json" \
    -d "${RULE_BODY}" \
    "http://localhost:24040/settings.v1.RecordingRulesService/UpsertRecordingRule" \
    -o "${WORK}/rule-response.json" || true

if grep -q '"metricName"' "${WORK}/rule-response.json" 2>/dev/null; then
    log_success "Recording rule registered"
else
    log_warning "Recording rule registration response:"
    cat "${WORK}/rule-response.json" 2>/dev/null || true
    log_warning "Continuing; rule may already exist."
fi

kill ${PF_PID} 2>/dev/null || true
trap 'rm -rf "${WORK}"' EXIT

# =============================================================================
# RBAC for perf-analyzer and perf-collector
# =============================================================================

log_info "Applying RBAC for perf-analyzer and perf-collector..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: perf-analyzer
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: perf-analyzer
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: perf-analyzer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: perf-analyzer
subjects:
  - kind: ServiceAccount
    name: perf-analyzer
    namespace: ${NAMESPACE}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: perf-collector
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: perf-collector
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: perf-collector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: perf-collector
subjects:
  - kind: ServiceAccount
    name: perf-collector
    namespace: ${NAMESPACE}
EOF

log_success "RBAC applied"

# =============================================================================
# Internal NLB (two annotated LoadBalancer Services sharing one NLB)
# =============================================================================

log_info "Provisioning internal NLB for ECS reachability..."
# Apply sequentially: AWS Load Balancer Controller shares one NLB across two
# Services via `aws-load-balancer-name` only if the second Service sees the
# NLB already exists. A single concurrent `kubectl apply` makes both reconcile
# loops race — both try to CreateLoadBalancer and the second hits
# DuplicateLoadBalancerName and gets stuck.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: pyroscope-nlb
  namespace: ${NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internal
    service.beta.kubernetes.io/aws-load-balancer-name: perf-platform-internal
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: pyroscope
  ports:
    - name: pyroscope
      port: 4040
      targetPort: 4040
      protocol: TCP
EOF

log_info "Waiting for pyroscope-nlb to provision the shared NLB..."
NLB_DNS=""
for i in {1..60}; do
    NLB_DNS=$(kubectl get svc pyroscope-nlb -n "${NAMESPACE}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "${NLB_DNS}" ]]; then
        break
    fi
    sleep 10
done

if [[ -z "${NLB_DNS}" ]]; then
    log_error "NLB DNS was not assigned within 10 minutes"
    exit 1
fi

log_info "Attaching perf-analyzer listener to the same NLB..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: perf-analyzer-nlb
  namespace: ${NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internal
    service.beta.kubernetes.io/aws-load-balancer-name: perf-platform-internal
spec:
  type: LoadBalancer
  selector:
    app: perf-analyzer
  ports:
    - name: analyzer
      port: 8080
      targetPort: 8080
      protocol: TCP
EOF

for i in {1..30}; do
    ANALYZER_NLB_DNS=$(kubectl get svc perf-analyzer-nlb -n "${NAMESPACE}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "${ANALYZER_NLB_DNS}" ]]; then
        break
    fi
    sleep 5
done

aws ssm put-parameter \
    --name "perf-platform-internal-nlb" \
    --value "${NLB_DNS}" \
    --type String --overwrite --no-cli-pager >/dev/null

log_success "Internal NLB DNS stored in SSM: ${NLB_DNS}"

# =============================================================================
# Prometheus recording rule (ratio on Pyroscope-emitted metric)
# =============================================================================

log_info "Applying Prometheus recording rule..."

# Append the recording rule to Prometheus's serverFiles via helm upgrade --reuse-values.
# prometheus-community/prometheus then rewrites its own ConfigMap and the
# built-in configmap-reload sidecar reloads Prometheus runtime config.
cat > "${WORK}/perf-platform-rules.yaml" <<'RULES'
# profile_cpu_self_seconds is emitted by Pyroscope from the recording
# rule registered earlier. Compare each new version vs the prior baseline.
groups:
  - name: perf-platform
    interval: 30s
    rules:
      - record: perf:profile_cpu_ratio_5m
        expr: |
          (
            sum by (service_name) (
              rate(profile_cpu_self_seconds{version!=""}[5m])
            )
            /
            (
              avg by (service_name) (
                avg_over_time(
                  sum by (service_name) (
                    rate(profile_cpu_self_seconds{version!=""}[5m] offset 1h)
                  )[1h:5m]
                )
              )
              > 0
            )
          )
RULES

helm upgrade prometheus prometheus-community/prometheus \
    --namespace "${NAMESPACE}" \
    --reuse-values \
    --set-file "serverFiles.perf-platform\\.rules\\.yaml=${WORK}/perf-platform-rules.yaml" \
    --wait --timeout 5m

log_success "Prometheus recording rule applied"

# =============================================================================
# Grafana Pyroscope datasource + Profiles Drilldown plugin
# =============================================================================

log_info "Configuring Grafana..."

SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "${PREFIX}-ide-password" \
    --query 'SecretString' --output text --no-cli-pager)
GRAFANA_PASSWORD=$(echo "${SECRET_VALUE}" | jq -r '.password')

GRAFANA_LB=$(kubectl get svc grafana -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [[ -z "${GRAFANA_LB}" ]]; then
    log_error "Grafana LoadBalancer not found. Run monitoring.sh first."
    exit 1
fi
GRAFANA_URL="http://${GRAFANA_LB}"

# Install Profiles Drilldown plugin (idempotent).
log_info "Installing Grafana Profiles Drilldown plugin..."
helm upgrade --install grafana grafana/grafana \
    --namespace "${NAMESPACE}" \
    --reuse-values \
    --set "plugins={grafana-pyroscope-app}" \
    --wait --timeout 5m
log_success "Profiles Drilldown plugin installed"

# Wait for Grafana API to be ready after the helm upgrade restarts the pod.
log_info "Waiting for Grafana API to be ready..."
for i in {1..40}; do
    STATUS=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${GRAFANA_URL}/api/health" \
        | jq -r .database 2>/dev/null || true)
    if [[ "${STATUS}" == "ok" ]]; then
        log_info "Grafana API ready"
        break
    fi
    [[ $i -eq 40 ]] && { log_error "Grafana API not ready after 200s"; exit 1; }
    sleep 5
done

# Pyroscope datasource.
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
kubectl create configmap perf-platform-pyroscope-datasource \
    --from-file="${WORK}/pyroscope-datasource.yaml" -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap perf-platform-pyroscope-datasource \
    -n "${NAMESPACE}" grafana_datasource=1 --overwrite
log_success "Grafana Pyroscope datasource provisioned"

# Contact point.
EXISTING=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/v1/provisioning/contact-points" \
    | jq -r ".[] | select(.name == \"${CONTACT_POINT_NAME}\") | .uid" 2>/dev/null || true)
if [[ -n "${EXISTING}" ]]; then
    curl -s -X DELETE -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        "${GRAFANA_URL}/api/v1/provisioning/contact-points/${EXISTING}" >/dev/null
fi

CONTACT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    -d "{
      \"name\": \"${CONTACT_POINT_NAME}\",
      \"type\": \"webhook\",
      \"settings\": {
        \"url\": \"${ANALYZER_WEBHOOK_URL}\",
        \"httpMethod\": \"POST\"
      },
      \"disableResolveMessage\": true
    }" \
    "${GRAFANA_URL}/api/v1/provisioning/contact-points")

if echo "${CONTACT_RESPONSE}" | jq -e '.name' >/dev/null 2>&1; then
    log_success "Contact point ${CONTACT_POINT_NAME} created"
else
    log_error "Contact point creation failed: ${CONTACT_RESPONSE}"
    exit 1
fi

# Alert rule.
log_info "Creating Grafana alert rule ${ALERT_RULE_TITLE}..."
EXISTING_ALERT=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    | jq -r ".[] | select(.title == \"${ALERT_RULE_TITLE}\") | .uid" 2>/dev/null || true)
if [[ -n "${EXISTING_ALERT}" ]]; then
    curl -s -X DELETE -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${EXISTING_ALERT}" >/dev/null
fi

FOLDER_UID=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/folders" \
    | jq -r '.[] | select(.title == "Workshop Dashboards") | .uid' 2>/dev/null || echo "")

ALERT_BODY="{
  \"title\": \"${ALERT_RULE_TITLE}\",
  \"condition\": \"A\",
  \"data\": [
    {
      \"refId\": \"A\",
      \"relativeTimeRange\": {\"from\": 300, \"to\": 0},
      \"datasourceUid\": \"promds\",
      \"model\": {
        \"expr\": \"perf:profile_cpu_ratio_5m > 1.3\",
        \"instant\": true,
        \"refId\": \"A\"
      }
    }
  ],
  \"intervalSeconds\": 30,
  \"noDataState\": \"OK\",
  \"execErrState\": \"OK\",
  \"for\": \"2m\",
  \"ruleGroup\": \"perf-platform\",
  \"annotations\": {
    \"summary\": \"Profile CPU self-time regression detected\",
    \"description\": \"Service {{ \$labels.service_name }} CPU self-time ratio {{ \$value | printf \\\"%.2f\\\" }}x baseline\"
  },
  \"labels\": {
    \"severity\": \"warning\",
    \"alertname\": \"${ALERT_RULE_TITLE}\",
    \"analysis_type\": \"profiling\"
  }"

if [[ -n "${FOLDER_UID}" ]]; then
    ALERT_BODY="${ALERT_BODY}, \"folderUID\": \"${FOLDER_UID}\"}"
else
    ALERT_BODY="${ALERT_BODY}}"
fi

ALERT_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    -d "${ALERT_BODY}" \
    "${GRAFANA_URL}/api/v1/provisioning/alert-rules")

if echo "${ALERT_RESPONSE}" | jq -e '.uid' >/dev/null 2>&1; then
    log_success "Alert rule ${ALERT_RULE_TITLE} created"
else
    log_error "Alert rule creation failed: ${ALERT_RESPONSE}"
    exit 1
fi

# Notification policy.
log_info "Configuring notification policy..."
POLICY_BODY=$(cat <<EOF
{
  "receiver": "grafana-default-email",
  "group_by": ["alertname"],
  "group_wait": "30s",
  "group_interval": "5m",
  "repeat_interval": "1h",
  "routes": [
    {
      "receiver": "${CONTACT_POINT_NAME}",
      "matchers": ["analysis_type=profiling"],
      "group_by": ["alertname", "service_name"],
      "group_wait": "10s",
      "group_interval": "30s",
      "repeat_interval": "2m"
    }
  ]
}
EOF
)

POLICY_RESPONSE=$(curl -s -X PUT -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
    -d "${POLICY_BODY}" \
    "${GRAFANA_URL}/api/v1/provisioning/policies")

if echo "${POLICY_RESPONSE}" | grep -q "policies updated"; then
    log_success "Notification policy updated"
else
    log_warning "Notification policy response: ${POLICY_RESPONSE}"
fi

# =============================================================================
# Summary
# =============================================================================

log_info ""
log_info "Agentic performance platform ready."
log_info "  Pyroscope:          http://pyroscope.${NAMESPACE}.svc.cluster.local:4040"
log_info "  Internal NLB DNS:   ${NLB_DNS}  (SSM: perf-platform-internal-nlb)"
log_info "  Analyzer webhook:   ${ANALYZER_WEBHOOK_URL}"
log_info "  Grafana alert rule: ${ALERT_RULE_TITLE}"
log_info "  Grafana contact pt: ${CONTACT_POINT_NAME}"
log_info "  Profiles Drilldown: installed in Grafana"
log_info ""
log_info "Next: participants deploy perf-analyzer (module S1) and perf-collector (module S2)."

echo "✅ Success: Perf Platform (Pyroscope + recording rules + NLB + Grafana wiring)"
