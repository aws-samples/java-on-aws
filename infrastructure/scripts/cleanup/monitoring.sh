#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

NAMESPACE="monitoring"

log "🧹 Starting monitoring cleanup..."

# Get Grafana URL before cleanup
GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || echo "")

log "🔧 Uninstalling Helm releases..."
helm uninstall grafana -n "$NAMESPACE" 2>/dev/null || true
helm uninstall prometheus -n "$NAMESPACE" 2>/dev/null || true

log "🗑️ Deleting ConfigMaps..."
kubectl delete configmap prometheus-datasource -n "$NAMESPACE" 2>/dev/null || true

log "🔐 Deleting secrets and PVCs..."
kubectl delete secret grafana-admin -n "$NAMESPACE" 2>/dev/null || true
kubectl delete pvc --all -n "$NAMESPACE" 2>/dev/null || true

log "🧹 Deleting remaining resources..."
kubectl delete all --all -n "$NAMESPACE" 2>/dev/null || true
kubectl delete namespace "$NAMESPACE" 2>/dev/null || true

log "⏳ Waiting for namespace deletion..."
while kubectl get namespace "$NAMESPACE" 2>/dev/null; do
  sleep 5
done

# Clean up LoadBalancer
if [[ -n "$GRAFANA_LB" ]]; then
  log "🔧 Cleaning up LoadBalancer..."
  LB_ARNS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='$GRAFANA_LB'].LoadBalancerArn" --output text 2>/dev/null || echo "")

  for LB_ARN in $LB_ARNS; do
    if [[ -n "$LB_ARN" && "$LB_ARN" != "None" ]]; then
      LISTENER_ARNS=$(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" --query 'Listeners[].ListenerArn' --output text 2>/dev/null || echo "")
      for LISTENER_ARN in $LISTENER_ARNS; do
        aws elbv2 delete-listener --listener-arn "$LISTENER_ARN" 2>/dev/null || true
      done
      aws elbv2 delete-load-balancer --load-balancer-arn "$LB_ARN" 2>/dev/null || true
      log "✅ LoadBalancer cleaned up"
    fi
  done
fi

log "✅ Monitoring cleanup completed"
