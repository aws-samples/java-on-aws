#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_suite-lib.sh
source "${SCRIPT_DIR}/_suite-lib.sh"

print_prerequisites "kubectl, docker, Maven, and the shared 02-05 stages"
init_context
load_state
require_state MCP_URL COGNITO_ISSUER_URI DB_PARAMETER_NAME DB_SECRET_ID
ensure_eks_context
require_workshop_role aiagent-eks-pod-role
[[ -f "${AIAGENT_DIR}/pom.xml" ]] || die "AI-agent source not found. Run 01-setup.sh first."

build_and_push_jib "${AIAGENT_DIR}" aiagent alternative
IMAGE_DIGEST=$(aws_cli ecr describe-images --repository-name aiagent --image-ids imageTag=alternative \
  --query 'imageDetails[0].imageDigest' --output text)
IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aiagent@${IMAGE_DIGEST}"
state_set EKS_IMAGE_URI "${IMAGE_URI}"

if kubectl get namespace aiagent >/dev/null 2>&1; then
  [[ -n "${EKS_NAMESPACE_CREATED:-}" ]] || state_set EKS_NAMESPACE_CREATED false
else
  kubectl create namespace aiagent
  state_set EKS_NAMESPACE_CREATED true
  kubectl label namespace aiagent "app.kubernetes.io/managed-by=${SUITE_OWNER}" --overwrite
fi
if kubectl get serviceaccount aiagent -n aiagent >/dev/null 2>&1; then
  [[ -n "${EKS_SERVICE_ACCOUNT_CREATED:-}" ]] || state_set EKS_SERVICE_ACCOUNT_CREATED false
else
  kubectl create serviceaccount aiagent -n aiagent
  state_set EKS_SERVICE_ACCOUNT_CREATED true
  kubectl label serviceaccount aiagent -n aiagent "app.kubernetes.io/managed-by=${SUITE_OWNER}" --overwrite
fi
upsert_pod_identity aiagent aiagent "arn:aws:iam::${ACCOUNT_ID}:role/aiagent-eks-pod-role" EKS

mkdir -p "${AIAGENT_DIR}/k8s"
backup_k8s_resource aiagent secretproviderclass aiagent-secrets EKS_SPC_BACKUP_PATH
backup_k8s_resource aiagent deployment aiagent EKS_DEPLOYMENT_BACKUP_PATH
backup_k8s_resource aiagent service aiagent EKS_SERVICE_BACKUP_PATH
backup_k8s_resource aiagent ingress aiagent EKS_INGRESS_BACKUP_PATH
cat > "${AIAGENT_DIR}/k8s/secret-provider-class.yaml" <<'EOF'
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aiagent-secrets
  namespace: aiagent
  labels: {app.kubernetes.io/managed-by: java-spring-ai-agents-suite}
spec:
  provider: aws
  parameters:
    usePodIdentity: "true"
    objects: |
      - objectName: "workshop-db-secret"
        objectType: "secretsmanager"
        jmesPath:
          - {path: "password", objectAlias: "spring.datasource.password"}
          - {path: "username", objectAlias: "spring.datasource.username"}
      - objectName: "workshop-db-connection-string"
        objectType: "ssmparameter"
        objectAlias: "spring.datasource.url"
EOF
cat > "${AIAGENT_DIR}/k8s/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aiagent
  namespace: aiagent
  labels: {app: aiagent, app.kubernetes.io/managed-by: ${SUITE_OWNER}}
spec:
  replicas: 1
  selector: {matchLabels: {app: aiagent}}
  template:
    metadata: {labels: {app: aiagent, app.kubernetes.io/managed-by: ${SUITE_OWNER}}}
    spec:
      serviceAccountName: aiagent
      nodeSelector: {karpenter.sh/nodepool: workshop}
      containers:
        - name: aiagent
          image: ${IMAGE_URI}
          imagePullPolicy: IfNotPresent
          ports: [{containerPort: 8080}]
          env:
            - {name: SPRING_CONFIG_IMPORT, value: "optional:configtree:/mnt/secrets-store/"}
            - {name: SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL, value: "${MCP_URL}"}
            - {name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI, value: "${COGNITO_ISSUER_URI}"}
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
          csi: {driver: secrets-store.csi.k8s.io, readOnly: true, volumeAttributes: {secretProviderClass: aiagent-secrets}}
EOF
cat > "${AIAGENT_DIR}/k8s/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: aiagent
  namespace: aiagent
  labels: {app: aiagent, app.kubernetes.io/managed-by: ${SUITE_OWNER}}
spec:
  type: ClusterIP
  selector: {app: aiagent}
  ports: [{port: 80, targetPort: 8080, protocol: TCP}]
EOF
cat > "${AIAGENT_DIR}/k8s/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aiagent
  namespace: aiagent
  labels: {app: aiagent, app.kubernetes.io/managed-by: ${SUITE_OWNER}}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: aiagent, port: {number: 80}}}
EOF
kubectl apply -f "${AIAGENT_DIR}/k8s/secret-provider-class.yaml"
kubectl apply -f "${AIAGENT_DIR}/k8s/deployment.yaml"
kubectl apply -f "${AIAGENT_DIR}/k8s/service.yaml"
kubectl apply -f "${AIAGENT_DIR}/k8s/ingress.yaml"
kubectl rollout status deployment/aiagent -n aiagent --timeout=300s

host=""
for i in {1..40}; do
  host=$(kubectl get ingress aiagent -n aiagent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "${host}" ]] && break
  log "Waiting for AI-agent ingress hostname (${i}/40)"
  ((i == 40)) || sleep 15
done
[[ -n "${host}" ]] || die "AI-agent ingress did not receive a hostname"
AIAGENT_ENDPOINT="http://${host}"
wait_for_http_status "EKS AI-agent health" "${AIAGENT_ENDPOINT}/actuator/health" '^(200)$' 30 10
state_set ACTIVE_TARGET eks
state_set AIAGENT_ENDPOINT "${AIAGENT_ENDPOINT}"
log "AI agent reconciled on EKS: ${AIAGENT_ENDPOINT}"
