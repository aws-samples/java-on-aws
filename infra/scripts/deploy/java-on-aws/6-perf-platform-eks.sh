#!/bin/bash

# Agentic Performance Platform (Amazon EKS) - deploy collector + analyzer,
# onboard the workload, create the latency alert rule, and drive the regression.
#
# Mirrors the workshop content, EKS path only:
#   java-on-aws-immersion-day/content/analysis/perf-platform/
#     collector/  -> build + deploy the perf-collector DaemonSet
#     analyzer/   -> build + deploy the perf-analyzer Service
#     on-demand/  -> onboard unicorn-store-spring (label + annotations)
#     on-alert/   -> create ServiceLatency-eks alert rule, then "Driving the regression"
#
# Runs the same commands/flow as the lab, made idempotent and re-runnable, with
# the necessary waits and checks. Ends with the on-alert "Driving the regression"
# load test (artillery 200 rps for 4 minutes, foreground).
#
# Prerequisites:
#   - 1-containerize.sh and 2-eks.sh have been run (unicorn-store-spring on EKS).
#   - The OSS monitoring stack (Prometheus/Pyroscope/Grafana) and the perf-platform
#     Grafana objects (CloudWatch datasource, Latency dashboard, perf-analyzer
#     contact point + notification policy) were provisioned by the workshop bootstrap.

# Source common utilities (enables set -e + ERR trap)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# Source environment variables (ACCOUNT_ID, AWS_REGION)
source /etc/profile.d/workshop.sh

CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2)
APP_NAMESPACE="unicorn-store-spring"
APP_NAME="unicorn-store-spring"
MON_NS="monitoring"
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

log_info "Deploying the Agentic Performance Platform on Amazon EKS..."
log_info "AWS Account: $ACCOUNT_ID"
log_info "AWS Region:  $AWS_REGION"
log_info "EKS Cluster: $CLUSTER_NAME"

# Fail fast if the monitoring stack is not present (provisioned by bootstrap).
if ! kubectl get ns "${MON_NS}" >/dev/null 2>&1; then
  log_error "Namespace '${MON_NS}' not found. The monitoring stack must be provisioned first."
  exit 1
fi

S3_BUCKET=$(aws ssm get-parameter --name workshop-bucket-name \
  --query 'Parameter.Value' --output text --no-cli-pager)
log_info "Workshop S3 bucket: ${S3_BUCKET}"

# ============================================================================
# SECTION 1: Deploy the collector (DaemonSet on Amazon EKS)
# ============================================================================
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 1: Deploying the collector"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Copying perf-collector sources..."
cp -r ~/java-on-aws/apps/perf-collector ~/environment/
log_success "perf-collector sources copied"

log_info "Building and pushing the perf-collector image..."
cd ~/environment/perf-collector
aws ecr get-login-password --region ${AWS_REGION} \
  | docker login --username AWS --password-stdin ${ECR_BASE}
COLLECTOR_ECR_URI=${ECR_BASE}/perf-collector
mvn clean compile jib:build -Dimage=${COLLECTOR_ECR_URI}:latest
log_success "perf-collector image pushed: ${COLLECTOR_ECR_URI}:latest"

log_info "Binding perf-collector ServiceAccount to perf-collector-eks-pod-role..."
if ! aws eks list-pod-identity-associations --cluster-name ${CLUSTER_NAME} \
      --query "associations[?serviceAccount=='perf-collector' && namespace=='${MON_NS}']" \
      --output text --no-cli-pager | grep -q .; then
  aws eks create-pod-identity-association \
    --cluster-name ${CLUSTER_NAME} \
    --namespace ${MON_NS} \
    --service-account perf-collector \
    --role-arn $(aws iam get-role --role-name perf-collector-eks-pod-role \
        --query 'Role.Arn' --output text --no-cli-pager) \
    --no-cli-pager
  log_success "Pod Identity association created"
else
  log_success "Pod Identity association already exists"
fi
sleep 15

log_info "Applying the perf-collector DaemonSet..."
mkdir -p ~/environment/perf-collector/k8s/
cat <<EOF > ~/environment/perf-collector/k8s/daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: perf-collector
  namespace: monitoring
  labels:
    app: perf-collector
