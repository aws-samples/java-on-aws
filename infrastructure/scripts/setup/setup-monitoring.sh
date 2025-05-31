#!/bin/bash

set -euo pipefail

NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
PROMETHEUS_SSM_PARAM_NAME="/unicornstore/prometheus/external-url"
GRAFANA_SSM_PARAM_NAME="/unicornstore/grafana/public-url"
STORAGE_CLASS="gp3"

echo "🔐 Generating admin password..."
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 16)

echo "📦 Creating namespace '$NAMESPACE'..."
kubectl create namespace $NAMESPACE 2>/dev/null || true

echo "📡 Adding Helm repos..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "📊 Installing Prometheus (internal only)..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace $NAMESPACE \
  --set server.service.type=LoadBalancer \
  --set-string server.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-internal"="true" \
  --set server.persistentVolume.storageClass=$STORAGE_CLASS \
  --set server.persistentVolume.size=4Gi \
  --set alertmanager.enabled=false

echo "🔐 Creating Grafana credentials secret..."
kubectl delete secret $GRAFANA_SECRET_NAME -n $NAMESPACE 2>/dev/null || true
kubectl create secret generic $GRAFANA_SECRET_NAME \
  --from-literal=username=admin \
  --from-literal=password="$GRAFANA_ADMIN_PASSWORD" \
  -n $NAMESPACE

echo "📈 Installing Grafana (public)..."
helm upgrade --install grafana grafana/grafana \
  --namespace $NAMESPACE \
  --set service.type=LoadBalancer \
  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing" \
  --set persistence.enabled=true \
  --set persistence.storageClassName=$STORAGE_CLASS \
  --set persistence.size=2Gi \
  --set admin.existingSecret=$GRAFANA_SECRET_NAME \
  --set admin.userKey=username \
  --set admin.passwordKey=password \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.monitoring.svc.cluster.local \
  --set datasources."datasources\.yaml".datasources[0].access=proxy \
  --set datasources."datasources\.yaml".datasources[0].isDefault=true

echo "🔔 Deploying Alertmanager (with PVC)..."
ALARM_TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name unicornstore-stack \
  --query "Stacks[0].Outputs[?OutputKey=='AlarmTopicArn'].OutputValue" \
  --output text)

helm upgrade --install alertmanager prometheus-community/alertmanager \
  --namespace $NAMESPACE \
  --set alertmanager.statefulSet.enabled=true \
  --set alertmanager.persistentVolume.enabled=true \
  --set alertmanager.persistentVolume.storageClass=$STORAGE_CLASS \
  --set alertmanager.persistentVolume.size=2Gi \
  --set config.global.resolve_timeout="5m" \
  --set config.route.receiver="sns" \
  --set config.receivers[0].name="sns" \
  --set config.receivers[0].sns_configs[0].topic_arn="$ALARM_TOPIC_ARN" \
  --set config.receivers[0].sns_configs[0].send_resolved=true

echo "🔍 Waiting for Grafana external URL to be resolvable..."
for i in {1..30}; do
  GRAFANA_LB=$(kubectl get svc grafana -n $NAMESPACE -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" || true)
  if [[ -n "$GRAFANA_LB" ]]; then
    if nslookup "$GRAFANA_LB" >/dev/null 2>&1; then
      echo "🌐 Grafana is resolvable at: http://$GRAFANA_LB"
      break
    fi
  fi
  echo "⏳ Waiting for DNS resolution of $GRAFANA_LB..."
  sleep 10
done

if [[ -z "$GRAFANA_LB" ]]; then
  echo "❌ Failed to resolve Grafana LoadBalancer DNS"
  exit 1
fi

echo "💾 Storing URLs in SSM Parameter Store..."
aws ssm put-parameter --name "$PROMETHEUS_SSM_PARAM_NAME" --value "http://prometheus-server.monitoring.svc.cluster.local" --type String --overwrite
aws ssm put-parameter --name "$GRAFANA_SSM_PARAM_NAME" --value "http://$GRAFANA_LB" --type String --overwrite

echo "✅ Monitoring stack deployed successfully"
