#!/bin/bash
# eks-agent-setup.sh - Script to set up EKS deployment, service, and ingress

set -e

echo "Setting up EKS resources for Spring AI Agent..."

# Check if namespace exists, exit if it doesn't
if ! kubectl get namespace unicorn-spring-ai-agent &>/dev/null; then
  echo "Error: Namespace 'unicorn-spring-ai-agent' does not exist. Please create it first."
  exit 1
fi

# Get MCP Server URL - continue with placeholder if not found
echo "Getting MCP Server URL..."
if ! MCP_URL=$(kubectl get ingress unicorn-store-spring -n unicorn-store-spring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); then
  echo "Warning: Could not get MCP URL. Using placeholder value."
  MCP_URL="http://placeholder-mcp-url.example.com"
else
  MCP_URL="http://$MCP_URL"
  echo "MCP URL: $MCP_URL"
fi

# Get ECR URI - exit if not found
echo "Getting ECR URI..."
if ! ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-spring-ai-agent | jq --raw-output '.repositories[0].repositoryUri' 2>/dev/null); then
  echo "Error: Could not get ECR URI. Repository 'unicorn-spring-ai-agent' may not exist. Exiting."
  exit 1
else
  echo "ECR URI: $ECR_URI"
fi

# Get database connection string
echo "Getting database connection string..."
if ! SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name unicornstore-db-connection-string | jq --raw-output '.Parameter.Value' 2>/dev/null); then
  echo "Warning: Could not get database connection string. Using placeholder value."
  SPRING_DATASOURCE_URL="jdbc:postgresql://placeholder-db-url:5432/unicornstore"
else
  echo "Database connection string retrieved successfully."
fi

# Create directory for Kubernetes manifests
echo "Creating directory for Kubernetes manifests..."
mkdir -p ~/environment/unicorn-spring-ai-agent/k8s

# Create deployment manifest
echo "Creating deployment manifest..."
cat <<EOF > ~/environment/unicorn-spring-ai-agent/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unicorn-spring-ai-agent
  namespace: unicorn-spring-ai-agent
  labels:
    project: unicorn-store
    app: unicorn-spring-ai-agent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: unicorn-spring-ai-agent
  template:
    metadata:
      labels:
        app: unicorn-spring-ai-agent
    spec:
      nodeSelector:
        karpenter.sh/nodepool: dedicated
      serviceAccountName: unicorn-spring-ai-agent
      containers:
        - name: unicorn-spring-ai-agent
          resources:
            requests:
              cpu: "1"
              memory: "2Gi"
          image: ${ECR_URI}:latest
          imagePullPolicy: Always
          env:
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "unicornstore-db-secret"
                  key: "password"
                  optional: false
            - name: SPRING_DATASOURCE_URL
              value: ${SPRING_DATASOURCE_URL}
            - name: SPRING_AI_MCP_CLIENT_SSE_CONNECTIONS_SERVER1_URL
              value: ${MCP_URL}
          ports:
            - containerPort: 8080
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
              path: /
              port: 8080
            failureThreshold: 6
            periodSeconds: 5
            initialDelaySeconds: 10
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 10"]
          securityContext:
            # runAsNonRoot: true
            allowPrivilegeEscalation: false
EOF
kubectl apply -f ~/environment/unicorn-spring-ai-agent/k8s/deployment.yaml

# Create service manifest
echo "Creating service manifest..."
cat <<EOF > ~/environment/unicorn-spring-ai-agent/k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: unicorn-spring-ai-agent
  namespace: unicorn-spring-ai-agent
  labels:
    project: unicorn-store
    app: unicorn-spring-ai-agent
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: unicorn-spring-ai-agent
EOF
kubectl apply -f ~/environment/unicorn-spring-ai-agent/k8s/service.yaml

# Create ingress manifest
echo "Creating ingress manifest..."
cat <<EOF > ~/environment/unicorn-spring-ai-agent/k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: unicorn-spring-ai-agent
  namespace: unicorn-spring-ai-agent
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=3600
  labels:
    project: unicorn-store
    app: unicorn-spring-ai-agent
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: unicorn-spring-ai-agent
                port:
                  number: 80
EOF
kubectl apply -f ~/environment/unicorn-spring-ai-agent/k8s/ingress.yaml

# Checking the application status ...
kubectl wait deployment unicorn-spring-ai-agent -n unicorn-spring-ai-agent --for condition=Available=True --timeout=120s
kubectl get deployment unicorn-spring-ai-agent -n unicorn-spring-ai-agent
SVC_URL=http://$(kubectl get ingress unicorn-spring-ai-agent -n unicorn-spring-ai-agent -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 5; done
echo $SVC_URL
echo Service is Ready!
