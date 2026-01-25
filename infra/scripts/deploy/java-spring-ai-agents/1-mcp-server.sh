#!/bin/bash

# MCP Server - Add MCP server capabilities to Unicorn Store Spring and deploy to EKS
# Based on: java-spring-ai-agents/content/mcp/mcp-server/index.en.md
#           java-spring-ai-agents/content/deploy-mcp-server/index.en.md

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/mcpserver
APP_NAME="mcpserver"
NAMESPACE="mcpserver"
CLUSTER_NAME="workshop-eks"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

log_info "Setting up MCP Server for Unicorn Store Spring..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"
log_info "ECR URI: ${ECR_URI}"

# Copy the application
log_info "Copying Unicorn Store application sources..."
mkdir -p ~/environment/mcpserver
rsync -aq ~/java-on-aws/apps/unicorn-store-spring/ ~/environment/mcpserver \
  --exclude target --exclude src/test

cd ~/environment/mcpserver
git init -b main
echo "target" >> .gitignore
echo "*.jar" >> .gitignore
git add .
git commit -q -m "initial commit"
log_success "Application copied and initialized"

# Update configuration
log_info "Adding MCP server configuration to application.yaml..."
yq -i '.spring.ai.mcp.server.name = "unicorn-store-spring" |
  .spring.ai.mcp.server.version = "1.0.0" |
  .spring.ai.mcp.server.protocol = "STREAMABLE" |
  .logging.level."org.springframework.ai" = "DEBUG"' \
  ~/environment/mcpserver/src/main/resources/application.yaml
log_success "Configuration updated"

# Add Spring AI BOM to dependencyManagement
log_info "Adding Spring AI BOM to pom.xml..."
sed -i '/<dependencyManagement>/,/<\/dependencyManagement>/ {
    /<dependencies>/a\
            <dependency>\
                <groupId>org.springframework.ai</groupId>\
                <artifactId>spring-ai-bom</artifactId>\
                <version>1.1.2</version>\
                <type>pom</type>\
                <scope>import</scope>\
            </dependency>
}' ~/environment/mcpserver/pom.xml
log_success "Spring AI BOM added"

# Add MCP server starter dependency
log_info "Adding MCP server starter dependency..."
sed -i '/<!-- Spring Boot starters -->/i\
        <dependency>\
            <groupId>org.springframework.ai</groupId>\
            <artifactId>spring-ai-starter-mcp-server-webmvc</artifactId>\
        </dependency>
' ~/environment/mcpserver/pom.xml
log_success "MCP server starter added"

# Create UnicornTools.java
log_info "Creating UnicornTools.java..."
cat <<'EOF' > ~/environment/mcpserver/src/main/java/com/unicorn/store/service/UnicornTools.java
package com.unicorn.store.service;

import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Component;
import java.util.List;
import com.unicorn.store.model.Unicorn;

@Component
public class UnicornTools {
    private final UnicornService unicornService;

    public UnicornTools(UnicornService unicornService) {
        this.unicornService = unicornService;
    }

    @Bean
    public ToolCallbackProvider unicornToolsProvider(UnicornTools unicornTools) {
        return MethodToolCallbackProvider.builder()
                .toolObjects(unicornTools)
                .build();
    }

    @Tool(description = "Create a new unicorn in the unicorn store.")
    public Unicorn createUnicorn(Unicorn unicorn) {
        return unicornService.createUnicorn(unicorn);
    }

    @Tool(description = "Get a list of all unicorns in the unicorn store")
    public List<Unicorn> getAllUnicorns(String... parameters) {
        return unicornService.getAllUnicorns();
    }
}
EOF
log_success "UnicornTools.java created"

# Commit changes
log_info "Committing changes..."
cd ~/environment/mcpserver
git add .
git commit -m "Add MCP server"
log_success "Changes committed"

# ============================================================================
# Deploy to Amazon EKS
# Based on: java-spring-ai-agents/content/deploy-mcp-server/index.en.md
# ============================================================================

# Build and push container image using Jib
log_info "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} \
  | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
log_success "ECR login successful"

log_info "Building and pushing container image with Jib..."
cd ~/environment/mcpserver
mvn compile jib:build \
  -Dimage=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mcpserver:latest \
  -DskipTests
