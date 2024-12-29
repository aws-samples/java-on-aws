CLUSTER_NAME=unicorn-store
APP_NAME=unicorn-store-spring

aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME

echo Deleting EKS $APP_NAME ...

kubectl delete ingress $APP_NAME -n $APP_NAME
kubectl delete service $APP_NAME -n $APP_NAME
kubectl delete deployment $APP_NAME -n $APP_NAME --cascade=foreground
kubectl delete sa $APP_NAME -n $APP_NAME
kubectl delete namespace $APP_NAME

kubectl delete ingressclass alb
kubectl delete nodepool dedicated
kubectl delete nodepool nodes-arm64

helm uninstall external-secrets -n external-secrets

# List all Pod Identity associations in the cluster
ASSOCIATIONS=$(aws eks list-pod-identity-associations \
    --cluster-name unicorn-store \
    --query 'associations[].associationId' \
    --output text) && echo $ASSOCIATIONS

# Delete each association
for ASSOCIATION_ID in $ASSOCIATIONS; do
    echo "Deleting association: $ASSOCIATION_ID"
    aws eks delete-pod-identity-association \
        --cluster-name unicorn-store \
        --association-id $ASSOCIATION_ID \
        --no-cli-pager
done
