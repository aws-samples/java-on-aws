#!/usr/bin/env bash
# ============================================================================
# deploy-optimizer.sh — build + deploy perf-optimizer (MCP optimization agent)
# Run on the amd64 "ide" instance (has Maven/Docker + instance role for ECR/EKS).
# Fetches the module from S3, jib-builds to ECR, deploys to the monitoring ns
# reusing the perf-analyzer ServiceAccount (Bedrock + S3 perms), and prints how
# to connect Claude Code over MCP/SSE.
# ============================================================================
set -uo pipefail
REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
REPO=${ECR_BASE}/perf-optimizer
NS=monitoring
BUCKET=$(aws ssm get-parameter --name workshop-bucket-name --query Parameter.Value --output text)
KB_ID=$(aws ssm get-parameter --name /perf-optimizer/kb-id --query Parameter.Value --output text 2>/dev/null || echo "")

WORK=$HOME/perf-optimizer-src; rm -rf "$WORK"; mkdir -p "$WORK"
echo "== fetch module from S3 =="
aws s3 cp "s3://${BUCKET}/perf-scenario/perf-optimizer.tgz" "$WORK/src.tgz"
tar -xzf "$WORK/src.tgz" -C "$WORK"
cd "$WORK/perf-optimizer" || { echo "module dir missing"; exit 1; }

echo "== build + push image (jib) =="
aws ecr describe-repositories --repository-names perf-optimizer >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name perf-optimizer >/dev/null
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_BASE"
mvn -q clean compile jib:build -Dimage="${REPO}:latest" || { echo "BUILD FAILED"; exit 1; }

echo "== deploy to $NS =="
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
      serviceAccountName: perf-analyzer   # reuse: has Bedrock + S3 perms
      containers:
      - name: perf-optimizer
        image: ${REPO}:latest
        ports: [{containerPort: 8080}]
        env:
        - {name: AWS_REGION, value: "${REGION}"}
        - {name: PYROSCOPE_URL, value: "http://pyroscope.monitoring:4040"}
        - {name: SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MODEL, value: "global.anthropic.claude-sonnet-4-6"}
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

if [ -n "$KB_ID" ] && [ "$KB_ID" != "None" ]; then
  kubectl -n "$NS" set env deployment/perf-optimizer \
    SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID="$KB_ID" >/dev/null
  echo "Managed Bedrock KB grounding wired (KB $KB_ID). Bundled kb/*.md remains as fallback."
else
  echo "No /perf-optimizer/kb-id in SSM — grounding on bundled kb/*.md. Run kb-optimizer.sh (after granting perms) to enable the managed KB."
fi

# Force a fresh pull of the just-built :latest (apply alone is a no-op if the
# image string is unchanged).
kubectl -n "$NS" rollout restart deploy/perf-optimizer >/dev/null 2>&1 || true
kubectl -n "$NS" rollout status deploy/perf-optimizer --timeout=200s || {
  echo "rollout not ready; logs:"; kubectl -n "$NS" logs -l app=perf-optimizer --tail=60; exit 1; }

echo
echo "== perf-optimizer is up =="
echo "Connect Claude Code (this instance) over MCP/SSE:"
echo "  kubectl -n ${NS} port-forward svc/perf-optimizer 8080:8080 &"
echo "  claude mcp add --transport sse perf-optimizer http://localhost:8080/sse"
echo "Then ask Claude Code:  \"use perf-optimizer to optimize unicorn-store-spring-eks\""
echo "(If the SSE path differs on Spring AI 2.0, check startup logs for the MCP endpoint.)"
