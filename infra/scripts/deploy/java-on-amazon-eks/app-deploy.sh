#!/bin/bash
# =============================================================================
# app-deploy.sh — deploy the participant's starting point to the cluster.
#
# Applies what ~/environment/unicorn-store-spring/k8s holds (written by app-prepare.sh):
# namespace + ServiceAccount, Pod Identity association to unicornstore-eks-pod-role,
# SecretProviderClass, Deployment, Service, Ingress. Waits for the Deployment to be
# Available. The ALB takes ~2 more minutes to provision; verify.sh checks it, so the
# bootstrap can install the platform pieces meanwhile.
#
# Needs kubectl against the cluster and the :latest image (app-prepare.sh). Idempotent.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh

APP_NAME="unicorn-store-spring"
NS="${APP_NAME}"
K8S="${HOME}/environment/${APP_NAME}/k8s"
CLUSTER_NAME="${PREFIX:-workshop}-eks"
POD_ROLE="unicornstore-eks-pod-role"

[ -f "${K8S}/deployment.yaml" ] || { log_error "${K8S}/deployment.yaml missing — run app-prepare.sh first"; exit 1; }

log_info "Namespace + ServiceAccount ${NS}..."
kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "${NS}" create serviceaccount "${APP_NAME}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

log_info "Pod Identity: ${NS}/${APP_NAME} -> ${POD_ROLE}..."
if ! aws eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" \
      --query "associations[?serviceAccount=='${APP_NAME}' && namespace=='${NS}']" --output text --no-cli-pager | grep -q .; then
  aws eks create-pod-identity-association --cluster-name "${CLUSTER_NAME}" \
    --namespace "${NS}" --service-account "${APP_NAME}" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${POD_ROLE}" --no-cli-pager >/dev/null
  log_success "Pod Identity association created"
else
  log_info "Pod Identity association already exists"
fi

log_info "Applying manifests from ${K8S}..."
kubectl apply -f "${K8S}/secret-provider-class.yaml" >/dev/null
kubectl apply -f "${K8S}/deployment.yaml" -f "${K8S}/service.yaml" -f "${K8S}/ingress.yaml" >/dev/null
kubectl -n "${NS}" wait deployment "${APP_NAME}" --for condition=Available=True --timeout=300s >/dev/null \
  || { log_error "Deployment not Available:"; kubectl -n "${NS}" get pods -o wide; kubectl -n "${NS}" describe pod -l app="${APP_NAME}" | tail -30; exit 1; }
log_success "Deployment ${NS}/${APP_NAME} Available (ALB provisioning continues in the background)"

echo "✅ Success: unicorn-store-spring deployed to EKS"
