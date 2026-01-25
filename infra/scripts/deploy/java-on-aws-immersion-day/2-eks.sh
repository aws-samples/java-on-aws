#!/bin/bash

# Deploy to Amazon EKS - Create namespace, service account, Pod Identity, secrets, and deploy app
# Based on: java-on-amazon-eks/content/deploy-containers/deploy-to-eks/index.en.md

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/unicorn-store-spring
APP_NAME="unicorn-store-spring"
NAMESPACE="unicorn-store-spring"
CLUSTER_NAME="workshop-eks"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

log_info "Deploying Unicorn Store Spring to Amazon EKS..."
log_info "AWS Account: $ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"
log_info "EKS Cluster: $CLUSTER_NAME"

# Create namespace
log_info "Creating namespace ${NAMESPACE}..."
kubectl create namespace unicorn-store-spring
log_success "Namespace created"

# Create service account
log_info "Creating service account ${APP_NAME}..."
kubectl create serviceaccount unicorn-store-spring -n unicorn-store-spring
log_success "Service account created"

# Create Pod Identity association
log_info "Creating Pod Identity association..."
aws eks create-pod-identity-association \
  --cluster-name workshop-eks \
  --namespace unicorn-store-spring \
  --service-account unicorn-store-spring \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/unicornstore-eks-pod-role \
  --no-cli-pager

# Verify Pod Identity association is ready
log_info "Verifying Pod Identity association..."
ASSOCIATION_ID=""
for i in {1..10}; do
    ASSOCIATION_ID=$(aws eks list-pod-identity-associations --cluster-name workshop-eks --no-cli-pager \
      | jq -r '.associations[] | select(.namespace=="unicorn-store-spring" and .serviceAccount=="unicorn-store-spring") | .associationId')
    if [[ -n "$ASSOCIATION_ID" ]]; then
        break
    fi
    log_info "Waiting for Pod Identity association to propagate... ($i/10)"
    sleep 2
done

if [[ -z "$ASSOCIATION_ID" ]]; then
    log_error "Pod Identity association not found after waiting"
    exit 1
fi

aws eks describe-pod-identity-association \
  --cluster-name workshop-eks \
  --association-id ${ASSOCIATION_ID} \
  --no-cli-pager > /dev/null
log_success "Pod Identity association verified (ID: ${ASSOCIATION_ID})"

# Create k8s directory
log_info "Creating k8s directory..."
mkdir -p ~/environment/unicorn-store-spring/k8s

# Create and apply SecretProviderClass
log_info "Creating SecretProviderClass..."
cat <<EOF > ~/environment/unicorn-store-spring/k8s/secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: unicorn-store-secrets
  namespace: unicorn-store-spring
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
kubectl apply -f ~/environment/unicorn-store-spring/k8s/secret-provider-class.yaml

# Verify SecretProviderClass is registered
log_info "Verifying SecretProviderClass..."
kubectl get secretproviderclass unicorn-store-secrets -n unicorn-store-spring > /dev/null
log_success "SecretProviderClass created and verified"

# Create and apply Deployment
log_info "Creating Deployment..."
ECR_URI=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/unicorn-store-spring
cat <<EOF > ~/environment/unicorn-store-spring/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
  labels:
    app: unicorn-store-spring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: unicorn-store-spring
  template:
    metadata:
      labels:
        app: unicorn-store-spring
    spec:
      serviceAccountName: unicorn-store-spring
      nodeSelector:
        karpenter.sh/nodepool: workshop
      containers:
        - name: unicorn-store-spring
          image: ${ECR_URI}:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_CONFIG_IMPORT
              value: "optional:configtree:/mnt/secrets-store/"
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
              secretProviderClass: unicorn-store-secrets
EOF
kubectl apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
log_success "Deployment created"

# Create and apply Service
log_info "Creating Service..."
cat <<EOF > ~/environment/unicorn-store-spring/k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
  labels:
    app: unicorn-store-spring
spec:
  type: ClusterIP
  selector:
    app: unicorn-store-spring
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
EOF
kubectl apply -f ~/environment/unicorn-store-spring/k8s/service.yaml
log_success "Service created"

# Create and apply Ingress
log_info "Creating Ingress..."
cat <<EOF > ~/environment/unicorn-store-spring/k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
  labels:
    app: unicorn-store-spring
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: unicorn-store-spring
                port:
                  number: 80
EOF
kubectl apply -f ~/environment/unicorn-store-spring/k8s/ingress.yaml
log_success "Ingress created"

# Wait for deployment
log_info "Waiting for deployment to be ready..."
kubectl wait deployment unicorn-store-spring -n unicorn-store-spring --for condition=Available=True --timeout=180s
kubectl get deployment unicorn-store-spring -n unicorn-store-spring
log_success "Deployment ready"

# Check pod status
log_info "Checking pod status..."
kubectl get pods -n unicorn-store-spring

# Wait for ALB and test
log_info "Waiting for ALB to be provisioned (this may take 2-5 minutes)..."
SVC_URL=http://$(kubectl get ingress unicorn-store-spring -n unicorn-store-spring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
while [[ $(curl -s -o /dev/null -w "%{http_code}" ${SVC_URL}/) != "200" ]]; do
  echo "Service not yet available ..." && sleep 15
done
echo "Service available."
echo ${SVC_URL}
curl -s ${SVC_URL} && echo

log_success "EKS deployment completed"
echo "✅ Success: Deployed to EKS (URL: ${SVC_URL})"
