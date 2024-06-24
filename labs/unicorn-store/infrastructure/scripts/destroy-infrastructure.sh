#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started destroy-infrastructure ..." $start_time

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc --query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)

IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.privateIp')

# Check if we're on AL2 or AL2023
STR=$(cat /etc/os-release)
SUB2="VERSION_ID=\"2\""
SUB2023="VERSION_ID=\"2023\""
if [[ "$STR" == *"$SUB2"* ]]
    then
        INTERFACE_NAME=$(ip address | grep $IP | awk ' { print $8 } ')
    else
        INTERFACE_NAME=$(ip address | grep $IP | awk ' { print $10 } ')
fi

MAC=$(ip address show dev $INTERFACE_NAME | grep ether | awk ' { print $2 } ')
IDE_VPC_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-id)

echo Deleteing vpc peering
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $(aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$IDE_VPC_ID" --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text)

echo Deleting ECR images ...
for x in `aws ecr list-images --repository-name unicorn-store-spring --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-spring --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name unicorn-store-spring --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-spring --image-ids imageDigest=$x; done
aws ecr delete-repository --repository-name unicorn-store-spring

aws codecommit delete-repository --repository-name unicorn-store-spring

echo Deleting core infrastructure ...

pushd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/cdk
cdk destroy UnicornStoreInfrastructure --force
cdk destroy UnicornStoreVpc --force
popd

# TODO: delete IAM roles, policies, etc.

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished destroy-infrastructure." $start_time
