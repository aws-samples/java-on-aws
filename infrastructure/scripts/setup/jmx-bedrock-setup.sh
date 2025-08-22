#!/usr/bin/env bash
set -Eeuo pipefail

### ───────────────────────────────
### Configuration (adjust if needed)
### ───────────────────────────────
APP_NAME="unicorn-store-spring"
ECR_REPO="$APP_NAME"
ECS_CLUSTER="$APP_NAME"
ECS_SERVICE="$APP_NAME"
CONTAINER_NAME="$APP_NAME"
CONTAINER_PORT=8080
ALB_LISTENER_PORT=80
TARGET_GROUP_NAME="$APP_NAME"
LOG_GROUP="/ecs/$APP_NAME"

WORKDIR="${WORKDIR:-$HOME/environment/unicorn-store-spring}"
DOCKERFILE_SOURCE="${DOCKERFILE_SOURCE:-dockerfiles/Dockerfile_02_multistage}"
DOCKERFILE_TARGET="${DOCKERFILE_TARGET:-Dockerfile}"

# Feature flags
ENABLE_ECS="${ENABLE_ECS:-true}"
ENABLE_EKS="${ENABLE_EKS:-true}"
ENABLE_PROM_RELOAD="${ENABLE_PROM_RELOAD:-true}"

# VPC/Subnet/SG conventions
VPC_TAG_NAME="${VPC_TAG_NAME:-unicornstore-vpc}"
TAG_PUBLIC_1="*PublicSubnet1"
TAG_PUBLIC_2="*PublicSubnet2"
TAG_PRIVATE_1="*PrivateSubnet1"
TAG_PRIVATE_2="*PrivateSubnet2"

# EKS namespaces/objects
EKS_NAMESPACE="${EKS_NAMESPACE:-unicorn-store-spring}"
KARPENTER_NODEPOOL_LABEL="${KARPENTER_NODEPOOL_LABEL:-dedicated}"   # optional

# Prometheus/Grafana
PROM_CM_NS="${PROM_CM_NS:-monitoring}"
PROM_CM_NAME="${PROM_CM_NAME:-prometheus-server}"
GRAFANA_SVC_NS="${GRAFANA_SVC_NS:-monitoring}"
GRAFANA_SVC_NAME="${GRAFANA_SVC_NAME:-grafana}"
GRAFANA_SECRET_NAME="${GRAFANA_SECRET_NAME:-grafana-admin}"

### ───────────────────────────────
### Prerequisites check
### ───────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' not found. Please install it."; exit 1; }; }
need aws
need jq
need docker
if [[ "$ENABLE_EKS" == "true" || "$ENABLE_PROM_RELOAD" == "true" ]]; then need kubectl; fi

AWS_REGION="${AWS_REGION:-$(aws configure get region || true)}"
[[ -n "${AWS_REGION:-}" ]] || { echo "❌ AWS_REGION is not set and not configured in AWS CLI."; exit 1; }
export AWS_REGION
ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
export ACCOUNT_ID
export AWS_PAGER=""

echo "ℹ️  Region:     $AWS_REGION"
echo "ℹ️  Account:    $ACCOUNT_ID"
echo "ℹ️  Work dir:   $WORKDIR"
mkdir -p "$WORKDIR"

### ───────────────────────────────
### Build & push Docker image to ECR
### ───────────────────────────────
cd "$WORKDIR"
if [[ -f "$DOCKERFILE_SOURCE" ]]; then
  cp "$DOCKERFILE_SOURCE" "$DOCKERFILE_TARGET"
fi

# Ensure ECR repo (idempotent)
if ! aws ecr describe-repositories --repository-names "$ECR_REPO" >/dev/null 2>&1; then
  echo "🪣 Creating ECR repository '$ECR_REPO'…"
  aws ecr create-repository --repository-name "$ECR_REPO" >/dev/null
else
  echo "✅ ECR repository '$ECR_REPO' exists."
fi

ECR_URI="$(aws ecr describe-repositories --repository-names "$ECR_REPO" | jq -r '.repositories[0].repositoryUri')"
echo "ℹ️  ECR URI: $ECR_URI"

echo "🔐 Logging in to ECR…"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_URI" >/dev/null

IMAGE_LOCAL_TAG="$APP_NAME:latest"
IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
echo "🐳 Building Docker image…"
docker build -t "$IMAGE_LOCAL_TAG" .

