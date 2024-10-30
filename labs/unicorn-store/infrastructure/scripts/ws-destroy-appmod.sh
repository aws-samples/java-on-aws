#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-destroy-appmod ..." $start_time

CLUSTER_NAME=unicorn-store
APP_NAME=unicorn-store-spring

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME

kubectl delete deployment $CLUSTER_NAME-wildfly -n $CLUSTER_NAME-wildfly --cascade=foreground
kubectl delete service $CLUSTER_NAME-wildfly -n $CLUSTER_NAME-wildfly
eksctl delete iamserviceaccount --cluster=$CLUSTER_NAME --name=$CLUSTER_NAME-wildfly --namespace=$CLUSTER_NAME-wildfly --region=$AWS_REGION
kubectl delete sa $CLUSTER_NAME-wildfly -n $CLUSTER_NAME-wildfly
kubectl delete namespace $CLUSTER_NAME-wildfly

kubectl delete deployment $CLUSTER_NAME-quarkus -n $CLUSTER_NAME-quarkus --cascade=foreground
kubectl delete service $CLUSTER_NAME-quarkus -n $CLUSTER_NAME-quarkus
eksctl delete iamserviceaccount --cluster=$CLUSTER_NAME --name=$CLUSTER_NAME-quarkus --namespace=$CLUSTER_NAME-quarkus --region=$AWS_REGION
kubectl delete sa $CLUSTER_NAME-quarkus -n $CLUSTER_NAME-quarkus
kubectl delete namespace $CLUSTER_NAME-quarkus

echo Deleting AppMod data ...

for x in `aws ecr list-images --repository-name $CLUSTER_NAME-wildfly --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-wildfly --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name $CLUSTER_NAME-wildfly --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-wildfly --image-ids imageDigest=$x; done
aws ecr delete-repository --repository-name $CLUSTER_NAME-wildfly --force

for x in `aws ecr list-images --repository-name $CLUSTER_NAME-quarkus --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-quarkus --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name $CLUSTER_NAME-quarkus --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-quarkus --image-ids imageDigest=$x; done
aws ecr delete-repository --repository-name $CLUSTER_NAME-quarkus --force

UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc --query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$UNICORN_VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-dbserver-sg`].GroupId' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$UNICORN_VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-appserver-sg`].GroupId' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$UNICORN_VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-webserver-sg`].GroupId' --output text)

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-destroy-appmod." $start_time
