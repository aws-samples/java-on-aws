#bin/sh

echo Clean up
docker images --format "{{.Repository}}:{{.Tag}}" | grep unicorn-store-spring | xargs -r docker rmi
for x in `aws ecr list-images --repository-name unicorn-store-spring --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-spring --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name unicorn-store-spring --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-spring --image-ids imageDigest=$x; done
kubectl scale deployment unicorn-store-spring -n unicorn-store-spring --replicas=0