echo "🏷️  Tagging & pushing…"
docker tag "$IMAGE_LOCAL_TAG" "$ECR_URI:$IMAGE_TAG"
docker tag "$IMAGE_LOCAL_TAG" "$ECR_URI:latest"
docker push "$ECR_URI:$IMAGE_TAG" >/dev/null
docker push "$ECR_URI:latest" >/dev/null
docker images | head -n 10

### ───────────────────────────────
### Gather SSM/Secrets for Spring datasource
### ───────────────────────────────
echo "🔎 Fetching SSM/Secrets for datasource…"
DB_CONN_PARAM_NAME="${DB_CONN_PARAM_NAME:-unicornstore-db-connection-string}"
DB_PASS_SECRET_NAME="${DB_PASS_SECRET_NAME:-unicornstore-db-password-secret}"

UNICORNSTORE_DB_CONNECTION_STRING_ARN="$(aws ssm get-parameter --name "$DB_CONN_PARAM_NAME" --query 'Parameter.ARN' --output text 2>/dev/null || true)"
[[ "$UNICORNSTORE_DB_CONNECTION_STRING_ARN" != "None" && -n "$UNICORNSTORE_DB_CONNECTION_STRING_ARN" ]] || { echo "❌ SSM parameter '$DB_CONN_PARAM_NAME' not found."; exit 1; }
echo "✅ SSM ARN: $UNICORNSTORE_DB_CONNECTION_STRING_ARN"

UNICORNSTORE_DB_PASSWORD_SECRET_ARN="$(aws secretsmanager describe-secret --secret-id "$DB_PASS_SECRET_NAME" --query 'ARN' --output text 2>/dev/null || true)"
[[ "$UNICORNSTORE_DB_PASSWORD_SECRET_ARN" != "None" && -n "$UNICORNSTORE_DB_PASSWORD_SECRET_ARN" ]] || { echo "❌ Secrets Manager secret '$DB_PASS_SECRET_NAME' not found."; exit 1; }
echo "✅ Secret ARN: $UNICORNSTORE_DB_PASSWORD_SECRET_ARN"

### ───────────────────────────────
### ECS (Fargate) – Cluster, TaskDef, ALB, Service
### ───────────────────────────────
if [[ "$ENABLE_ECS" == "true" ]]; then
  echo "🏗️  Setting up ECS/Fargate…"

  # Register Task Definition
  TD_FILE="$(mktemp)"
  cat > "$TD_FILE" <<JSON