spec:
  selector:
    matchLabels:
      app: perf-collector
  template:
    metadata:
      labels:
        app: perf-collector
    spec:
      serviceAccountName: perf-collector
      hostPID: true
      containers:
      - name: perf-collector
        image: ${COLLECTOR_ECR_URI}:latest
        securityContext:
          runAsUser: 0
          privileged: true
        volumeMounts:
        - name: profiler-host
          mountPath: /var/perf-collector
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: AWS_REGION
          value: "${AWS_REGION}"
        - name: AWS_S3_BUCKET
          value: "${S3_BUCKET}"
        - name: PERF_COLLECTOR_PLATFORM
          value: "eks"
        - name: PYROSCOPE_URL
          value: "http://pyroscope.monitoring:4040"
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
      volumes:
      - name: profiler-host
        hostPath:
          path: /var/perf-collector
          type: DirectoryOrCreate
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: perf-collector
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: perf-collector
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: perf-collector
subjects:
- kind: ServiceAccount
  name: perf-collector
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: perf-collector
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f ~/environment/perf-collector/k8s/daemonset.yaml

# The collector is a DaemonSet (one pod per node). A small, compute-optimized
# EKS Auto node (e.g. c6a.large, ~3Gi) can be memory-saturated by the monitoring
# stack and unable to fit the 256Mi collector pod. That is harmless as long as
# the collector runs on the node(s) hosting the target workload, so wait for
# coverage of the workload node(s) rather than requiring every DaemonSet pod to
# be Ready (a plain `kubectl rollout status` would hang and then hard-fail).
kubectl rollout status daemonset/perf-collector -n ${MON_NS} --timeout=120s \
  || log_warning "DaemonSet not fully rolled out; a node may be too small to fit the collector. Checking workload coverage..."

log_info "Confirming a collector pod runs on the node(s) hosting ${APP_NAME}..."
COVERED=""
for i in {1..18}; do
  WORKLOAD_NODES=$(kubectl get pods -n ${APP_NAMESPACE} -l app=${APP_NAME} \
    --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u)
  COLLECTOR_NODES=$(kubectl get pods -n ${MON_NS} -l app=perf-collector \
    --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u)
  if [[ -n "${WORKLOAD_NODES}" ]]; then
    COVERED="yes"
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      echo "${COLLECTOR_NODES}" | grep -qx "$n" || COVERED=""
    done <<< "${WORKLOAD_NODES}"
    [[ -n "${COVERED}" ]] && break
  fi
  log_info "Waiting for collector coverage of workload node(s)... ($i/18)"
  sleep 10
done

if [[ -z "${COVERED}" ]]; then
  log_error "No perf-collector pod is Running on the node(s) hosting ${APP_NAME}."
  kubectl get pods -n ${MON_NS} -l app=perf-collector -o wide || true
  exit 1
fi
log_success "perf-collector covers the workload node(s)"

# Surface, but tolerate, collector pods that cannot schedule on saturated nodes.
PENDING=$(kubectl get pods -n ${MON_NS} -l app=perf-collector \
  --field-selector=status.phase=Pending -o name 2>/dev/null || true)
if [[ -n "${PENDING}" ]]; then
  log_warning "Some collector pods are Pending (a node is too small/saturated to fit the 256Mi request)."
  log_warning "Expected on tight EKS Auto nodes and harmless here — the collector covers the workload node(s)."
fi

log_info "Collector pods:"
kubectl get pods -n ${MON_NS} -l app=perf-collector -o wide
kubectl logs -n ${MON_NS} -l app=perf-collector --tail=20 || true

# ============================================================================
# SECTION 2: Build and deploy the analyzer
# ============================================================================
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 2: Building the analyzer"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Copying perf-analyzer sources..."
cp -r ~/java-on-aws/apps/perf-analyzer ~/environment/
log_success "perf-analyzer sources copied"

log_info "Building and pushing the perf-analyzer image..."
cd ~/environment/perf-analyzer
aws ecr get-login-password --region ${AWS_REGION} \
  | docker login --username AWS --password-stdin ${ECR_BASE}
ANALYZER_ECR_URI=${ECR_BASE}/perf-analyzer
mvn clean compile jib:build -Dimage=${ANALYZER_ECR_URI}:latest
log_success "perf-analyzer image pushed: ${ANALYZER_ECR_URI}:latest"

log_info "Binding perf-analyzer ServiceAccount to perf-analyzer-eks-pod-role..."
if ! aws eks list-pod-identity-associations --cluster-name ${CLUSTER_NAME} \
      --query "associations[?serviceAccount=='perf-analyzer' && namespace=='${MON_NS}']" \
      --output text --no-cli-pager | grep -q .; then
  aws eks create-pod-identity-association \
    --cluster-name ${CLUSTER_NAME} \
    --namespace ${MON_NS} \
    --service-account perf-analyzer \
    --role-arn $(aws iam get-role --role-name perf-analyzer-eks-pod-role \
        --query 'Role.Arn' --output text --no-cli-pager) \
    --no-cli-pager
  log_success "Pod Identity association created"
