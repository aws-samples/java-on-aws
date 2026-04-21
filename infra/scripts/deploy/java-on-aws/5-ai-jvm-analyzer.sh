#!/bin/bash

# AI JVM Analyzer - Deploy continuous profiling and AI-powered analysis
# Based on: java-on-aws-immersion-day/content/analysis/ai-jvm-analyzer/
# Covers: Continuous profiling, AI JVM Analyzer deployment, up to Grafana credentials retrieval
#
# Prerequisites: 1-containerize.sh and 2-eks.sh must be run first

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/unicorn-store-spring
APP_NAME="unicorn-store-spring"
NAMESPACE="unicorn-store-spring"
CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"

log_info "Setting up AI JVM Analyzer with continuous profiling..."
log_info "AWS Account: $ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"
log_info "EKS Cluster: $CLUSTER_NAME"

# ============================================================================
# SECTION 1: Continuous Profiling - Change source code
# ============================================================================

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 1: Continuous Profiling Setup"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$APP_DIR"

# Update application version identifier (idempotent - sed is safe to re-run)
log_info "Updating application version identifier..."
sed -i 's/Welcome to the Unicorn Store.*/Welcome to the Unicorn Store - Profiling!");/' \
  src/main/java/com/unicorn/store/controller/UnicornController.java
log_success "Application version updated"

# ============================================================================
# SECTION 2: Create Dockerfile with async-profiler
# ============================================================================

log_info "Creating Dockerfile with async-profiler..."
cat <<'EOF' > ~/environment/unicorn-store-spring/Dockerfile
FROM public.ecr.aws/docker/library/maven:3-amazoncorretto-25-al2023 AS builder

RUN yum install -y wget tar gzip

RUN cd /tmp && \
    wget -q https://github.com/async-profiler/async-profiler/releases/download/v4.3/async-profiler-4.3-linux-x64.tar.gz && \
    mkdir /async-profiler && \
    tar -xzf ./async-profiler-4.3-linux-x64.tar.gz -C /async-profiler --strip-components=1

COPY ./pom.xml ./pom.xml
COPY src ./src/

RUN mvn clean package -DskipTests -ntp && mv target/store-spring-1.0.0-exec.jar store-spring.jar

FROM public.ecr.aws/docker/library/amazoncorretto:25-al2023

RUN yum install -y shadow-utils

COPY --from=builder /async-profiler/ /async-profiler/
COPY --from=builder store-spring.jar store-spring.jar

RUN groupadd --system spring -g 1000
RUN adduser spring -u 1000 -g 1000

USER 1000:1000
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "-Dserver.port=8080", "/store-spring.jar"]
EOF
log_success "Created Dockerfile with async-profiler"

# ============================================================================
# SECTION 3: Build and push container image
# ============================================================================

log_info "Building container image with async-profiler..."
cd ~/environment/unicorn-store-spring

aws ecr get-login-password --region ${AWS_REGION} \
  | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

docker build -t unicorn-store-spring:latest .
log_success "Docker image built"

log_info "Tagging and pushing images..."
docker tag unicorn-store-spring:latest ${ECR_URI}:11-profiling
docker tag unicorn-store-spring:latest ${ECR_URI}:latest
docker push ${ECR_URI}:11-profiling
docker push ${ECR_URI}:latest
log_success "Pushed ${ECR_URI}:11-profiling and :latest"

# ============================================================================
# SECTION 4: Set up S3 storage for profiling data
# ============================================================================

log_info "Setting up S3 storage for profiling data..."
S3_BUCKET=$(aws ssm get-parameter --name workshop-bucket-name --query 'Parameter.Value' --output text)
log_info "S3 Bucket: ${S3_BUCKET}"

mkdir -p ~/environment/unicorn-store-spring/k8s/

# Create PV and PVC (idempotent via kubectl apply)
cat <<EOF > ~/environment/unicorn-store-spring/k8s/persistence.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: s3-profiling-pv
spec:
  capacity:
    storage: 1200Gi
  accessModes:
    - ReadWriteMany
  mountOptions:
    - allow-other
    - uid=1000
    - gid=1000
    - allow-delete
  csi:
    driver: s3.csi.aws.com
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      bucketName: ${S3_BUCKET}
      authenticationSource: pod
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-profiling-pvc
  namespace: unicorn-store-spring
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 1200Gi
  volumeName: s3-profiling-pv
EOF

kubectl apply -f ~/environment/unicorn-store-spring/k8s/persistence.yaml
log_success "S3 persistent volume and claim created"

# ============================================================================
# SECTION 5: Configure continuous profiling on the deployment
# ============================================================================

log_info "Configuring continuous profiling on deployment..."

# Use yq to modify the deployment manifest (idempotent - yq overwrites)
yq eval '.spec.template.spec.containers[0].command = ["/bin/sh", "-c"]' \
  -i ~/environment/unicorn-store-spring/k8s/deployment.yaml
