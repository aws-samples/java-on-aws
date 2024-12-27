CLUSTER_NAME=unicorn-store
APP_NAME=unicorn-store-spring

aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME

echo Deleting EKS $APP_NAME ...

kubectl delete ingress $APP_NAME -n $APP_NAME
kubectl delete service $APP_NAME -n $APP_NAME
kubectl delete deployment $APP_NAME -n $APP_NAME --cascade=foreground
kubectl delete sa $APP_NAME -n $APP_NAME
kubectl delete namespace $APP_NAME
