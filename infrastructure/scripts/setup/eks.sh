set -e

CLUSTER_NAME=${1:-"unicorn-store"}

check_cluster() {
    cluster_status=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query "cluster.status" --output text 2>/dev/null)
    if [ "$cluster_status" != "ACTIVE" ]; then
        echo "EKS cluster is not active. Current status: $cluster_status. Retrying in 10 seconds ..."
        return 1
    fi
    echo "EKS cluster is active."
    return 0
}

while ! check_cluster; do sleep 10; done

while ! aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME; do
    echo "Failed to update kubeconfig. Retrying in 10 seconds ..."
    sleep 10
done

while ! kubectl get ns; do
    echo "Failed to get namespaces. Retrying in 10 seconds ..."
    sleep 10
done

cat <<EOF | kubectl create -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  labels:
    app.kubernetes.io/name: LoadBalancerController
  name: alb
spec:
  controller: eks.amazonaws.com/alb
EOF

cat <<EOF | kubectl create -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: dedicated
spec:
  # weight: 50
  template:
    spec:
      nodeClassRef:
        group: eks.amazonaws.com
        kind: NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["c5.xlarge"]
  limits:
    cpu: 20
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
EOF

echo "Deploying External Secrets operator ..."

aws eks create-pod-identity-association --cluster-name $CLUSTER_NAME \
  --namespace external-secrets --service-account external-secrets \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/unicornstore-eks-eso-role

sleep 10

helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets --version 0.16.0 -n external-secrets --create-namespace --wait

cat <<EOF | envsubst | kubectl create -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: unicorn-store
spec:
  provider:
    aws:
      service: SecretsManager
      region: $AWS_REGION
      role: arn:aws:iam::$ACCOUNT_ID:role/unicornstore-eks-eso-sm-role
EOF

sleep 5

kubectl get ClusterSecretStore unicorn-store

cat <<EOF | envsubst | kubectl create -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterExternalSecret
metadata:
  name: unicornstore-db-secret
spec:
  # The name to be used on the ExternalSecrets
  externalSecretName: unicornstore-db-secret

  # The ExternalSecret will be deployed to these namespaces
  namespaceSelectors:
    - matchLabels:
        project: unicorn-store

  # How often to check and make sure that the ExternalSecrets exist in the matching namespaces
  refreshTime: 10s

  # This is the spec of the ExternalSecrets to be created
  externalSecretSpec:
    secretStoreRef:
      name: unicorn-store
      kind: ClusterSecretStore
    refreshInterval: 1h
    target:
      name: unicornstore-db-secret
      creationPolicy: Owner
    data:
      - secretKey: password
        remoteRef:
          key: unicornstore-db-secret
          property: password
EOF

echo "Setting up namespaces "
setup_namespace_and_service_account() {
    local name=$1
    local project=${2:-"unicorn-store"}

    echo "Setting up namespace for ${name} with project ${project}..."

    cat <<EOF | envsubst | kubectl create -f - || return 1
apiVersion: v1
kind: Namespace
metadata:
  name: ${name}
  labels:
    project: ${project}
    app: ${name}
EOF

    cat <<EOF | envsubst | kubectl create -f - || return 1
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${name}
  namespace: ${name}
  labels:
    project: ${project}
    app: ${name}
EOF

    aws eks create-pod-identity-association --cluster-name $CLUSTER_NAME \
      --namespace ${name} --service-account ${name} \
      --role-arn arn:aws:iam::$ACCOUNT_ID:role/unicornstore-eks-pod-role || return 1

    echo "Setup completed successfully for ${name}"
}

setup_namespace_and_service_account "unicorn-store-spring" "unicorn-store"
setup_namespace_and_service_account "unicorn-store-wildfly" "unicorn-store"
setup_namespace_and_service_account "unicorn-store-quarkus" "unicorn-store"
setup_namespace_and_service_account "unicorn-spring-ai-agent" "unicorn-store"

aws eks create-access-entry --cluster-name unicorn-store \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/WSParticipantRole \
  --type STANDARD 2>/dev/null || true
aws eks associate-access-policy --cluster-name unicorn-store \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/WSParticipantRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster 2>/dev/null || true

echo "EKS cluster setup is complete."
