#!/bin/bash

set -euo pipefail

NAMESPACE="monitoring"
ALERT_RULE_CONFIGMAP_NAME="unicornstore-alert-rule"
CONTACT_POINT_CONFIGMAP_NAME="unicornstore-contact-point"
DATASOURCE_CONFIGMAP_NAME="unicornstore-datasource"
DASHBOARD_CONFIGMAP_NAME="unicornstore-dashboard"
GRAFANA_HELM_RELEASE="grafana"

echo "🧹 Starting cleanup of Kubernetes-based Grafana alerting resources..."

# Delete alert rule configmap
echo "🔸 Deleting Alert Rule ConfigMap: $ALERT_RULE_CONFIGMAP_NAME"
kubectl delete configmap "$ALERT_RULE_CONFIGMAP_NAME" -n "$NAMESPACE" --ignore-not-found

# Delete contact point configmap
echo "🔸 Deleting Contact Point ConfigMap: $CONTACT_POINT_CONFIGMAP_NAME"
kubectl delete configmap "$CONTACT_POINT_CONFIGMAP_NAME" -n "$NAMESPACE" --ignore-not-found

# Delete datasource configmap
echo "🔸 Deleting Datasource ConfigMap: $DATASOURCE_CONFIGMAP_NAME"
kubectl delete configmap "$DATASOURCE_CONFIGMAP_NAME" -n "$NAMESPACE" --ignore-not-found

# Delete dashboard configmap
echo "🔸 Deleting Dashboard ConfigMap: $DASHBOARD_CONFIGMAP_NAME"
kubectl delete configmap "$DASHBOARD_CONFIGMAP_NAME" -n "$NAMESPACE" --ignore-not-found

# Optionally uninstall the Grafana Helm release
echo "🔸 Attempting to uninstall Helm release: $GRAFANA_HELM_RELEASE"
helm uninstall "$GRAFANA_HELM_RELEASE" -n "$NAMESPACE" || echo "⚠️ Helm release not found or already uninstalled."

echo "✅ Cleanup complete."