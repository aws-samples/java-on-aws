#!/bin/bash

set -euo pipefail

NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"

echo "🔐 Generating admin password..."
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 16)

echo "📦 Creating namespace '$NAMESPACE'..."
kubectl create namespace $NAMESPACE 2>/dev/null || true

echo "📡 Adding Helm repos..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "📊 Installing Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace $NAMESPACE \
  --set server.service.type=LoadBalancer \
  --set server.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-internal"="true" \
  --set server.ingress.enabled=false

echo "🔐 Creating Grafana credentials secret..."
kubectl delete secret $GRAFANA_SECRET_NAME -n $NAMESPACE 2>/dev/null || true
kubectl create secret generic $GRAFANA_SECRET_NAME \
  --from-literal=username=admin \
  --from-literal=password="$GRAFANA_ADMIN_PASSWORD" \
  -n $NAMESPACE

echo "📈 Installing Grafana..."
helm upgrade --install grafana grafana/grafana \
  --namespace $NAMESPACE \
  --set service.type=LoadBalancer \
  --set admin.existingSecret=$GRAFANA_SECRET_NAME \
  --set admin.userKey=username \
  --set admin.passwordKey=password \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.monitoring.svc.cluster.local \
  --set datasources."datasources\.yaml".datasources[0].access=proxy \
  --set datasources."datasources\.yaml".datasources[0].isDefault=true

echo "⏳ Waiting for Grafana LoadBalancer IP..."
for i in {1..30}; do
  GRAFANA_URL=$(kubectl get svc grafana -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  if [[ -n "$GRAFANA_URL" ]]; then break; fi
  sleep 10
done

if [[ -z "$GRAFANA_URL" ]]; then
  echo "❌ Could not determine Grafana LoadBalancer URL."
else
  echo "✅ Deployment complete."
  echo ""
  echo "🔗 Grafana URL: http://$GRAFANA_URL"
  echo "👤 Username: admin"
  echo "🔑 Password: $GRAFANA_ADMIN_PASSWORD"
fi