yq eval '.spec.template.spec.containers[0].args = ["mkdir -p /s3/profiling/$HOSTNAME; (while true; do sleep 10; newest=$(ls /tmp/profile-*.jfr 2>/dev/null | sort -r | head -1); for f in /tmp/profile-*.jfr; do [ -f \"$f\" ] || continue; [ \"$f\" = \"$newest\" ] && continue; mv \"$f\" /s3/profiling/$HOSTNAME/; done; done &) && java -agentpath:/async-profiler/lib/libasyncProfiler.so=start,event=wall,file=/tmp/profile-%t.jfr,loop=30s -jar -Dserver.port=8080 /store-spring.jar"]' \
  -i ~/environment/unicorn-store-spring/k8s/deployment.yaml

# Add volume mount for S3 (idempotent - check before adding)
if ! yq eval '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "persistent-storage")' ~/environment/unicorn-store-spring/k8s/deployment.yaml 2>/dev/null | grep -q "persistent-storage"; then
  yq eval '.spec.template.spec.containers[0].volumeMounts += [{"name": "persistent-storage", "mountPath": "/s3"}]' \
    -i ~/environment/unicorn-store-spring/k8s/deployment.yaml
fi

if ! yq eval '.spec.template.spec.volumes[] | select(.name == "persistent-storage")' ~/environment/unicorn-store-spring/k8s/deployment.yaml 2>/dev/null | grep -q "persistent-storage"; then
  yq eval '.spec.template.spec.volumes += [{"name": "persistent-storage", "persistentVolumeClaim": {"claimName": "s3-profiling-pvc"}}]' \
    -i ~/environment/unicorn-store-spring/k8s/deployment.yaml
fi

log_success "Continuous profiling configured"

# ============================================================================
# SECTION 6: Enable Prometheus metrics scraping
# ============================================================================

log_info "Enabling Prometheus metrics scraping..."
yq eval '.spec.template.metadata.annotations."prometheus.io/scrape" = "true"' -i ~/environment/unicorn-store-spring/k8s/deployment.yaml
yq eval '.spec.template.metadata.annotations."prometheus.io/port" = "8080"' -i ~/environment/unicorn-store-spring/k8s/deployment.yaml
yq eval '.spec.template.metadata.annotations."prometheus.io/path" = "/actuator/prometheus"' -i ~/environment/unicorn-store-spring/k8s/deployment.yaml

yq eval 'del(.spec.template.spec.containers[0].env[] | select(.name == "CLUSTER"))' -i ~/environment/unicorn-store-spring/k8s/deployment.yaml
yq eval '.spec.template.spec.containers[0].env += [{"name": "CLUSTER", "value": "workshop-eks"}]' -i ~/environment/unicorn-store-spring/k8s/deployment.yaml
log_success "Prometheus scraping annotations added"

# ============================================================================
# SECTION 7: Deploy the application with profiling
# ============================================================================

log_info "Deploying application with profiling enabled..."
kubectl apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl rollout status deployment unicorn-store-spring -n unicorn-store-spring --timeout=180s
sleep 15
log_success "Application deployed with profiling"

# ============================================================================
# SECTION 8: Test the application
# ============================================================================

log_info "Testing the application..."
SVC_URL=http://$(kubectl get ingress unicorn-store-spring \
  -n unicorn-store-spring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -s --request POST ${SVC_URL}/unicorns \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq
log_success "Application test passed"

# ============================================================================
# SECTION 9: Verify profiling started
# ============================================================================

