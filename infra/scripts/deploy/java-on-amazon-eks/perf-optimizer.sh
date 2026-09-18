#!/bin/bash
# =============================================================================
# Phase 8 — perf-optimizer (Bedrock + Spring AI optimization agent, MCP server)
#
# Builds and pushes the image, provisions the Bedrock Knowledge Base (S3 Vectors)
# from the IDE role — no admin step, no SSM — and deploys the MCP server into the
# monitoring namespace. For the builders' session this is pre-run by the bootstrap;
# an extended lab has participants build it step by step.
#
# KB grounding is best-effort: if KB provisioning fails, the agent still runs and
# grounds on the bundled kb/*.md docs baked into the image.
#
# No admin: the KB execution role (perf-optimizer-kb-role, no permissions boundary)
# is created by CDK; this script only PASSES it to bedrock:CreateKnowledgeBase.
# The optimizer runs under its own SA (perf-optimizer) bound by Pod Identity to
# perf-optimizer-eks-pod-role (Bedrock + bedrock:Retrieve on the KB), both from CDK.
# The KB data source lives in the workshop bucket under perf-optimizer/kb/ (IDE
# role can write it; the CDK exec role can read it). Runs on the IDE (ec2-user).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source /etc/profile.d/workshop.sh

REGION="${AWS_REGION:-us-east-1}"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/perf-optimizer"
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO="${ECR_BASE}/perf-optimizer"
NS="monitoring"
CLUSTER_NAME="${PREFIX:-workshop}-eks"
MODEL="global.anthropic.claude-sonnet-4-6"

WS_BUCKET=$(aws ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text)
VECTOR_BUCKET="perf-optimizer-kb-vectors-${ACCOUNT_ID}"   # matches CDK role + IDE s3vectors scope (perf-optimizer-*)
INDEX="perf-optimizer-index"
KB_ROLE="perf-optimizer-kb-role"                          # CDK-created (no permissions boundary)
KB_NAME="perf-optimizer-kb"
KB_PREFIX="perf-optimizer/kb"                             # data-source prefix in the workshop bucket
EMBED_ARN="arn:aws:bedrock:${REGION}::foundation-model/amazon.titan-embed-text-v2:0"

# -----------------------------------------------------------------------------
# 1. Build + push the image (jib pushes straight to ECR; repo auto-creates).
# -----------------------------------------------------------------------------
log_info "Building and pushing perf-optimizer image..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ECR_BASE}"
( cd "${APP_DIR}" && mvn -q clean compile jib:build -Dimage="${REPO}:latest" ) \
  || { log_error "perf-optimizer build failed"; exit 1; }
log_success "perf-optimizer image pushed: ${REPO}:latest"