else
  log_success "Pod Identity association already exists"
fi
sleep 15

log_info "Deploying the perf-analyzer to Amazon EKS..."
mkdir -p ~/environment/perf-analyzer/k8s/
cat <<EOF > ~/environment/perf-analyzer/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-analyzer
  namespace: monitoring
  labels:
    app: perf-analyzer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-analyzer
  template:
    metadata:
      labels:
        app: perf-analyzer
    spec:
      serviceAccountName: perf-analyzer
      containers:
      - name: perf-analyzer
        image: ${ANALYZER_ECR_URI}:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
        env:
        - name: AWS_REGION
          value: "${AWS_REGION}"
        - name: AWS_S3_BUCKET
          value: "${S3_BUCKET}"
        - name: PYROSCOPE_URL
          value: "http://pyroscope.monitoring:4040"
        - name: SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MODEL
          value: "global.anthropic.claude-sonnet-4-6"
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: perf-analyzer
  namespace: monitoring
spec:
  selector:
    app: perf-analyzer
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: perf-analyzer
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: perf-analyzer
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: perf-analyzer
subjects:
- kind: ServiceAccount
  name: perf-analyzer
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: perf-analyzer
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f ~/environment/perf-analyzer/k8s/deployment.yaml
kubectl wait deployment perf-analyzer -n ${MON_NS} --for condition=Available=True --timeout=180s
log_success "perf-analyzer is available"

log_info "Analyzer logs (looking for clean startup):"
kubectl logs -n ${MON_NS} -l app=perf-analyzer --tail=50 || true

# ============================================================================
# SECTION 3: Onboard unicorn-store-spring (on-demand chapter)
# ============================================================================
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 3: Onboarding unicorn-store-spring"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Adding the perf-profile opt-in label and github annotations..."
kubectl patch deploy/unicorn-store-spring -n ${APP_NAMESPACE} --type=strategic --patch '
spec:
  template:
    metadata:
      labels:
        perf-profile/service: unicorn-store-spring
      annotations:
        perf-profile/github-repo: aws-samples/java-on-aws
        perf-profile/github-path: apps/unicorn-store-spring
'
kubectl rollout status deploy/unicorn-store-spring -n ${APP_NAMESPACE} --timeout=180s
log_success "Workload onboarded (label + annotations applied)"

log_info "Waiting for the collector to attach and stream samples..."
sleep 30
ATTACHED=""
for i in {1..12}; do
  ATTACHED=$(kubectl logs -n ${MON_NS} -l app=perf-collector --tail=200 2>/dev/null \
    | grep -E 'Attached|Pushed' | tail -10 || true)
  if [[ -n "$ATTACHED" ]]; then
    log_success "Collector attached / pushing samples:"
    echo "$ATTACHED"
    break
  fi
  log_info "Waiting for collector attach... ($i/12)"
  sleep 10
done
if [[ -z "$ATTACHED" ]]; then
  log_warning "No 'Attached'/'Pushed' lines seen yet; the collector may still be discovering the JVM."
fi