log_success "Container image pushed"

# Create namespace
log_info "Creating namespace ${NAMESPACE}..."
kubectl create namespace mcpserver
log_success "Namespace created"

# Create service account
log_info "Creating service account ${APP_NAME}..."
kubectl create serviceaccount mcpserver -n mcpserver
log_success "Service account created"

# Create Pod Identity association
log_info "Creating Pod Identity association..."
aws eks create-pod-identity-association \
  --cluster-name workshop-eks \
  --namespace mcpserver \
  --service-account mcpserver \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/unicornstore-eks-pod-role \
  --no-cli-pager

# Verify Pod Identity association
log_info "Verifying Pod Identity association..."
for i in {1..10}; do
    ASSOCIATION_ID=$(aws eks list-pod-identity-associations --cluster-name workshop-eks --no-cli-pager \
      | jq -r '.associations[] | select(.namespace=="mcpserver") | .associationId')
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

# Create k8s directory
log_info "Creating k8s directory..."
mkdir -p ~/environment/mcpserver/k8s

# Create and apply SecretProviderClass
log_info "Creating SecretProviderClass..."
cat <<EOF > ~/environment/mcpserver/k8s/secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: mcpserver-secrets
  namespace: mcpserver
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
kubectl apply -f ~/environment/mcpserver/k8s/secret-provider-class.yaml
log_success "SecretProviderClass created"

# Create and apply Deployment
log_info "Creating Deployment..."
ECR_URI=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mcpserver
cat <<EOF > ~/environment/mcpserver/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcpserver
  namespace: mcpserver
  labels:
    app: mcpserver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mcpserver
  template:
    metadata:
      labels:
        app: mcpserver
    spec:
      serviceAccountName: mcpserver
      nodeSelector:
        karpenter.sh/nodepool: workshop
      containers:
        - name: mcpserver
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
              secretProviderClass: mcpserver-secrets
EOF
kubectl apply -f ~/environment/mcpserver/k8s/deployment.yaml
log_success "Deployment created"

# Create and apply Service
log_info "Creating Service..."
cat <<EOF > ~/environment/mcpserver/k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: mcpserver
  namespace: mcpserver
  labels:
    app: mcpserver
spec:
  type: ClusterIP
  selector:
    app: mcpserver
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
EOF
kubectl apply -f ~/environment/mcpserver/k8s/service.yaml
log_success "Service created"

# Create and apply Ingress (VPC-internal)
log_info "Creating Ingress (internal ALB)..."
cat <<EOF > ~/environment/mcpserver/k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mcpserver
  namespace: mcpserver
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
  labels:
    app: mcpserver
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mcpserver
                port:
                  number: 80
EOF
kubectl apply -f ~/environment/mcpserver/k8s/ingress.yaml
log_success "Ingress created"

# Wait for deployment
log_info "Waiting for deployment to be ready..."
kubectl wait deployment mcpserver -n mcpserver --for condition=Available=True --timeout=180s
kubectl get deployment mcpserver -n mcpserver
log_success "Deployment ready"

# Wait for ALB and test
log_info "Waiting for internal ALB to be provisioned (this may take 2-5 minutes)..."
MCP_URL=http://$(kubectl get ingress mcpserver -n mcpserver \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

while ! curl -s --max-time 5 ${MCP_URL} > /dev/null 2>&1; do
  echo "Waiting for load balancer..." && sleep 15
done

log_success "MCP Server URL: ${MCP_URL}"

# Test the MCP server
log_info "Testing MCP Server..."
curl -s ${MCP_URL}; echo

log_info "Creating test unicorn..."
curl -X POST ${MCP_URL}/unicorns \
  -H "Content-Type: application/json" \
  -d '{"name": "rainbow", "age": "5", "type": "classic", "size": "medium"}'; echo
log_success "MCP Server test completed"

# Commit k8s manifests
log_info "Committing k8s manifests..."
cd ~/environment/mcpserver
git add .
git commit -m "Add k8s manifests"
log_success "Changes committed"

log_success "MCP Server deployment completed"
echo "✅ Success: MCP Server deployed to EKS (URL: ${MCP_URL})"