# -----------------------------------------------------------------------------
# 2. Provision the Bedrock Knowledge Base (S3 Vectors) — best-effort.
#    Sets KB_ID on success; leaves it empty to fall back to bundled kb/*.md.
# -----------------------------------------------------------------------------
KB_ID=""
provision_kb() {
  log_info "Ensuring S3 Vectors bucket + index..."
  aws s3vectors list-vector-buckets \
      --query "vectorBuckets[?vectorBucketName=='${VECTOR_BUCKET}']" --output text 2>/dev/null | grep -q . \
    || aws s3vectors create-vector-bucket --vector-bucket-name "${VECTOR_BUCKET}" >/dev/null
  aws s3vectors list-indexes --vector-bucket-name "${VECTOR_BUCKET}" \
      --query "indexes[?indexName=='${INDEX}']" --output text 2>/dev/null | grep -q . \
    || aws s3vectors create-index --vector-bucket-name "${VECTOR_BUCKET}" --index-name "${INDEX}" \
         --data-type float32 --dimension 1024 --distance-metric cosine >/dev/null

  log_info "Staging KB docs to s3://${WS_BUCKET}/${KB_PREFIX}/ ..."
  aws s3 cp "${APP_DIR}/kb/" "s3://${WS_BUCKET}/${KB_PREFIX}/" \
    --recursive --exclude "*" --include "*.md" >/dev/null

  KB_ID=$(aws bedrock-agent list-knowledge-bases \
    --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" --output text 2>/dev/null)
  if [ "${KB_ID}" = "None" ] || [ -z "${KB_ID}" ]; then
    log_info "Creating Knowledge Base ${KB_NAME} (passing ${KB_ROLE})..."
    for i in 1 2 3 4 5 6; do
      KB_ID=$(aws bedrock-agent create-knowledge-base --name "${KB_NAME}" \
        --description "perf-optimizer: right-sizing playbook + golden AOT/CRaC Dockerfiles" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${KB_ROLE}" \
        --knowledge-base-configuration "{\"type\":\"VECTOR\",\"vectorKnowledgeBaseConfiguration\":{\"embeddingModelArn\":\"${EMBED_ARN}\"}}" \
        --storage-configuration "{\"type\":\"S3_VECTORS\",\"s3VectorsConfiguration\":{\"vectorBucketArn\":\"arn:aws:s3vectors:${REGION}:${ACCOUNT_ID}:bucket/${VECTOR_BUCKET}\",\"indexName\":\"${INDEX}\"}}" \
        --query 'knowledgeBase.knowledgeBaseId' --output text 2>/tmp/kberr) && break
      log_warning "  create attempt ${i} failed (role may still be propagating), retrying in 10s..."; sed 's/^/    /' /tmp/kberr 2>/dev/null; sleep 10
    done
  fi
  if [ "${KB_ID}" = "None" ] || [ -z "${KB_ID}" ]; then
    log_warning "KB creation failed — continuing with bundled kb/*.md grounding."; KB_ID=""; return 0
  fi
  log_info "KB_ID=${KB_ID}; waiting for ACTIVE..."
  until [ "$(aws bedrock-agent get-knowledge-base --knowledge-base-id "${KB_ID}" \
      --query 'knowledgeBase.status' --output text 2>/dev/null)" = "ACTIVE" ]; do echo -n "."; sleep 5; done; echo " ACTIVE"

  local DS_ID
  DS_ID=$(aws bedrock-agent list-data-sources --knowledge-base-id "${KB_ID}" \
    --query "dataSourceSummaries[?name=='optimizer-docs'].dataSourceId | [0]" --output text 2>/dev/null)
  if [ "${DS_ID}" = "None" ] || [ -z "${DS_ID}" ]; then
    DS_ID=$(aws bedrock-agent create-data-source --knowledge-base-id "${KB_ID}" --name optimizer-docs \
      --data-source-configuration "{\"type\":\"S3\",\"s3Configuration\":{\"bucketArn\":\"arn:aws:s3:::${WS_BUCKET}\",\"inclusionPrefixes\":[\"${KB_PREFIX}/\"]}}" \
      --query 'dataSource.dataSourceId' --output text)
  fi
  local JOB_ID
  JOB_ID=$(aws bedrock-agent start-ingestion-job --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" \
    --query 'ingestionJob.ingestionJobId' --output text)
  log_info "Ingesting KB docs..."
  until [ "$(aws bedrock-agent get-ingestion-job --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" \
      --ingestion-job-id "${JOB_ID}" --query 'ingestionJob.status' --output text)" != "IN_PROGRESS" ]; do echo -n "."; sleep 5; done; echo " ingested"
  log_success "Bedrock KB ready: ${KB_ID}"
}
provision_kb

# -----------------------------------------------------------------------------
# 3. perf-optimizer ServiceAccount + Pod Identity binding to the CDK-managed
#    perf-optimizer-eks-pod-role (Bedrock Converse + bedrock:Retrieve on the KB).
#    Own SA — no reuse of perf-analyzer and no dependency on perf-platform.sh.
# -----------------------------------------------------------------------------
kubectl get sa perf-optimizer -n "${NS}" >/dev/null 2>&1 \
  || kubectl create serviceaccount perf-optimizer -n "${NS}"
if ! aws eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" \
      --query "associations[?serviceAccount=='perf-optimizer' && namespace=='${NS}']" \
      --output text --no-cli-pager | grep -q .; then
  aws eks create-pod-identity-association --cluster-name "${CLUSTER_NAME}" \
    --namespace "${NS}" --service-account perf-optimizer \
    --role-arn "$(aws iam get-role --role-name perf-optimizer-eks-pod-role --query 'Role.Arn' --output text --no-cli-pager)" \
    --no-cli-pager >/dev/null
  log_success "Pod Identity association created (perf-optimizer -> perf-optimizer-eks-pod-role)"
  sleep 10
fi

# -----------------------------------------------------------------------------
# 3b. Read-only ClusterRole for the optimizer's K8s fact collection (deployments,
#     pods) + sidecar /dump pod-IP discovery. NO write verbs — the optimizer
#     never mutates the cluster (acceptance criterion 5). Bound to the
#     perf-optimizer SA.
# -----------------------------------------------------------------------------
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: perf-optimizer
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: perf-optimizer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: perf-optimizer
subjects:
  - kind: ServiceAccount
    name: perf-optimizer
    namespace: ${NS}
EOF
log_success "perf-optimizer read-only ClusterRole applied (get/list/watch only)"

# -----------------------------------------------------------------------------
# 4. Deploy the MCP server. Wire the KB id when provisioned; otherwise the agent
#    grounds on the bundled kb/*.md docs.
# -----------------------------------------------------------------------------
log_info "Deploying perf-optimizer to ${NS}..."
KB_ENV=""
[ -n "${KB_ID}" ] && KB_ENV="        - {name: SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID, value: \"${KB_ID}\"}"

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-optimizer
  namespace: ${NS}
  labels: {app: perf-optimizer}
spec:
  replicas: 1
  selector: {matchLabels: {app: perf-optimizer}}
  template:
    metadata: {labels: {app: perf-optimizer}}
    spec:
      serviceAccountName: perf-optimizer   # Pod Identity -> perf-optimizer-eks-pod-role (Bedrock + KB Retrieve)
      containers:
      - name: perf-optimizer
        image: ${REPO}:latest
        ports: [{containerPort: 8080}]
        env:
        - {name: AWS_REGION, value: "${REGION}"}
        - {name: PYROSCOPE_URL, value: "http://pyroscope.monitoring:4040"}
        - {name: PROMETHEUS_URL, value: "http://prometheus-server.monitoring"}
        - {name: SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MODEL, value: "${MODEL}"}
${KB_ENV}
        readinessProbe: {httpGet: {path: /actuator/health, port: 8080}, initialDelaySeconds: 20, periodSeconds: 10}
        resources:
          requests: {cpu: "250m", memory: "512Mi"}
          limits:   {cpu: "1",    memory: "1Gi"}
---
apiVersion: v1
kind: Service
metadata: {name: perf-optimizer, namespace: ${NS}}
spec:
  selector: {app: perf-optimizer}
  ports: [{port: 8080, targetPort: 8080}]
  type: ClusterIP
EOF

# Force a fresh pull of the just-built :latest (apply is a no-op if the image
# string is unchanged).
kubectl -n "${NS}" rollout restart deploy/perf-optimizer >/dev/null 2>&1 || true
kubectl -n "${NS}" rollout status deploy/perf-optimizer --timeout=200s || {
  log_error "rollout not ready; recent logs:"; kubectl -n "${NS}" logs -l app=perf-optimizer --tail=60; exit 1; }

if [ -n "${KB_ID}" ]; then
  log_success "perf-optimizer up with managed KB grounding (KB ${KB_ID}); bundled kb/*.md remains as fallback."
else
  log_success "perf-optimizer up with bundled kb/*.md grounding (no managed KB)."
fi

# -----------------------------------------------------------------------------
# 5. Optimization dashboard — the visual the optimizer's numbers move. Shipped as
#    a ConfigMap (label grafana_dashboard=1) that the Grafana sidecar imports into
#    the "Workshop Dashboards" folder (grafana_folder annotation + monitoring.sh's
#    folderAnnotation). All panels read the Prometheus datasource (uid promds) and
#    filter to the unicorn-store-spring container. Time range 1h, refresh 15s.
# -----------------------------------------------------------------------------
log_info "Provisioning Optimization dashboard (ConfigMap -> Grafana sidecar)..."
DASH=$(mktemp)
cat > "${DASH}" <<'DASH_EOF'
{
  "title": "Optimization",
  "uid": "perf-optimizer-optimization",
  "tags": ["optimization", "java", "workshop"],
  "timezone": "browser",
  "schemaVersion": 39,
  "refresh": "15s",
  "time": { "from": "now-1h", "to": "now" },
  "templating": { "list": [] },
  "panels": [
    { "type": "row", "id": 100, "title": "At a glance",
      "gridPos": { "x": 0, "y": 0, "w": 24, "h": 1 }, "collapsed": false },
    { "type": "stat", "id": 1, "title": "Startup (ready time)",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 0, "y": 1, "w": 5, "h": 4 },
      "fieldConfig": { "defaults": { "unit": "s" } },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false }, "graphMode": "none" },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "max(application_ready_time_seconds{namespace=\"unicorn-store-spring\"})" } ] },
    { "type": "stat", "id": 2, "title": "Working set",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 5, "y": 1, "w": 5, "h": 4 },
      "fieldConfig": { "defaults": { "unit": "bytes" } },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false }, "graphMode": "none" },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "max(container_memory_working_set_bytes{namespace=\"unicorn-store-spring\",container=\"unicorn-store-spring\"})" } ] },
    { "type": "stat", "id": 3, "title": "Memory limit",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 10, "y": 1, "w": 5, "h": 4 },
      "fieldConfig": { "defaults": { "unit": "bytes" } },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false }, "graphMode": "none" },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "max(kube_pod_container_resource_limits{namespace=\"unicorn-store-spring\",container=\"unicorn-store-spring\",resource=\"memory\"})" } ] },
    { "type": "stat", "id": 4, "title": "Replicas ready",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 15, "y": 1, "w": 5, "h": 4 },
      "fieldConfig": { "defaults": { "unit": "short" } },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false }, "graphMode": "none" },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "max(kube_deployment_status_replicas_ready{namespace=\"unicorn-store-spring\",deployment=\"unicorn-store-spring\"})" } ] },
    { "type": "stat", "id": 5, "title": "Nodes",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 20, "y": 1, "w": 4, "h": 4 },
      "fieldConfig": { "defaults": { "unit": "short" } },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false }, "graphMode": "none" },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "count(kube_node_info)" } ] },
    { "type": "row", "id": 200, "title": "Trends",
      "gridPos": { "x": 0, "y": 5, "w": 24, "h": 1 }, "collapsed": false },
    { "type": "timeseries", "id": 6, "title": "Startup per pod (ready time)",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 0, "y": 6, "w": 12, "h": 8 },
      "fieldConfig": { "defaults": { "unit": "s" } },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "application_ready_time_seconds{namespace=\"unicorn-store-spring\"}", "legendFormat": "{{pod}}" } ] },
    { "type": "timeseries", "id": 7, "title": "Working set vs memory limit",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 12, "y": 6, "w": 12, "h": 8 },
      "fieldConfig": { "defaults": { "unit": "bytes" } },
      "targets": [
        { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
          "expr": "sum by (pod) (container_memory_working_set_bytes{namespace=\"unicorn-store-spring\",container=\"unicorn-store-spring\"})", "legendFormat": "working set {{pod}}" },
        { "refId": "B", "datasource": { "type": "prometheus", "uid": "promds" },
          "expr": "max(kube_pod_container_resource_limits{namespace=\"unicorn-store-spring\",container=\"unicorn-store-spring\",resource=\"memory\"})", "legendFormat": "limit" } ] },
    { "type": "timeseries", "id": 8, "title": "CPU usage vs limit (cores)",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 0, "y": 14, "w": 12, "h": 8 },
      "fieldConfig": { "defaults": { "unit": "short" } },
      "targets": [
        { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
          "expr": "sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"unicorn-store-spring\",container=\"unicorn-store-spring\"}[5m]))", "legendFormat": "cpu {{pod}}" },
        { "refId": "B", "datasource": { "type": "prometheus", "uid": "promds" },
          "expr": "max(kube_pod_container_resource_limits{namespace=\"unicorn-store-spring\",container=\"unicorn-store-spring\",resource=\"cpu\"})", "legendFormat": "limit" } ] },
    { "type": "timeseries", "id": 9, "title": "Container restarts",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 12, "y": 14, "w": 12, "h": 8 },
      "fieldConfig": { "defaults": { "unit": "short" } },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "sum by (pod) (kube_pod_container_status_restarts_total{namespace=\"unicorn-store-spring\",container=\"unicorn-store-spring\"})", "legendFormat": "{{pod}}" } ] },
    { "type": "timeseries", "id": 10, "title": "Replicas ready",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 0, "y": 22, "w": 12, "h": 8 },
      "fieldConfig": { "defaults": { "unit": "short" } },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "kube_deployment_status_replicas_ready{namespace=\"unicorn-store-spring\",deployment=\"unicorn-store-spring\"}", "legendFormat": "ready" } ] },
    { "type": "timeseries", "id": 11, "title": "Node count",
      "datasource": { "type": "prometheus", "uid": "promds" },
      "gridPos": { "x": 12, "y": 22, "w": 12, "h": 8 },
      "fieldConfig": { "defaults": { "unit": "short" } },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "promds" },
        "expr": "count(kube_node_info)", "legendFormat": "nodes" } ] }
  ]
}
DASH_EOF
kubectl create configmap perf-optimizer-dashboard \
  --from-file=optimization.json="${DASH}" -n "${NS}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label   configmap perf-optimizer-dashboard -n "${NS}" grafana_dashboard=1 --overwrite
kubectl annotate configmap perf-optimizer-dashboard -n "${NS}" grafana_folder="Workshop Dashboards" --overwrite
rm -f "${DASH}"
log_success "Optimization dashboard provisioned (Workshop Dashboards / Optimization)"

echo "✅ Success: perf-optimizer (image ${REPO}:latest${KB_ID:+, KB ${KB_ID}})"
log_info "Connect Claude Code (this instance) over MCP/SSE — register at user scope, run from the app folder:"
log_info "  kubectl -n ${NS} port-forward svc/perf-optimizer 8080:8080 &"
log_info "  claude mcp add -s user --transport sse perf-optimizer http://localhost:8080/sse"
log_info "  cd unicorn-store-spring && claude   # app folder: Dockerfile + k8s/deployment.yaml"
log_info "Then ask Claude Code: \"use perf-optimizer to optimize unicorn-store-spring, then apply the plan\""
