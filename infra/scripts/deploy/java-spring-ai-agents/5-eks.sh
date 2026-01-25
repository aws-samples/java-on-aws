#!/bin/bash

# Deploy AI Agent to Amazon EKS
# Based on: java-spring-ai-agents/content/deploy/eks/index.en.md

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/aiagent
APP_NAME="aiagent"
NAMESPACE="aiagent"
CLUSTER_NAME="workshop-eks"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

log_info "Deploying AI Agent to Amazon EKS..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"
log_info "ECR URI: ${ECR_URI}"

# Verify application exists
if [[ ! -d "${APP_DIR}" ]]; then
    log_error "AI Agent application not found at ${APP_DIR}. Run 3-app.sh first."
    exit 1
fi

# ============================================================================
# Add Jib plugin and build container image
# ============================================================================
log_info "Adding Jib plugin to pom.xml..."
grep -q 'jib-maven-plugin' ~/environment/aiagent/pom.xml || \
sed -i '/<\/plugins>/i\
			<plugin>\
				<groupId>com.google.cloud.tools</groupId>\
				<artifactId>jib-maven-plugin</artifactId>\
				<version>3.5.1</version>\
				<configuration>\
					<from>\
						<image>public.ecr.aws/docker/library/amazoncorretto:25-alpine</image>\
					</from>\
					<container>\
						<user>1000</user>\
					</container>\
				</configuration>\
			</plugin>' ~/environment/aiagent/pom.xml
log_success "Jib plugin added"

log_info "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} \
  | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
log_success "ECR login successful"

log_info "Building and pushing container image with Jib..."
cd ~/environment/aiagent
mvn compile jib:build \
  -Dimage=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aiagent:latest \
  -DskipTests
log_success "Container image pushed"

# ============================================================================
# Create namespace and service account
# ============================================================================
log_info "Creating namespace ${NAMESPACE}..."
kubectl create namespace aiagent
log_success "Namespace created"

log_info "Creating service account ${APP_NAME}..."
kubectl create serviceaccount aiagent -n aiagent
log_success "Service account created"

# ============================================================================
# Configure Pod Identity
# ============================================================================
log_info "Creating Pod Identity association..."
aws eks create-pod-identity-association \
  --cluster-name workshop-eks \
  --namespace aiagent \
  --service-account aiagent \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/aiagent-eks-pod-role \
  --no-cli-pager

log_info "Verifying Pod Identity association..."
for i in {1..10}; do
    ASSOCIATION_ID=$(aws eks list-pod-identity-associations --cluster-name workshop-eks --no-cli-pager \
      | jq -r '.associations[] | select(.namespace=="aiagent") | .associationId')
    if [[ -n "${ASSOCIATION_ID}" ]]; then
        break
    fi
    log_info "Waiting for Pod Identity association to propagate... ($i/10)"
    sleep 2
done

if [[ -z "${ASSOCIATION_ID}" ]]; then
    log_error "Pod Identity association not found after waiting"
    exit 1
fi

aws eks describe-pod-identity-association \
  --cluster-name workshop-eks \
  --association-id ${ASSOCIATION_ID} \
  --no-cli-pager > /dev/null
log_success "Pod Identity association verified (ID: ${ASSOCIATION_ID})"

# ============================================================================
# Create Kubernetes manifests
# ============================================================================
log_info "Creating k8s directory..."
mkdir -p ~/environment/aiagent/k8s

# SecretProviderClass
log_info "Creating SecretProviderClass..."
cat <<EOF > ~/environment/aiagent/k8s/secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aiagent-secrets
  namespace: aiagent
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
kubectl apply -f ~/environment/aiagent/k8s/secret-provider-class.yaml
log_success "SecretProviderClass created"

# Get MCP URL and Cognito Issuer URI
log_info "Getting MCP Server URL and Cognito configuration..."
MCP_URL=http://$(kubectl get ingress mcpserver -n mcpserver \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "MCP URL: ${MCP_URL}"

USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text)
COGNITO_ISSUER_URI="https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}"
echo "Cognito Issuer URI: ${COGNITO_ISSUER_URI}"

# Deployment
log_info "Creating Deployment..."
ECR_URI=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aiagent
cat <<EOF > ~/environment/aiagent/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aiagent
  namespace: aiagent
  labels:
    app: aiagent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aiagent
  template:
    metadata:
      labels:
        app: aiagent
    spec:
      serviceAccountName: aiagent
      nodeSelector:
        karpenter.sh/nodepool: workshop
      containers:
        - name: aiagent
          image: ${ECR_URI}:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_CONFIG_IMPORT
              value: "optional:configtree:/mnt/secrets-store/"
            - name: SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL
              value: "${MCP_URL}"
            - name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI
              value: "${COGNITO_ISSUER_URI}"
          resources:
            requests:
              cpu: "1"
              memory: "2Gi"
            limits:
              cpu: "1"
              memory: "2Gi"
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            failureThreshold: 6
            periodSeconds: 5
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            failureThreshold: 6
            periodSeconds: 5
            initialDelaySeconds: 10
          startupProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            failureThreshold: 10
            periodSeconds: 5
            initialDelaySeconds: 20
          volumeMounts:
            - name: secrets-store
              mountPath: "/mnt/secrets-store"
              readOnly: true
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 10"]
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: aiagent-secrets
EOF
kubectl apply -f ~/environment/aiagent/k8s/deployment.yaml
log_success "Deployment created"

# Service
log_info "Creating Service..."
cat <<EOF > ~/environment/aiagent/k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: aiagent
  namespace: aiagent
  labels:
    app: aiagent
spec:
  type: ClusterIP
  selector:
    app: aiagent
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
EOF
kubectl apply -f ~/environment/aiagent/k8s/service.yaml
log_success "Service created"

# Ingress
log_info "Creating Ingress..."
cat <<EOF > ~/environment/aiagent/k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aiagent
  namespace: aiagent
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
  labels:
    app: aiagent
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: aiagent
                port:
                  number: 80
EOF
kubectl apply -f ~/environment/aiagent/k8s/ingress.yaml
log_success "Ingress created"

# ============================================================================
# Wait for deployment and test
# ============================================================================
log_info "Waiting for deployment to be ready..."
kubectl wait deployment aiagent -n aiagent \
  --for condition=Available=True --timeout=180s
kubectl get deployment aiagent -n aiagent
log_success "Deployment ready"

log_info "Waiting for ALB to be provisioned (this may take 2-5 minutes)..."
SVC_URL=http://$(kubectl get ingress aiagent -n aiagent \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

while ! curl -s --max-time 5 "${SVC_URL}/actuator/health" | grep -q '"status":"UP"'; do
  echo "Waiting for load balancer..." && sleep 15
done

log_success "EKS deployment completed"
echo "✅ Success: AI Agent deployed to EKS"
echo "URL: ${SVC_URL}"
echo "Username: alice"
echo "Password: ${IDE_PASSWORD}"
