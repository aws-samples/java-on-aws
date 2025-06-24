#!/bin/bash

set -euo pipefail

# 🔧 Configuration
NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
DATASOURCE_FILE="grafana-datasource.yaml"
DASHBOARD_JSON_FILE="jvm-dashboard.json"
DASHBOARD_PROVISIONING_FILE="dashboard-provisioning.yaml"
EXTRA_SCRAPE_FILE="extra-scrape-configs.yaml"

# 🔐 Generate Grafana credentials
GRAFANA_USER="admin"
GRAFANA_PASSWORD="$(openssl rand -base64 16 | tr -d '\n')"

# 🗆 Create namespace
kubectl create namespace "$NAMESPACE" 2>/dev/null || true

# 🧱 Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update

# 🔐 Grafana Secret (must be created BEFORE Helm install)
kubectl delete secret "$GRAFANA_SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true
kubectl create secret generic "$GRAFANA_SECRET_NAME" \
  --from-literal=username="$GRAFANA_USER" \
  --from-literal=password="$GRAFANA_PASSWORD" \
  -n "$NAMESPACE"

cat > "$EXTRA_SCRAPE_FILE" <<EOF
- job_name: "otel-collector"
  static_configs:
    - targets: ["otel-collector-service.unicorn-store-spring.svc.cluster.local:8889"]

- job_name: "ecs-cloudmap"
  metrics_path: "/actuator/prometheus"
  cloudmap_sd_configs:
    - namespace: "unicornstore.local"
      service: "unicorn-store-spring"
  relabel_configs:
    - source_labels: [__meta_cloudmap_instance_ipv4]
      regex: (.+)
      target_label: __address__
      replacement: "\${1}:9404"
    - source_labels: [__meta_cloudmap_instance_attribute_ECS_CLUSTER_NAME]
      target_label: ecs_cluster
    - source_labels: [__meta_cloudmap_instance_attribute_ECS_SERVICE_NAME]
      target_label: ecs_service
    - source_labels: [__meta_cloudmap_instance_attribute_AVAILABILITY_ZONE]
      target_label: az
    - source_labels: [__meta_cloudmap_instance_attribute_REGION]
      target_label: region
EOF

kubectl create configmap prometheus-extra-scrape --from-file="$EXTRA_SCRAPE_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 📂 Prometheus Installation with internal LoadBalancer
echo "📝 Writing temporary $VALUES_FILE"
cat <<EOF > $VALUES_FILE
alertmanager:
  enabled: false

kube-state-metrics:
  enabled: true

prometheus-node-exporter:
  enabled: true

prometheus-pushgateway:
  enabled: false

server:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal

  extraFlags:
    - web.enable-remote-write-receiver

  extraScrapeConfigs: |
    - job_name: "otel-collector"
      static_configs:
        - targets: ["otel-collector-service.unicorn-store-spring.svc.cluster.local:8889"]

    - job_name: "ecs-cloudmap"
      metrics_path: "/actuator/prometheus"
      cloudmap_sd_configs:
        - namespace: "unicornstore.local"
          service: "unicorn-store-spring"
      relabel_configs:
        - source_labels: [__meta_cloudmap_instance_ipv4]
          regex: (.+)
          target_label: __address__
          replacement: "\${1}:9404"
        - source_labels: [__meta_cloudmap_instance_attribute_ECS_CLUSTER_NAME]
          target_label: ecs_cluster
        - source_labels: [__meta_cloudmap_instance_attribute_ECS_SERVICE_NAME]
          target_label: ecs_service
        - source_labels: [__meta_cloudmap_instance_attribute_AVAILABILITY_ZONE]
          target_label: az
        - source_labels: [__meta_cloudmap_instance_attribute_REGION]
          target_label: region

  retention: 24h
  persistentVolume:
    size: 25Gi
EOF

echo "🚀 Deploying Prometheus with Helm values"
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE"

