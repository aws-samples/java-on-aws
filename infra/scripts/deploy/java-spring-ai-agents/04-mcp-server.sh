#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

print_prerequisites "kubectl, docker, Maven, EKS access, and predeployed mcpserver ECR/IAM/database resources"
init_context
require_state DB_PARAMETER_NAME DB_SECRET_ID
ensure_eks_context
require_workshop_role unicornstore-eks-pod-role
[[ -f "${MCPSERVER_DIR}/pom.xml" ]] || die "MCP source not found. Run 01-setup.sh first."

build_and_push_jib "${MCPSERVER_DIR}" mcpserver latest
IMAGE_DIGEST=$(aws_cli ecr describe-images --repository-name mcpserver --image-ids imageTag=latest \
  --query 'imageDetails[0].imageDigest' --output text)
IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mcpserver@${IMAGE_DIGEST}"
state_set MCP_IMAGE_URI "${IMAGE_URI}"

if kubectl get namespace mcpserver >/dev/null 2>&1; then
  [[ -n "${MCP_NAMESPACE_CREATED:-}" ]] || state_set MCP_NAMESPACE_CREATED false
else
  kubectl create namespace mcpserver
  state_set MCP_NAMESPACE_CREATED true
  kubectl label namespace mcpserver "app.kubernetes.io/managed-by=${SUITE_OWNER}" --overwrite
fi

if kubectl get serviceaccount mcpserver -n mcpserver >/dev/null 2>&1; then
  [[ -n "${MCP_SERVICE_ACCOUNT_CREATED:-}" ]] || state_set MCP_SERVICE_ACCOUNT_CREATED false
else
  kubectl create serviceaccount mcpserver -n mcpserver
  state_set MCP_SERVICE_ACCOUNT_CREATED true
  kubectl label serviceaccount mcpserver -n mcpserver "app.kubernetes.io/managed-by=${SUITE_OWNER}" --overwrite
fi

upsert_pod_identity mcpserver mcpserver "arn:aws:iam::${ACCOUNT_ID}:role/unicornstore-eks-pod-role" MCP
mkdir -p "${MCPSERVER_DIR}/k8s"
backup_k8s_resource mcpserver secretproviderclass mcpserver-secrets MCP_SPC_BACKUP_PATH
backup_k8s_resource mcpserver deployment mcpserver MCP_DEPLOYMENT_BACKUP_PATH
backup_k8s_resource mcpserver service mcpserver MCP_SERVICE_BACKUP_PATH
backup_k8s_resource mcpserver ingress mcpserver MCP_INGRESS_BACKUP_PATH
cat > "${MCPSERVER_DIR}/k8s/secret-provider-class.yaml" <<'EOF'
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: mcpserver-secrets
  namespace: mcpserver
  labels:
    app.kubernetes.io/managed-by: java-spring-ai-agents-suite
spec:
  provider: aws
  parameters:
    usePodIdentity: "true"
    objects: |
      - objectName: "workshop-db-secret"
        objectType: "secretsmanager"
        jmesPath:
          - path: "password"
            objectAlias: "spring.datasource.password"
          - path: "username"
            objectAlias: "spring.datasource.username"
      - objectName: "workshop-db-connection-string"
        objectType: "ssmparameter"
        objectAlias: "spring.datasource.url"
EOF
cat > "${MCPSERVER_DIR}/k8s/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcpserver
  namespace: mcpserver
  labels: {app: mcpserver, app.kubernetes.io/managed-by: ${SUITE_OWNER}}
