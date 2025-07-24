#!/bin/bash

set -euo pipefail

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

# --- Configuration ---
NAMESPACE="monitoring"
GRAFANA_SECRET_NAME="grafana-admin"
SECRET_NAME="grafana-webhook-credentials"
PARAM_NAME="/unicornstore/prometheus/internal-dns"

# Temporary files to clean up
VALUES_FILE="prometheus-values.yaml"
EXTRA_SCRAPE_FILE="extra-scrape-configs.yaml"
DATASOURCE_FILE="grafana-datasource.yaml"
DASHBOARD_JSON_FILE="jvm-dashboard.json"
DASHBOARD_PROVISIONING_FILE="dashboard-provisioning.yaml"
ALERT_RULE_FILE="grafana-alert-rules.yaml"
GRAFANA_VALUES_FILE="grafana-values.yaml"
LAMBDA_ALERT_RULE_FILE="lambda-alert-rule.json"
NOTIFICATION_POLICY_CONFIGMAP_FILE="notification-policy.yaml"

cleanup_temp_files() {
  log "🧹 Cleaning up temporary files..."
  rm -f "$VALUES_FILE" "$EXTRA_SCRAPE_FILE" "$DATASOURCE_FILE" "$NOTIFICATION_POLICY_CONFIGMAP_FILE" \
        "$DASHBOARD_JSON_FILE" "$DASHBOARD_PROVISIONING_FILE" \
        "$ALERT_RULE_FILE" "$GRAFANA_VALUES_FILE" "$LAMBDA_ALERT_RULE_FILE" \
        "grafana-credentials.txt"
}
trap cleanup_temp_files EXIT

log "🚨 Starting monitoring stack cleanup..."

# --- Get Grafana credentials before cleanup ---
GRAFANA_USER="admin"
GRAFANA_PASSWORD=""

if kubectl get secret "$GRAFANA_SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  GRAFANA_PASSWORD=$(kubectl get secret "$GRAFANA_SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.password}" | base64 --decode)
  log "📋 Retrieved Grafana password from existing secret"
fi

# Get Grafana LoadBalancer hostname before cleanup
GRAFANA_LB=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
if [[ -n "$GRAFANA_LB" && "$GRAFANA_LB" != "<no value>" ]]; then
  GRAFANA_URL="http://$GRAFANA_LB"
  log "📋 Found Grafana URL: $GRAFANA_URL"
fi

# Get Prometheus LoadBalancer hostname before cleanup
PROM_LB_HOSTNAME=$(kubectl get svc prometheus-server -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null || true)
if [[ -n "$PROM_LB_HOSTNAME" && "$PROM_LB_HOSTNAME" != "<no value>" ]]; then
  log "📋 Found Prometheus hostname: $PROM_LB_HOSTNAME"
fi

# --- Clean up Grafana alert rules (if Grafana is accessible) ---
if [[ -n "$GRAFANA_LB" && -n "$GRAFANA_PASSWORD" ]]; then
  log "🔧 Cleaning up Grafana alert rules..."
  
  # Wait briefly for Grafana to be accessible
  for i in {1..5}; do
    if curl -s -o /dev/null -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" | grep -q "200"; then
      log "✅ Grafana is accessible for cleanup"
      break
    fi
    log "⏳ Waiting for Grafana access... ($i/5)"
    sleep 2
  done
  
  # Delete alert rules
  ALERT_RULES=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/alert-rules" 2>/dev/null || echo "[]")
  if [[ "$ALERT_RULES" != "[]" ]]; then
    echo "$ALERT_RULES" | jq -r '.[].uid' | while read -r rule_uid; do
      if [[ -n "$rule_uid" && "$rule_uid" != "null" ]]; then
        log "🗑️ Deleting alert rule: $rule_uid"
        curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
          "$GRAFANA_URL/api/v1/provisioning/alert-rules/$rule_uid" >/dev/null || true
      fi
    done
  fi
  
  # Delete contact points
  CONTACT_POINTS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/v1/provisioning/contact-points" 2>/dev/null || echo "[]")
  if [[ "$CONTACT_POINTS" != "[]" ]]; then
    echo "$CONTACT_POINTS" | jq -r '.[] | select(.name=="lambda-webhook") | .uid' | while read -r cp_uid; do
      if [[ -n "$cp_uid" && "$cp_uid" != "null" ]]; then
        log "🗑️ Deleting contact point: $cp_uid"
        curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
          "$GRAFANA_URL/api/v1/provisioning/contact-points/$cp_uid" >/dev/null || true
      fi
    done
  fi
  
  # Delete folders
  FOLDERS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/folders" 2>/dev/null || echo "[]")
  if [[ "$FOLDERS" != "[]" ]]; then
    echo "$FOLDERS" | jq -r '.[] | select(.title=="Unicorn Store Dashboards") | .uid' | while read -r folder_uid; do
      if [[ -n "$folder_uid" && "$folder_uid" != "null" ]]; then
        log "🗑️ Deleting folder: $folder_uid"
        curl -s -X DELETE -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
          "$GRAFANA_URL/api/folders/$folder_uid" >/dev/null || true
      fi
    done
  fi
