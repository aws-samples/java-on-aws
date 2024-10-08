#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start=`date +%s`

if [[ -z "${ACCOUNT_ID}" ]]; then
  export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
  echo ACCOUNT_ID is set to $ACCOUNT_ID
else
  echo ACCOUNT_ID was set to $ACCOUNT_ID
fi
if [[ -z "${AWS_REGION}" ]]; then
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
  echo AWS_REGION is set to $AWS_REGION
else
  echo AWS_REGION was set to $AWS_REGION
fi

cd ~/environment/unicorn-store-spring
sed -i '/.*Welcome to the Unicorn Store*/c\        return new ResponseEntity<>("Welcome to the Unicorn Store!", HttpStatus.OK);' ~/environment/unicorn-store-spring/src/main/java/com/unicorn/store/controller/UnicornController.java
mvn clean package && mv target/store-spring-1.0.0-exec.jar store-spring.jar

cp dockerfiles/Dockerfile_02_multistage Dockerfile
docker build -t unicorn-store-spring:latest .

ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
echo $ECR_URI
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

IMAGE_TAG=i$(date +%Y%m%d%H%M%S)
echo $IMAGE_TAG
docker tag unicorn-store-spring:latest $ECR_URI:$IMAGE_TAG
docker tag unicorn-store-spring:latest $ECR_URI:latest
docker images

docker push $ECR_URI:$IMAGE_TAG
docker push $ECR_URI:latest