echo "🧹 Cleaning up $VALUES_FILE"
rm "$VALUES_FILE"

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

VPC_CIDR=$(aws ec2 describe-vpcs \
--vpc-ids "$VPC_ID" \
--query "Vpcs[0].CidrBlock" \
--output text)

for i in {1..30}; do
  PROM_LB_HOSTNAME=$(kubectl get svc prometheus-server -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "$PROM_LB_HOSTNAME" && "$PROM_LB_HOSTNAME" != "<no value>" ]]; then
    echo "✅ Prometheus ILB ready: $PROM_LB_HOSTNAME"
    aws ssm put-parameter --name "/unicornstore/prometheus/internal-dns" \
      --value "$PROM_LB_HOSTNAME" --type String --overwrite

    echo "🔍 Looking up SG for ILB: $PROM_LB_HOSTNAME"

    # Get Load Balancer ARN by matching its DNS name
    LB_ARN=$(aws elbv2 describe-load-balancers \
      --query "LoadBalancers[?DNSName=='$PROM_LB_HOSTNAME'].LoadBalancerArn" \
      --output text)

    if [[ -z "$LB_ARN" ]]; then
      echo "❌ Could not find Load Balancer ARN for $PROM_LB_HOSTNAME"
      exit 1
    fi

    # Get SG ID from Load Balancer
    ILB_SG_ID=$(aws elbv2 describe-load-balancers \
      --load-balancer-arns "$LB_ARN" \
      --query "LoadBalancers[0].SecurityGroups[0]" \
      --output text)

    if [[ -z "$ILB_SG_ID" || "$ILB_SG_ID" == "None" ]]; then
      echo "❌ Could not determine Security Group for Load Balancer $LB_ARN"
      exit 1
    fi

    echo "🔐 ILB Security Group: $ILB_SG_ID"

    # Authorize Prometheus port for ECS
    aws ec2 authorize-security-group-ingress \
      --group-id "$ILB_SG_ID" \
      --protocol tcp \
      --port 9090 \
      --cidr "$VPC_CIDR" \
      --output text || echo "ℹ️ Rule may already exist"

    break
  fi
  echo "⏳ Waiting for Prometheus ILB... ($i/30)"
  sleep 10
done

echo "✅ Prometheus now scrapes OTEL Collector and ECS targets via Cloud Map. Internal LoadBalancer is active."

# 🗄 Prometheus Datasource
cat > "$DATASOURCE_FILE" <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-server.monitoring.svc.cluster.local
    isDefault: true
EOF

kubectl create configmap unicornstore-datasource --from-file="$DATASOURCE_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap unicornstore-datasource -n "$NAMESPACE" grafana_datasource=1 --overwrite

# JVM Dashboard
curl -s -o "$DASHBOARD_JSON_FILE" https://grafana.com/api/dashboards/22108/revisions/3/download

cat > "$DASHBOARD_PROVISIONING_FILE" <<EOF
apiVersion: 1
providers:
  - name: 'unicornstore'
    orgId: 1
    folder: 'Unicorn Store Dashboards'
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
      foldersFromFilesStructure: false
EOF

kubectl create configmap unicornstore-dashboard --from-file="$DASHBOARD_JSON_FILE" --from-file="$DASHBOARD_PROVISIONING_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap unicornstore-dashboard -n "$NAMESPACE" grafana_dashboard=1 --overwrite