log_info "Verifying profiling started..."
for i in {1..12}; do
  PROFILING_LOG=$(kubectl logs $(kubectl get pods -n unicorn-store-spring \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}') \
    -n unicorn-store-spring 2>/dev/null | grep "Profiling started" || true)
  if [[ -n "$PROFILING_LOG" ]]; then
    log_success "Profiling started: $PROFILING_LOG"
    break
  fi
  log_info "Waiting for profiling to start... ($i/12)"
  sleep 10
done

if [[ -z "$PROFILING_LOG" ]]; then
  log_warning "Profiling start message not found in logs yet (may still be initializing)"
fi

# Verify profiling files in S3 (wait for at least one file)
log_info "Waiting for profiling files in S3..."
POD_NAME=$(kubectl get pods -n unicorn-store-spring --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
for i in {1..12}; do
  S3_FILES=$(aws s3 ls s3://${S3_BUCKET}/profiling/${POD_NAME}/ 2>/dev/null || true)
  if [[ -n "$S3_FILES" ]]; then
    log_success "Profiling files found in S3"
    echo "$S3_FILES" | tail -3
    break
  fi
  log_info "Waiting for profiling files... ($i/12)"
  sleep 10
done

# ============================================================================
# SECTION 10: Deploy AI JVM Analyzer
# ============================================================================

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "SECTION 2: AI JVM Analyzer Deployment"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy AI JVM Analyzer sources (idempotent - cp -r overwrites)
log_info "Copying AI JVM Analyzer sources..."
cp -r ~/java-on-aws/apps/ai-jvm-analyzer ~/environment/
log_success "AI JVM Analyzer sources copied"

# Build the container image with Jib
log_info "Building AI JVM Analyzer container image..."
cd ~/environment/ai-jvm-analyzer

aws ecr get-login-password --region ${AWS_REGION} \
  | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
ANALYZER_ECR_URI=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/ai-jvm-analyzer

mvn compile jib:build -Dimage=${ANALYZER_ECR_URI}:latest
log_success "AI JVM Analyzer image built and pushed"

# ============================================================================
# SECTION 11: Configure Pod Identity for AI JVM Analyzer
# ============================================================================

log_info "Configuring Pod Identity for AI JVM Analyzer..."
if ! aws eks list-pod-identity-associations --cluster-name ${CLUSTER_NAME} --query "associations[?serviceAccount=='ai-jvm-analyzer' && namespace=='monitoring']" --output text --no-cli-pager | grep -q .; then
    aws eks create-pod-identity-association \
        --cluster-name ${CLUSTER_NAME} \
        --namespace monitoring \
        --service-account ai-jvm-analyzer \
        --role-arn $(aws iam get-role --role-name ai-jvm-analyzer-eks-pod-role --query 'Role.Arn' --output text) \
        --no-cli-pager
    log_success "Pod Identity association created"
else
    log_success "Pod Identity association already exists"
fi
sleep 15

# ============================================================================
# SECTION 12: Deploy AI JVM Analyzer to EKS
# ============================================================================

log_info "Deploying AI JVM Analyzer to EKS..."
S3_BUCKET=$(aws ssm get-parameter --name workshop-bucket-name --query 'Parameter.Value' --output text)
ANALYZER_ECR_URI=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/ai-jvm-analyzer

mkdir -p ~/environment/ai-jvm-analyzer/k8s/
cat <<EOF > ~/environment/ai-jvm-analyzer/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-jvm-analyzer
  namespace: monitoring
  labels:
    app: ai-jvm-analyzer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ai-jvm-analyzer
  template:
    metadata:
      labels:
        app: ai-jvm-analyzer
    spec:
      serviceAccountName: ai-jvm-analyzer
      containers:
      - name: ai-jvm-analyzer
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
        image: ${ANALYZER_ECR_URI}:latest
        ports:
        - containerPort: 8080
        env:
        - name: AWS_REGION
          value: "${AWS_REGION:-us-east-1}"
        - name: AWS_S3_BUCKET
          value: "${S3_BUCKET}"
        - name: SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MODEL
          value: "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
        - name: SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MAX_TOKENS
          value: "10000"
        - name: GITHUB_REPO_URL
          value: "https://api.github.com/repos/aws-samples/java-on-aws"
        - name: GITHUB_REPO_PATH
          value: "apps/unicorn-store-spring"
        - name: FLAMEGRAPH_INCLUDE
          value: ".*unicorn.*"
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
  name: ai-jvm-analyzer
  namespace: monitoring
  labels:
    app: ai-jvm-analyzer
spec:
  selector:
    app: ai-jvm-analyzer
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ai-jvm-analyzer
  namespace: monitoring
EOF

kubectl apply -f ~/environment/ai-jvm-analyzer/k8s/deployment.yaml
log_info "Waiting for AI JVM Analyzer to be ready..."
kubectl wait deployment ai-jvm-analyzer -n monitoring --for condition=Available=True --timeout=120s
sleep 15

log_info "AI JVM Analyzer logs:"
kubectl logs $(kubectl get pods -n monitoring -l app=ai-jvm-analyzer --field-selector=status.phase=Running -o json \
    | jq -r '.items[0].metadata.name') -n monitoring
log_success "AI JVM Analyzer deployed"

# ============================================================================
# SECTION 13: Verify the deployment
# ============================================================================

log_info "Verifying AI JVM Analyzer deployment..."
kubectl get pods -n monitoring -l app=ai-jvm-analyzer
kubectl get svc ai-jvm-analyzer -n monitoring
log_success "AI JVM Analyzer deployment verified"

# ============================================================================
# SECTION 14: Retrieve Grafana access credentials
# ============================================================================

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Retrieving Grafana access credentials..."
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

GRAFANA_URL=$(kubectl get svc grafana -n monitoring -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
GRAFANA_PASSWORD=$(kubectl get secret grafana-admin -n monitoring -o jsonpath="{.data.password}" | base64 --decode)

echo ""
log_success "Grafana Access Details"
echo "🌍 URL:      http://${GRAFANA_URL}"
echo "👤 Username: admin"
echo "🔑 Password: ${GRAFANA_PASSWORD}"
echo ""

log_success "AI JVM Analyzer setup completed"
echo "✅ Success: AI JVM Analyzer (profiling + analyzer deployed, Grafana ready)"