[
  {
    "name": "$CONTAINER_NAME",
    "image": "$ECR_URI:latest",
    "portMappings": [
      {"containerPort": $CONTAINER_PORT, "hostPort": $CONTAINER_PORT, "protocol": "tcp", "appProtocol": "http", "name": "$CONTAINER_NAME-$CONTAINER_PORT-tcp"}
    ],
    "essential": true,
    "secrets": [
      { "name": "SPRING_DATASOURCE_URL", "valueFrom": "$UNICORNSTORE_DB_CONNECTION_STRING_ARN" },
      { "name": "SPRING_DATASOURCE_PASSWORD", "valueFrom": "$UNICORNSTORE_DB_PASSWORD_SECRET_ARN" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "$LOG_GROUP",
        "awslogs-create-group": "true",
        "awslogs-region": "$AWS_REGION",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
JSON

  echo "📝 Registering task definition…"
  aws ecs register-task-definition \
    --family "$APP_NAME" \
    --requires-compatibilities FARGATE \
    --network-mode awsvpc \
    --cpu 1024 --memory 2048 \
    --task-role-arn "arn:aws:iam::$ACCOUNT_ID:role/unicornstore-ecs-task-role" \
    --execution-role-arn "arn:aws:iam::$ACCOUNT_ID:role/unicornstore-ecs-task-execution-role" \
    --container-definitions "file://$TD_FILE" \
    --runtime-platform '{"cpuArchitecture":"X86_64","operatingSystemFamily":"LINUX"}' \
    --no-cli-pager >/dev/null
  rm -f "$TD_FILE"

  # Ensure cluster
  if ! aws ecs describe-clusters --clusters "$ECS_CLUSTER" --query 'clusters[0].status' --output text 2>/dev/null | grep -qE 'ACTIVE|PROVISIONING'; then
    echo "🧩 Creating ECS cluster…"
    aws ecs create-cluster --cluster-name "$ECS_CLUSTER" --capacity-providers FARGATE --no-cli-pager >/dev/null
  else
    echo "✅ ECS cluster exists."
  fi

  # VPC/Subnets/Security Groups
  VPC_ID="$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_TAG_NAME" --query 'Vpcs[0].VpcId' --output text)"
  [[ "$VPC_ID" != "None" ]] || { echo "❌ VPC with tag Name=$VPC_TAG_NAME not found."; exit 1; }
  echo "ℹ️  VPC_ID: $VPC_ID"

  get_or_create_sg() {
    local name="$1" desc="$2"
    local sg_id
    sg_id="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$name" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
    if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
      aws ec2 create-security-group --group-name "$name" --description "$desc" --vpc-id "$VPC_ID" >/dev/null
      sg_id="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$name" --query 'SecurityGroups[0].GroupId' --output text)"
    fi
    echo "$sg_id"
  }

  SG_ALB_ID="$(get_or_create_sg "$APP_NAME-ecs-sg-alb" "Security group for $APP_NAME ALB")"
  # Ingress: 80 from anywhere
  if ! aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_ALB_ID" --query "SecurityGroupRules[?IpProtocol=='tcp' && FromPort==\`$ALB_LISTENER_PORT\` && ToPort==\`$ALB_LISTENER_PORT\`].SecurityGroupRuleId" --output text | grep -q .; then
    aws ec2 authorize-security-group-ingress --group-id "$SG_ALB_ID" --protocol tcp --port "$ALB_LISTENER_PORT" --cidr "0.0.0.0/0" >/dev/null || true
  fi

  SUBNET_PUBLIC_1="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$TAG_PUBLIC_1" --query 'Subnets[0].SubnetId' --output text)"
  SUBNET_PUBLIC_2="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$TAG_PUBLIC_2" --query 'Subnets[0].SubnetId' --output text)"
  SUBNET_PRIVATE_1="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$TAG_PRIVATE_1" --query 'Subnets[0].SubnetId' --output text)"
  SUBNET_PRIVATE_2="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$TAG_PRIVATE_2" --query 'Subnets[0].SubnetId' --output text)"
  for sn in "$SUBNET_PUBLIC_1" "$SUBNET_PUBLIC_2" "$SUBNET_PRIVATE_1" "$SUBNET_PRIVATE_2"; do
    [[ "$sn" != "None" && -n "$sn" ]] || { echo "❌ Expected subnet not found (check tags $TAG_PUBLIC_1/2, $TAG_PRIVATE_1/2)."; exit 1; }
  done

  # ALB create/get
  ALB_ARN="$(aws elbv2 describe-load-balancers --names "$APP_NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)"
  if [[ -z "$ALB_ARN" || "$ALB_ARN" == "None" ]]; then
    echo "🪪 Creating ALB…"
    ALB_ARN="$(aws elbv2 create-load-balancer --name "$APP_NAME" --subnets "$SUBNET_PUBLIC_1" "$SUBNET_PUBLIC_2" --security-groups "$SG_ALB_ID" --query 'LoadBalancers[0].LoadBalancerArn' --output text --no-cli-pager)"
  else
    echo "✅ ALB exists."
  fi

  # Target group create/get
  TG_ARN="$(aws elbv2 describe-target-groups --names "$TARGET_GROUP_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)"
  if [[ -z "$TG_ARN" || "$TG_ARN" == "None" ]]; then
    echo "🎯 Creating target group…"
    TG_ARN="$(aws elbv2 create-target-group --name "$TARGET_GROUP_NAME" --port "$CONTAINER_PORT" --protocol HTTP --vpc-id "$VPC_ID" --target-type ip --query 'TargetGroups[0].TargetGroupArn' --output text --no-cli-pager)"
    aws elbv2 modify-target-group \
      --target-group-arn "$TG_ARN" \
      --health-check-path "/actuator/health" \
      --health-check-port "traffic-port" \
      --health-check-protocol HTTP \
      --health-check-interval-seconds 30 \
      --health-check-timeout-seconds 5 \
      --healthy-threshold-count 2 \
      --unhealthy-threshold-count 3 >/dev/null
  else
    echo "✅ Target group exists."
  fi

  # Listener create/get
  if ! aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query "Listeners[?Port==\`$ALB_LISTENER_PORT\`].ListenerArn" --output text | grep -q .; then
    echo "📢 Creating listener…"
    aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --port "$ALB_LISTENER_PORT" --protocol HTTP --default-actions "Type=forward,TargetGroupArn=$TG_ARN" --no-cli-pager >/dev/null
  else
    echo "✅ Listener exists."
  fi

  # ECS service SG
  SG_ECS_ID="$(get_or_create_sg "$APP_NAME-ecs-sg" "Security group for $APP_NAME ECS Service")"
  # Ingress 8080 from ALB SG
  if ! aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_ECS_ID" --query "SecurityGroupRules[?IpProtocol=='tcp' && FromPort==\`$CONTAINER_PORT\` && ToPort==\`$CONTAINER_PORT\` && GroupOwnerId!=null]" --output text | grep -q .; then
    aws ec2 authorize-security-group-ingress --group-id "$SG_ECS_ID" --protocol tcp --port "$CONTAINER_PORT" --source-group "$SG_ALB_ID" >/dev/null || true
  fi
  # Optional: allow Lambda SG if present
  LAMBDA_SG_ID="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=unicornstore-thread-dump-lambda-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
  if [[ -n "$LAMBDA_SG_ID" && "$LAMBDA_SG_ID" != "None" ]]; then
    aws ec2 authorize-security-group-ingress --group-id "$SG_ECS_ID" --protocol tcp --port "$CONTAINER_PORT" --source-group "$LAMBDA_SG_ID" >/dev/null || true
  fi

  # Create/update ECS service
  TD_ARN="$(aws ecs describe-task-definition --task-definition "$APP_NAME" --query 'taskDefinition.taskDefinitionArn' --output text)"
  if ! aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].status' --output text 2>/dev/null | grep -qE 'ACTIVE|DRAINING'; then
    echo "🚀 Creating ECS service…"
    aws ecs create-service \
      --cluster "$ECS_CLUSTER" \
      --service-name "$ECS_SERVICE" \
      --task-definition "$TD_ARN" \
      --enable-execute-command \
      --desired-count 1 \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_PRIVATE_1,$SUBNET_PRIVATE_2],securityGroups=[$SG_ECS_ID],assignPublicIp=DISABLED}" \
      --load-balancer "targetGroupArn=$TG_ARN,containerName=$CONTAINER_NAME,containerPort=$CONTAINER_PORT" \
      --no-cli-pager >/dev/null
  else
    echo "♻️  Updating ECS service…"
    aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$TD_ARN" --force-new-deployment --no-cli-pager >/dev/null
  fi

  ALB_URL="$(aws elbv2 describe-load-balancers --names "$APP_NAME" --query 'LoadBalancers[0].DNSName' --output text)"
  echo "🌍 ECS ALB URL: http://$ALB_URL"
fi

### ───────────────────────────────
### EKS Deployment/Service/Ingress
### ───────────────────────────────
if [[ "$ENABLE_EKS" == "true" ]]; then
  echo "☸️  Applying EKS manifests…"
  # Ensure namespace and SA
  kubectl get ns "$EKS_NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$EKS_NAMESPACE"
  kubectl -n "$EKS_NAMESPACE" get sa "$APP_NAME" >/dev/null 2>&1 || kubectl -n "$EKS_NAMESPACE" create sa "$APP_NAME"

  ECR_URI="$(aws ecr describe-repositories --repository-names "$ECR_REPO" | jq -r '.repositories[0].repositoryUri')"
  SPRING_DATASOURCE_URL="$(aws ssm get-parameter --name "$DB_CONN_PARAM_NAME" | jq -r '.Parameter.Value')"

  # Deployment
  DEP_FILE="$(mktemp)"
  cat > "$DEP_FILE" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $EKS_NAMESPACE
  labels:
    project: unicorn-store
    app: $APP_NAME
spec:
  replicas: 1
  selector:
    matchLabels: { app: $APP_NAME }
  template:
    metadata:
      labels: { app: $APP_NAME }
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "$CONTAINER_PORT"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      serviceAccountName: $APP_NAME
      $( [[ -n "$KARPENTER_NODEPOOL_LABEL" ]] && echo "nodeSelector:
        karpenter.sh/nodepool: $KARPENTER_NODEPOOL_LABEL" )
      containers:
        - name: $APP_NAME
          image: $ECR_URI:latest
          imagePullPolicy: Always
          resources:
            requests: { cpu: "1", memory: "2Gi" }
          env:
            - name: CLUSTER
              value: unicorn-store
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: unicornstore-db-secret
                  key: password
                  optional: false
            - name: SPRING_DATASOURCE_URL
              value: "$SPRING_DATASOURCE_URL"
          ports:
            - containerPort: $CONTAINER_PORT
          livenessProbe:
            httpGet: { path: /actuator/health/liveness, port: $CONTAINER_PORT }
            failureThreshold: 6
            periodSeconds: 5
          readinessProbe:
            httpGet: { path: /actuator/health/readiness, port: $CONTAINER_PORT }
            failureThreshold: 6
            periodSeconds: 5
            initialDelaySeconds: 10
          startupProbe:
            httpGet: { path: /actuator/health/liveness, port: $CONTAINER_PORT }
            failureThreshold: 10
            periodSeconds: 5
            initialDelaySeconds: 20
          lifecycle:
            preStop:
              exec:
                command: ["sh","-c","sleep 10"]
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
YAML
  kubectl apply -f "$DEP_FILE"
  rm -f "$DEP_FILE"

  # Service
  SVC_FILE="$(mktemp)"
  cat > "$SVC_FILE" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $EKS_NAMESPACE
  labels: { project: unicorn-store, app: $APP_NAME }
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: $CONTAINER_PORT
      protocol: TCP
  selector: { app: $APP_NAME }
YAML
  kubectl apply -f "$SVC_FILE"
  rm -f "$SVC_FILE"

  # Ingress (ALB Ingress Controller expected)
  ING_FILE="$(mktemp)"
  cat > "$ING_FILE" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP_NAME
  namespace: $EKS_NAMESPACE
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
  labels:
    project: unicorn-store
    app: $APP_NAME
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: $APP_NAME
                port:
                  number: 80
YAML
  kubectl apply -f "$ING_FILE"
  rm -f "$ING_FILE"
fi

### ───────────────────────────────
### Prometheus: add ECS ALB scrape target + show Grafana access
### ───────────────────────────────
if [[ "$ENABLE_PROM_RELOAD" == "true" && "${ALB_URL:-}" != "" && "$ENABLE_ECS" == "true" ]]; then
  echo "📈 Updating Prometheus ConfigMap (if present)…"
  if kubectl -n "$PROM_CM_NS" get configmap "$PROM_CM_NAME" >/dev/null 2>&1; then
    TMP_CFG="$(mktemp)"
    kubectl get configmap "$PROM_CM_NAME" -n "$PROM_CM_NS" -o jsonpath='{.data.prometheus\.yml}' > "$TMP_CFG"
    {
      echo ""
      echo "- job_name: 'ecs-$APP_NAME'"
      echo "  static_configs:"
      echo "  - targets: ['${ALB_URL}:80']"
      echo "  metrics_path: '/actuator/prometheus'"
      echo "  scrape_interval: 15s"
    } >> "$TMP_CFG"
    kubectl create configmap "$PROM_CM_NAME" -n "$PROM_CM_NS" --from-file=prometheus.yml="$TMP_CFG" --dry-run=client -o yaml | kubectl replace -f -
    rm -f "$TMP_CFG"

    echo "🔁 Reloading Prometheus…"
    kubectl -n "$PROM_CM_NS" port-forward svc/"$PROM_CM_NAME" 9090:80 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 3
    curl -sf -X POST http://localhost:9090/-/reload || true
    kill "$PF_PID" 2>/dev/null || true
    echo "✅ Added ECS ALB as scrape target: $ALB_URL"
  else
    echo "ℹ️  Prometheus ConfigMap '$PROM_CM_NAME' in namespace '$PROM_CM_NS' not found — skipping."
  fi
fi

if kubectl -n "$GRAFANA_SVC_NS" get svc "$GRAFANA_SVC_NAME" >/dev/null 2>&1; then
  GRAFANA_URL="$(kubectl get svc "$GRAFANA_SVC_NAME" -n "$GRAFANA_SVC_NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  GRAFANA_PASSWORD="$(kubectl get secret "$GRAFANA_SECRET_NAME" -n "$GRAFANA_SVC_NS" -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode || true)"
  echo "✅ Grafana:"
  echo "   🌍 URL:      http://$GRAFANA_URL"
  echo "   👤 Username: admin"
  echo "   🔑 Password: $GRAFANA_PASSWORD"
fi

echo "🎉 Done!"