# 🚀 Grafana mit Sidecars
helm upgrade --install grafana grafana/grafana \
  --namespace "$NAMESPACE" \
  --set service.type=LoadBalancer \
  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing" \
  --set admin.existingSecret="$GRAFANA_SECRET_NAME" \
  --set admin.userKey=username \
  --set admin.passwordKey=password \
  --set persistence.enabled=true \
  --set persistence.storageClassName="gp3" \
  --set grafana.ini.paths.provisioning="/etc/grafana/provisioning" \
  --set grafana.ini.alerting.enabled=true \
  --set grafana.ini.unified_alerting.enabled=true \
  --set grafana.ini.unified_alerting.provisioning.enabled=true \
  --set sidecar.datasources.enabled=true \
  --set sidecar.datasources.folder="/etc/grafana/provisioning/datasources" \
  --set sidecar.datasources.label="grafana_datasource" \
  --set-string sidecar.datasources.labelValue="1" \
  --set sidecar.datasources.image.repository=kiwigrid/k8s-sidecar \
  --set sidecar.datasources.image.tag="1.30.0" \
  --set sidecar.dashboards.enabled=true \
  --set sidecar.dashboards.folder="/etc/grafana/provisioning/dashboards" \
  --set sidecar.dashboards.label="grafana_dashboard" \
  --set-string sidecar.dashboards.labelValue="1" \
  --set sidecar.dashboards.image.repository=kiwigrid/k8s-sidecar \
  --set sidecar.dashboards.image.tag="1.30.0" \
  --set sidecar.alerts.enabled=true \
  --set sidecar.alerts.folder="/etc/grafana/provisioning/alerting" \
  --set sidecar.alerts.label="grafana_alert" \
  --set-string sidecar.alerts.labelValue="1" \
  --set sidecar.alerts.image.repository=kiwigrid/k8s-sidecar \
  --set sidecar.alerts.image.tag="1.30.0" \
  --set sidecar.contactpoints.enabled=true \
  --set sidecar.contactpoints.folder="/etc/grafana/provisioning/contact-points" \
  --set sidecar.contactpoints.label="grafana_contactpoint" \
  --set-string sidecar.contactpoints.labelValue="1" \
  --set sidecar.contactpoints.image.repository=kiwigrid/k8s-sidecar \
  --set sidecar.contactpoints.image.tag="1.30.0"

# 🔁 Ensure Grafana picks up the new secret
kubectl rollout restart deployment grafana -n "$NAMESPACE"

# ⏳ LoadBalancer DNS + Login Retry
for i in {1..30}; do
  GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
  if [[ -n "$GRAFANA_LB" && "$GRAFANA_LB" != "<no value>" ]]; then
    echo "🚀 Found LoadBalancer hostname: $GRAFANA_LB"
    for j in {1..30}; do
      if dig +short "$GRAFANA_LB" | grep -qE "^[0-9.]+$"; then
        echo "✅ DNS resolved: http://$GRAFANA_LB"
        for k in {1..10}; do
          if curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" http://$GRAFANA_LB/api/user | grep -q '"id"'; then
            echo "✅ Grafana login successful"
            break 3
          fi
          echo "🔁 Waiting for Grafana to become ready ($k/10)..."
          sleep 10
        done
        echo "❌ Grafana login failed or not ready"
        exit 1
      fi
      echo "🔎 Attempt $j/30: DNS not resolved yet, waiting 5s..."
      sleep 5
    done
  fi
  echo "🔁 Attempt $i/30: LoadBalancer not ready yet, waiting 10s..."
  sleep 10
done

# 🔹 Contact Point + Alert Rule via API
AWS_REGION=$(aws configure get region)
ALARM_TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name unicornstore-stack --query "Stacks[0].Outputs[?starts_with(OutputKey, 'MonitoringAlarmTopic')].OutputValue" --output text)

DATASOURCE_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" http://$GRAFANA_LB/api/datasources | jq -r '.[] | select(.name=="Prometheus") | .uid')
FOLDER_UID=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" http://$GRAFANA_LB/api/folders | jq -r '.[] | select(.title=="Unicorn Store Dashboards") | .uid')

if [[ -z "$DATASOURCE_UID" || -z "$FOLDER_UID" ]]; then
  echo "❌ Required UID values could not be determined."
  exit 1
fi