spec:
  replicas: 1
  selector: {matchLabels: {app: mcpserver}}
  template:
    metadata: {labels: {app: mcpserver, app.kubernetes.io/managed-by: ${SUITE_OWNER}}}
    spec:
      serviceAccountName: mcpserver
      nodeSelector: {karpenter.sh/nodepool: workshop}
      containers:
        - name: mcpserver
          image: ${IMAGE_URI}
          imagePullPolicy: IfNotPresent
          ports: [{containerPort: 8080}]
          env:
            - name: SPRING_CONFIG_IMPORT
              value: "optional:configtree:/mnt/secrets-store/"
          resources:
            requests: {cpu: "1", memory: 2Gi}
            limits: {cpu: "1", memory: 2Gi}
          startupProbe: {httpGet: {path: /actuator/health/liveness, port: 8080}, failureThreshold: 20, periodSeconds: 5}
          livenessProbe: {httpGet: {path: /actuator/health/liveness, port: 8080}, failureThreshold: 6, periodSeconds: 5}
          readinessProbe: {httpGet: {path: /actuator/health/readiness, port: 8080}, failureThreshold: 6, periodSeconds: 5, initialDelaySeconds: 10}
          volumeMounts: [{name: secrets-store, mountPath: /mnt/secrets-store, readOnly: true}]
          securityContext: {runAsNonRoot: true, runAsUser: 1000, allowPrivilegeEscalation: false}
          lifecycle: {preStop: {exec: {command: ["sh", "-c", "sleep 10"]}}}
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes: {secretProviderClass: mcpserver-secrets}
EOF
cat > "${MCPSERVER_DIR}/k8s/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mcpserver
  namespace: mcpserver
  labels: {app: mcpserver, app.kubernetes.io/managed-by: ${SUITE_OWNER}}
spec:
  type: ClusterIP
  selector: {app: mcpserver}
  ports: [{port: 80, targetPort: 8080, protocol: TCP}]
EOF
cat > "${MCPSERVER_DIR}/k8s/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mcpserver
  namespace: mcpserver
  labels: {app: mcpserver, app.kubernetes.io/managed-by: ${SUITE_OWNER}}
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: mcpserver, port: {number: 80}}}
EOF
kubectl apply -f "${MCPSERVER_DIR}/k8s/secret-provider-class.yaml"
kubectl apply -f "${MCPSERVER_DIR}/k8s/deployment.yaml"
kubectl apply -f "${MCPSERVER_DIR}/k8s/service.yaml"
kubectl apply -f "${MCPSERVER_DIR}/k8s/ingress.yaml"
kubectl rollout status deployment/mcpserver -n mcpserver --timeout=300s

wait_for_ingress_hostname "MCP ingress hostname" mcpserver mcpserver 40 15
MCP_URL="http://${INGRESS_HOST}"
wait_for_dns "MCP ingress" "${INGRESS_HOST}" 30 10
wait_for_http_status "MCP server HTTP readiness" "${MCP_URL}/actuator/health" '^(200)$' 30 10
state_set MCP_URL "${MCP_URL}"

SAMPLE_NAME="suite-unicorn-classic-small"
body=$(mktemp)
trap 'rm -f "${body}"' EXIT
status=$(curl -sS -o "${body}" -w '%{http_code}' --connect-timeout 10 --max-time 30 "${MCP_URL}/unicorns")
[[ "${status}" == "200" || "${status}" == "204" ]] || die "Could not list Unicorns: HTTP ${status}"
SAMPLE_ID=""
if [[ "${status}" == "200" && -s "${body}" ]]; then
  SAMPLE_ID=$(jq -r --arg name "${SAMPLE_NAME}" '.[] | select(.name == $name) | .id' "${body}" | head -n 1)
fi
if [[ -z "${SAMPLE_ID}" ]]; then
  response=$(curl --fail-with-body -sS --connect-timeout 10 --max-time 30 -X POST "${MCP_URL}/unicorns" \
    -H 'Content-Type: application/json' \
    -d '{"name":"suite-unicorn-classic-small","age":"10","type":"classic","size":"small"}')
  SAMPLE_ID=$(jq -r '.id' <<<"${response}")
  [[ -n "${SAMPLE_ID}" && "${SAMPLE_ID}" != "null" ]] || die "MCP sample creation returned no ID"
  state_set MCP_SAMPLE_CREATED true
else
  [[ -n "${MCP_SAMPLE_CREATED:-}" ]] || state_set MCP_SAMPLE_CREATED false
fi
state_set MCP_SAMPLE_ID "${SAMPLE_ID}"
state_set MCP_SAMPLE_NAME "${SAMPLE_NAME}"
log "MCP server reconciled at ${MCP_URL}; deterministic sample ID: ${SAMPLE_ID}"
