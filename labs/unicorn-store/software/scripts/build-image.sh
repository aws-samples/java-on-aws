#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start=`date +%s`

export ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI >/dev/null 2>&1

cd ~/environment/unicorn-store-spring
docker buildx build --load -t unicorn-store-spring:latest .
IMAGE_TAG=i$(date +%Y%m%d%H%M%S)
docker tag unicorn-store-spring:latest $ECR_URI:$IMAGE_TAG
docker tag unicorn-store-spring:latest $ECR_URI:latest
docker push $ECR_URI:$IMAGE_TAG
docker push $ECR_URI:latest
