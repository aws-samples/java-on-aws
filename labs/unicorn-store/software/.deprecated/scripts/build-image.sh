#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start=`date +%s`

export ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI >/dev/null 2>&1

cd ~/environment/unicorn-store-spring
sed -i '/.*Welcome to the Unicorn Store.*/c\        return new ResponseEntity<>("Welcome to the Unicorn Store !", HttpStatus.OK);' ~/environment/unicorn-store-spring/src/main/java/com/unicorn/store/controller/UnicornController.java

mvn clean package

cp dockerfiles/Dockerfile_01_original Dockerfile
docker buildx build --load -t unicorn-store-spring:latest .

IMAGE_TAG=i$(date +%Y%m%d%H%M%S)
docker tag unicorn-store-spring:latest $ECR_URI:$IMAGE_TAG
docker tag unicorn-store-spring:latest $ECR_URI:latest
docker push $ECR_URI:$IMAGE_TAG
docker push $ECR_URI:latest

cp dockerfiles/Dockerfile_02_multistage Dockerfile
docker buildx build --load -t unicorn-store-spring:latest .

cp dockerfiles/Dockerfile_01_original Dockerfile
sed -i '/.*Welcome to the Unicorn Store.*/c\        return new ResponseEntity<>("Welcome to the Unicorn Store!", HttpStatus.OK);' ~/environment/unicorn-store-spring/src/main/java/com/unicorn/store/controller/UnicornController.java

docker rmi -f $(docker images "*/unicorn-store-spring*" -q)
docker rmi -f $(docker images "unicorn-store-spring" -q)
docker rmi -f $(docker images -f "dangling=true" -q)

mvn clean