# End-to-end sanity check: trigger one on-demand analysis on the quiet service.
# The analyzer returns 202 immediately; the report lands in S3 asynchronously.
log_info "Triggering a first on-demand analysis (sanity check)..."
POD=$(kubectl get pods -n ${APP_NAMESPACE} \
  -l app=unicorn-store-spring --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$POD" ]]; then
  kubectl run -n ${MON_NS} trigger-analyze --rm -i --restart=Never \
    --image=curlimages/curl:latest --quiet -- \
    curl -sS -X POST "http://perf-analyzer.monitoring.svc.cluster.local:8080/api/v1/analyze" \
      -H 'Content-Type: application/json' \
      -d "{\"service\":\"unicorn-store-spring\",\"platform\":\"eks\",\"pod\":\"${POD}\",\"reason\":\"pre-change check\"}" \
    || log_warning "On-demand analyze trigger returned non-zero (non-fatal)"
else
  log_warning "Could not resolve a running unicorn-store-spring pod for the sanity analysis (non-fatal)"
fi

# ============================================================================
# SECTION 4: Create the ServiceLatency-eks alert rule (on-alert chapter)
# ============================================================================
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 4: Creating the ServiceLatency-eks alert rule"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Discovering the ALB CloudWatch dimension..."
INGRESS_DNS=$(kubectl get ingress unicorn-store-spring -n ${APP_NAMESPACE} \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName=='${INGRESS_DNS}'].LoadBalancerArn" \
  --output text --no-cli-pager)
ALB_DIM=$(echo "${ALB_ARN}" | sed 's|.*loadbalancer/||')
PLATFORM_SUFFIX=eks
SERVICE_NAME_LABEL=unicorn-store-spring-${PLATFORM_SUFFIX}
log_info "ALB dimension: ${ALB_DIM}"
log_info "service_name label: ${SERVICE_NAME_LABEL}"
if [[ -z "${ALB_DIM}" ]]; then
  log_error "Could not resolve the ALB dimension for ingress '${INGRESS_DNS}'."
  exit 1
fi

GRAFANA_URL=http://$(kubectl get svc grafana -n ${MON_NS} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
GRAFANA_PASSWORD=$(kubectl get secret grafana-admin -n ${MON_NS} -o jsonpath='{.data.password}' | base64 --decode)
FOLDER_UID=$(curl -s -u "admin:${GRAFANA_PASSWORD}" "${GRAFANA_URL}/api/folders" \
  | jq -r '.[] | select(.title=="Workshop Dashboards") | .uid')
if [[ -z "${FOLDER_UID}" || "${FOLDER_UID}" == "null" ]]; then
  log_error "Grafana 'Workshop Dashboards' folder not found. The perf-platform Grafana"
  log_error "objects (folder, dashboard, contact point, notification policy) are provisioned"
  log_error "by the workshop bootstrap (perf-platform.sh). Re-run it before creating the rule."
  exit 1
fi
log_info "Grafana Workshop Dashboards folder UID: ${FOLDER_UID}"

# Idempotency: remove any existing ServiceLatency-eks rule before recreating it.
log_info "Removing any existing ServiceLatency-${PLATFORM_SUFFIX} rule..."
EXISTING_RULE_UID=$(curl -s -u "admin:${GRAFANA_PASSWORD}" \
  "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
  | jq -r ".[] | select(.title==\"ServiceLatency-${PLATFORM_SUFFIX}\") | .uid" 2>/dev/null || true)
if [[ -n "${EXISTING_RULE_UID}" ]]; then
  curl -s -X DELETE -u "admin:${GRAFANA_PASSWORD}" \
    "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${EXISTING_RULE_UID}" >/dev/null || true
  log_info "  Removed existing rule ${EXISTING_RULE_UID}"
fi

log_info "Creating the ServiceLatency-${PLATFORM_SUFFIX} alert rule..."
cat > /tmp/service-latency-alert.json <<EOF
{
  "title": "ServiceLatency-${PLATFORM_SUFFIX}",
  "ruleGroup": "workshop-analysis-group",
  "folderUID": "${FOLDER_UID}",
  "condition": "C",
  "noDataState": "OK",
  "execErrState": "OK",
  "for": "1m",
  "intervalSeconds": 30,
  "data": [
    {
      "refId": "A",
      "relativeTimeRange": {"from": 120, "to": 0},
      "datasourceUid": "cloudwatch",
      "model": {
        "refId": "A",
        "datasource": {"type": "cloudwatch", "uid": "cloudwatch"},
        "queryMode": "Metrics",
        "region": "${AWS_REGION}",
        "namespace": "AWS/ApplicationELB",
        "metricName": "TargetResponseTime",
        "statistic": "p99",
        "dimensions": {"LoadBalancer": "${ALB_DIM}"},
        "period": "60",
        "matchExact": true,
        "metricEditorMode": 0,
        "metricQueryType": 0
      }
    },
    {
      "refId": "B",
      "datasourceUid": "__expr__",
      "model": {"refId": "B", "type": "reduce", "expression": "A", "reducer": "max",
                "datasource": {"type": "__expr__", "uid": "__expr__"}}
    },
    {
      "refId": "C",
      "datasourceUid": "__expr__",
      "model": {"refId": "C", "type": "threshold", "expression": "B",
                "datasource": {"type": "__expr__", "uid": "__expr__"},
                "conditions": [{"evaluator": {"type": "gt", "params": [1.0]},
                                "operator": {"type": "and"},
                                "query": {"params": ["B"]},
                                "reducer": {"type": "last"}, "type": "query"}]}
    }
  ],
  "annotations": {"summary": "ALB p99 TargetResponseTime > 1s on unicorn-store-spring (${PLATFORM_SUFFIX})"},
  "labels": {
    "alertname": "ServiceLatency-${PLATFORM_SUFFIX}",
    "service_name": "${SERVICE_NAME_LABEL}",
    "analysis_type": "perf-platform"
  }
}
EOF

curl -s -X POST -u "admin:${GRAFANA_PASSWORD}" \
  -H "Content-Type: application/json" -d @/tmp/service-latency-alert.json \
  "${GRAFANA_URL}/api/v1/provisioning/alert-rules" | jq '{title, uid, ruleGroup}'

log_info "Confirming the rule is healthy..."
curl -s -u "admin:${GRAFANA_PASSWORD}" \
  "${GRAFANA_URL}/api/prometheus/grafana/api/v1/rules" \
  | jq '.data.groups[].rules[] | select(.name | startswith("ServiceLatency-")) | {name, state, lastEvaluation}' || true
log_success "ServiceLatency-${PLATFORM_SUFFIX} alert rule created"

# ============================================================================
# SECTION 5: Driving the regression (on-alert chapter, final step)
# ============================================================================
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 5: Driving the regression"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "200 requests/sec for 4 minutes against the workload's ALB."
log_info "The alert transitions Normal -> Pending -> Firing, and Grafana posts the"
log_info "webhook to the analyzer. This runs in the foreground for the full 4 minutes."

ANALYSIS_PREFIX="perf-platform/analysis/eks/unicorn-store-spring/"

# Record the newest report that exists BEFORE the regression, so we can tell the
# webhook-triggered report apart from the on-demand sanity report above.
BASELINE_REPORT=$(aws s3 ls "s3://${S3_BUCKET}/${ANALYSIS_PREFIX}" --recursive --no-cli-pager 2>/dev/null \
  | grep analysis.md | sort | tail -1 | awk '{print $4}' || true)
log_info "Baseline latest report before regression: ${BASELINE_REPORT:-<none>}"

SVC_URL=$(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks)
log_info "Load target: ${SVC_URL}"
~/java-on-aws/infra/scripts/test/benchmark.sh ${SVC_URL} 240 200

log_success "Regression load finished."

# ============================================================================
# SECTION 6: Reading the auto-generated report (on-alert chapter, final step)
# ============================================================================
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 6: Reading the auto-generated report"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Waiting for the webhook-triggered analysis report to land in Amazon S3..."

# The alert fires ~1-2 min into the load and the analyzer writes the report
# ~30-60s later, so a fresh report usually already exists. Poll for one newer
# than the pre-regression baseline (up to ~5 minutes).
LATEST=""
for i in {1..30}; do
  LATEST=$(aws s3 ls "s3://${S3_BUCKET}/${ANALYSIS_PREFIX}" --recursive --no-cli-pager 2>/dev/null \
    | grep analysis.md | sort | tail -1 | awk '{print $4}' || true)
  if [[ -n "${LATEST}" && "${LATEST}" != "${BASELINE_REPORT}" ]]; then
    log_success "New analysis report detected."
    break
  fi
  log_info "Waiting for the analysis report... ($i/30)"
  sleep 10
done

if [[ -z "${LATEST}" ]]; then
  log_warning "No analysis report found under s3://${S3_BUCKET}/${ANALYSIS_PREFIX} yet."
  log_warning "Check the analyzer logs: kubectl logs -n ${MON_NS} -l app=perf-analyzer --tail=80"
elif [[ "${LATEST}" == "${BASELINE_REPORT}" ]]; then
  log_warning "No report newer than the baseline appeared within the wait window."
  log_warning "The alert may not have fired yet; latest available report: ${LATEST}"
fi

if [[ -n "${LATEST}" ]]; then
  ANALYSIS_ID=$(echo "${LATEST}" | awk -F/ '{print $(NF-1)}')
  LOCAL_FILE=~/environment/incident-analysis-${ANALYSIS_ID}.md
  aws s3 cp "s3://${S3_BUCKET}/${LATEST}" "${LOCAL_FILE}" --no-cli-pager
  echo "📄 Local file: ${LOCAL_FILE}"
  echo "🔗 S3 console: https://${AWS_REGION}.console.aws.amazon.com/s3/buckets/${S3_BUCKET}?prefix=$(dirname ${LATEST})/"
  command -v code >/dev/null 2>&1 && code "${LOCAL_FILE}" || true
fi

log_success "Performance platform deployed, regression driven, report retrieved."
echo "✅ Success: perf-collector + perf-analyzer deployed, workload onboarded, ServiceLatency-eks rule created, regression driven (200 rps / 4 min), analysis report downloaded"
