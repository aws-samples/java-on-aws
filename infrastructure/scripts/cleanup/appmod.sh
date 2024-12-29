CLUSTER_NAME=unicorn-store
APP_NAME=unicorn-store-spring

aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME

kubectl delete ingress $CLUSTER_NAME-wildfly -n $CLUSTER_NAME-wildfly
kubectl delete service $CLUSTER_NAME-wildfly -n $CLUSTER_NAME-wildfly
kubectl delete deployment $CLUSTER_NAME-wildfly -n $CLUSTER_NAME-wildfly --cascade=foreground
kubectl delete sa $CLUSTER_NAME-wildfly -n $CLUSTER_NAME-wildfly
kubectl delete namespace $CLUSTER_NAME-wildfly

kubectl delete ingress $CLUSTER_NAME-quarkus -n $CLUSTER_NAME-quarkus
kubectl delete service $CLUSTER_NAME-quarkus -n $CLUSTER_NAME-quarkus
kubectl delete deployment $CLUSTER_NAME-quarkus -n $CLUSTER_NAME-quarkus --cascade=foreground
kubectl delete sa $CLUSTER_NAME-quarkus -n $CLUSTER_NAME-quarkus
kubectl delete namespace $CLUSTER_NAME-quarkus

echo Deleting AppMod data ...

for x in `aws ecr list-images --repository-name $CLUSTER_NAME-wildfly --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-wildfly --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name $CLUSTER_NAME-wildfly --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-wildfly --image-ids imageDigest=$x; done
aws ecr delete-repository --repository-name $CLUSTER_NAME-wildfly --force

for x in `aws ecr list-images --repository-name $CLUSTER_NAME-quarkus --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-quarkus --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name $CLUSTER_NAME-quarkus --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-quarkus --image-ids imageDigest=$x; done
aws ecr delete-repository --repository-name $CLUSTER_NAME-quarkus --force