CONTACT_POINT_PAYLOAD=$(cat <<'EOF'
{
  "uid": "unicornstore-sns-contact",
  "name": "SNS Contact",
  "type": "webhook",
  "settings": {
    "url": "https://sns.${AWS_REGION}.amazonaws.com/",
    "httpMethod": "POST",
    "headers": {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    "body": "Action=Publish&TopicArn=$ALARM_TOPIC_ARN&Message=\\\\${__message}"
  },
  "disableResolveMessage": false
}
EOF
)

curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" -X POST \
  -H "Content-Type: application/json" \
  -d "$CONTACT_POINT_PAYLOAD" \
  http://$GRAFANA_LB/api/v1/provisioning/contact-points | tee contactpoint_response.json

echo "📂 Using Folder UID: $FOLDER_UID"

sleep 3 # Just to be safe

ALERT_RULE_PAYLOAD=$(cat <<EOF
{
  "title": "High JVM Threads Alert",
  "ruleGroup": "unicornstore-group",
  "folderUID": "$FOLDER_UID",
  "noDataState": "OK",
  "execErrState": "Alerting",
  "for": "1m",
  "orgId": 1,
  "uid": "unicornstore-threads",
  "condition": "B",
  "annotations": {
    "summary": "High JVM thread count in other namespaces"
  },
  "labels": {
    "alert": "High JVM Threads",
    "cluster": "{{ \$labels.cluster }}",
    "cluster_type": "{{ \$labels.cluster_type }}",
    "container_name": "{{ \$labels.container_name }}",
    "namespace": "{{ \$labels.namespace }}",
    "task_pod_id": "{{ \$labels.task_pod_id }}"
  },
  "data": [
    {
      "refId": "A",
      "queryType": "",
      "relativeTimeRange": {
        "from": 600,
        "to": 0
      },
      "datasourceUid": "$DATASOURCE_UID",
      "model": {
        "expr": "sum by (namespace) (jvm_threads_live_threads{namespace!=\"unicorn-store-spring\"})",
        "hide": false,
        "intervalMs": 1000,
        "maxDataPoints": 43200,
        "refId": "A"
      }
    },
    {
      "refId": "B",
      "queryType": "",
      "relativeTimeRange": {
        "from": 0,
        "to": 0
      },
      "datasourceUid": "-100",
      "model": {
        "conditions": [
          {
            "evaluator": {
              "params": [200],
              "type": "gt"
            },
            "operator": {
              "type": "and"
            },
            "query": {
              "params": ["A"]
            },
            "reducer": {
              "params": [],
              "type": "last"
            },
            "type": "query"
          }
        ],
        "datasource": {
          "type": "__expr__",
          "uid": "-100"
        },
        "hide": false,
        "intervalMs": 1000,
        "maxDataPoints": 43200,
        "refId": "B",
        "type": "classic_conditions"
      }
    }
  ],
  "notifications": [
    {
      "uid": "unicornstore-sns-contact"
    }
  ]
}
EOF
)

echo "📤 Posting Alert Rule to Grafana Alerting API..."

curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" -X POST \
  -H "Content-Type: application/json" \
  -d "$ALERT_RULE_PAYLOAD" \
  http://$GRAFANA_LB/api/v1/provisioning/alert-rules | tee alert_response.json

echo "🔍 Alert Rule verification ... "

EXISTING_RULE=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
  "http://$GRAFANA_LB/api/v1/provisioning/alert-rules/unicornstore-threads")

if echo "$EXISTING_RULE" | jq -e .uid > /dev/null; then
  echo "✅ Alert Rule 'unicornstore-threads' has been created successfully:"
  echo "$EXISTING_RULE" | jq .
else
  echo "❌ Alert Rule couldn't be found, please check logs and payload!"
fi

# 🔐 Output
echo -e "\n✅ Monitoring Stack Setup Complete!"
echo "🌍 Grafana URL: http://$GRAFANA_LB"
echo "👤 Username: $GRAFANA_USER"
echo "🔑 Password: $GRAFANA_PASSWORD"