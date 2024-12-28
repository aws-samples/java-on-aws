set -e

APP_NAME=${1:-"unicorn-store-spring"}

cd ~/environment/$APP_NAME
docker build -t $APP_NAME:latest .

ECR_URI=$(aws ecr describe-repositories --repository-names $APP_NAME | jq --raw-output '.repositories[0].repositoryUri')
echo $ECR_URI
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

IMAGE_TAG=i$(date +%Y%m%d%H%M%S)
echo $IMAGE_TAG
docker tag $APP_NAME:latest $ECR_URI:$IMAGE_TAG
docker tag $APP_NAME:latest $ECR_URI:latest
docker images

docker push $ECR_URI:$IMAGE_TAG
docker push $ECR_URI:latest
