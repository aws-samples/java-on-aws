#!/bin/bash

set -euo pipefail

NAMESPACE="monitoring"

# ConfigMap-Namen
ALERT_RULE_CONFIGMAP_NAME="unicornstore-alert-rule"
CONTACT_POINT_CONFIGMAP_NAME="unicornstore-contact-point"
DATASOURCE_CONFIGMAP_NAME="unicornstore-datasource"
DASHBOARD_CONFIGMAP_NAME="unicornstore-dashboard"
SCRAPE_CONFIGMAP_NAME="prometheus-extra-scrape"

# Helm Releases
GRAFANA_HELM_RELEASE="grafana"
PROMETHEUS_HELM_RELEASE="prometheus"

echo "🧹 Starting cleanup of Kubernetes-based monitoring stack..."

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

# Delete extra scrape config
echo "🔸 Deleting Extra Scrape ConfigMap: $SCRAPE_CONFIGMAP_NAME"
kubectl delete configmap "$SCRAPE_CONFIGMAP_NAME" -n "$NAMESPACE" --ignore-not-found

# Uninstall Helm releases
echo "🔸 Uninstalling Helm release: $GRAFANA_HELM_RELEASE"
helm uninstall "$GRAFANA_HELM_RELEASE" -n "$NAMESPACE" || echo "⚠️ Grafana release not found or already uninstalled."

echo "🔸 Uninstalling Helm release: $PROMETHEUS_HELM_RELEASE"
helm uninstall "$PROMETHEUS_HELM_RELEASE" -n "$NAMESPACE"