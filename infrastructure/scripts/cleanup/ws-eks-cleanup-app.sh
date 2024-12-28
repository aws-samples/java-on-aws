set -e

APP_NAME=${1:-"unicorn-store-spring"}

echo Cleaning up $APP_NAME ...

docker images --format "{{.Repository}}:{{.Tag}}" | grep $APP_NAME | xargs -r docker rmi
for x in `aws ecr list-images --repository-name $APP_NAME --query 'imageIds[*][imageDigest]' --output text`; do \
    aws ecr batch-delete-image --repository-name $APP_NAME --image-ids imageDigest=$x >/dev/null; done
for x in `aws ecr list-images --repository-name $APP_NAME --query 'imageIds[*][imageDigest]' --output text`; do \
    aws ecr batch-delete-image --repository-name $APP_NAME --image-ids imageDigest=$x >/dev/null; done

if [ -d ~/environment/$APP_NAME/k8s ]; then
    kubectl delete -f ~/environment/$APP_NAME/k8s
    rm -rf ~/environment/$APP_NAME/k8s
fi

echo "App cleanup is complete."