fi

# --- Clean up Prometheus LoadBalancer Security Group rules ---
if [[ -n "$PROM_LB_HOSTNAME" ]]; then
  log "🔐 Cleaning up Prometheus LoadBalancer Security Group rules..."
  
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" --query "Vpcs[0].VpcId" --output text 2>/dev/null || true)
  if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
    VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlock" --output text 2>/dev/null || true)
    
    LB_ARN=$(aws elbv2 describe-load-balancers --output json 2>/dev/null | jq -r \
      --arg dns "$PROM_LB_HOSTNAME" '
        .LoadBalancers[] | select(.DNSName == $dns) | .LoadBalancerArn' || true)
    
    if [[ -n "$LB_ARN" ]]; then
      ILB_SG_ID=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$LB_ARN" \
        --query "LoadBalancers[0].SecurityGroups[0]" \
        --output text 2>/dev/null || true)
      
      if [[ -n "$ILB_SG_ID" && "$ILB_SG_ID" != "None" ]]; then
        log "🗑️ Removing security group rule from $ILB_SG_ID"
        aws ec2 revoke-security-group-ingress \
          --group-id "$ILB_SG_ID" \
          --protocol tcp \
          --port 9090 \
          --cidr "$VPC_CIDR" \
          --output text 2>/dev/null || log "ℹ️ Security group rule may not exist"
      fi
    fi
  fi
fi

# --- Uninstall Helm releases ---
log "🗑️ Uninstalling Helm releases..."

if helm list -n "$NAMESPACE" | grep -q "grafana"; then
  log "🗑️ Uninstalling Grafana..."
  helm uninstall grafana --namespace "$NAMESPACE" || log "⚠️ Failed to uninstall Grafana"
fi

if helm list -n "$NAMESPACE" | grep -q "prometheus"; then
  log "🗑️ Uninstalling Prometheus..."
  helm uninstall prometheus --namespace "$NAMESPACE" || log "⚠️ Failed to uninstall Prometheus"
fi

# --- Clean up Kubernetes resources ---
log "🗑️ Cleaning up Kubernetes resources..."

# Delete ConfigMaps
kubectl delete configmap unicornstore-datasource -n "$NAMESPACE" 2>/dev/null || log "ℹ️ ConfigMap unicornstore-datasource not found"
kubectl delete configmap unicornstore-dashboard -n "$NAMESPACE" 2>/dev/null || log "ℹ️ ConfigMap unicornstore-dashboard not found"
kubectl delete configmap prometheus-extra-scrape -n "$NAMESPACE" 2>/dev/null || log "ℹ️ ConfigMap prometheus-extra-scrape not found"
kubectl delete configmap unicornstore-notification-policy -n "$NAMESPACE" 2>/dev/null || log "ℹ️ ConfigMap unicornstore-notification-policy not found"

# Delete Secrets
kubectl delete secret "$GRAFANA_SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || log "ℹ️ Secret $GRAFANA_SECRET_NAME not found"

# Delete PVCs (Persistent Volume Claims)
log "🗑️ Cleaning up Persistent Volume Claims..."
kubectl get pvc -n "$NAMESPACE" -o name 2>/dev/null | while read -r pvc; do
  if [[ -n "$pvc" ]]; then
    log "🗑️ Deleting $pvc"
    kubectl delete "$pvc" -n "$NAMESPACE" || log "⚠️ Failed to delete $pvc"
  fi
done

# Wait for PVCs to be deleted
log "⏳ Waiting for PVCs to be fully deleted..."
for i in {1..30}; do
  PVC_COUNT=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
  if [[ "$PVC_COUNT" -eq 0 ]]; then
    log "✅ All PVCs deleted"
    break
  fi
  log "⏳ Waiting for $PVC_COUNT PVCs to be deleted... ($i/30)"
  sleep 5
done

# --- Delete namespace ---
log "🗑️ Deleting namespace $NAMESPACE..."
kubectl delete namespace "$NAMESPACE" --timeout=60s 2>/dev/null || log "⚠️ Failed to delete namespace or namespace not found"

# Wait for namespace deletion
log "⏳ Waiting for namespace deletion..."
for i in {1..30}; do
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log "✅ Namespace $NAMESPACE deleted"
    break
  fi
  log "⏳ Waiting for namespace deletion... ($i/30)"
  sleep 5
done

# --- Clean up AWS resources ---
log "🗑️ Cleaning up AWS resources..."

# Delete SSM Parameter
if aws ssm get-parameter --name "$PARAM_NAME" >/dev/null 2>&1; then
  log "🗑️ Deleting SSM parameter $PARAM_NAME"
  aws ssm delete-parameter --name "$PARAM_NAME" || log "⚠️ Failed to delete SSM parameter"
else
  log "ℹ️ SSM parameter $PARAM_NAME not found"
fi

# Delete Secrets Manager secret
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  log "🗑️ Deleting Secrets Manager secret $SECRET_NAME"
  aws secretsmanager delete-secret --secret-id "$SECRET_NAME" --force-delete-without-recovery || log "⚠️ Failed to delete secret"
else
  log "ℹ️ Secrets Manager secret $SECRET_NAME not found"
fi

# --- Clean up Lambda Function URL (optional) ---
log "🔧 Checking Lambda Function URL..."
LAMBDA_FUNCTION_NAME="unicornstore-thread-dump-lambda"

if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
  # Check if Function URL exists
  if aws lambda get-function-url-config --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
    log "🗑️ Removing Lambda Function URL..."
    aws lambda delete-function-url-config --function-name "$LAMBDA_FUNCTION_NAME" || log "⚠️ Failed to delete Function URL"
    
    # Remove the permission
    aws lambda remove-permission \
      --function-name "$LAMBDA_FUNCTION_NAME" \
      --statement-id AllowPublicAccess 2>/dev/null || log "ℹ️ Permission may not exist"
  else
    log "ℹ️ Lambda Function URL not found"
  fi
else
  log "ℹ️ Lambda function $LAMBDA_FUNCTION_NAME not found"
fi

# --- Remove Helm repositories (optional) ---
log "🗑️ Cleaning up Helm repositories..."
helm repo remove prometheus-community 2>/dev/null || log "ℹ️ prometheus-community repo not found"
helm repo remove grafana 2>/dev/null || log "ℹ️ grafana repo not found"

# --- Final validation ---
log "🔍 Validating cleanup..."

# Check if namespace still exists
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  log "⚠️ Warning: Namespace $NAMESPACE still exists"
else
  log "✅ Namespace $NAMESPACE successfully deleted"
fi

# Check if Helm releases still exist
REMAINING_RELEASES=$(helm list -A | grep -E "(prometheus|grafana)" || true)
if [[ -n "$REMAINING_RELEASES" ]]; then
  log "⚠️ Warning: Some Helm releases may still exist:"
  echo "$REMAINING_RELEASES"
else
  log "✅ All monitoring Helm releases cleaned up"
fi

# Check AWS resources
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  log "⚠️ Warning: Secrets Manager secret $SECRET_NAME still exists"
else
  log "✅ Secrets Manager secret cleaned up"
fi

if aws ssm get-parameter --name "$PARAM_NAME" >/dev/null 2>&1; then
  log "⚠️ Warning: SSM parameter $PARAM_NAME still exists"
else
  log "✅ SSM parameter cleaned up"
fi

log "✅ Monitoring stack cleanup completed!"
log "ℹ️ Note: Some AWS resources (like Load Balancers) may take additional time to fully terminate"
log "ℹ️ Note: Persistent Volumes may need manual cleanup if they were not automatically deleted"

# --- Optional: List remaining resources for manual cleanup ---
log "📋 Checking for any remaining resources that may need manual cleanup..."

# Check for remaining PVs
REMAINING_PVS=$(kubectl get pv | grep "$NAMESPACE" || true)
if [[ -n "$REMAINING_PVS" ]]; then
  log "⚠️ Warning: Found Persistent Volumes that may need manual cleanup:"
  echo "$REMAINING_PVS"
fi

# Check for remaining Load Balancers
REMAINING_LBS=$(aws elbv2 describe-load-balancers --output table | grep -E "(prometheus|grafana)" || true)
if [[ -n "$REMAINING_LBS" ]]; then
  log "⚠️ Warning: Found Load Balancers that may need manual cleanup:"
  echo "$REMAINING_LBS"
fi

log "🎉 Cleanup script execution completed!"
