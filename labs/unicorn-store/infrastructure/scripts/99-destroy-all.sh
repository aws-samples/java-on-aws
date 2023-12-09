#bin/sh
echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started" $start_time

cd ~/environment/unicorn-store-spring
copilot app delete --yes

cd ~/environment/java-on-aws/labs/unicorn-store

for x in `aws ecr list-images --repository-name unicorn-store-spring --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-spring --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name unicorn-store-spring --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-spring --image-ids imageDigest=$x; done

flux uninstall --silent
kubectl delete deployment unicorn-store-spring -n unicorn-store-spring
kubectl delete service unicorn-store-spring -n unicorn-store-spring
kubectl delete sa unicorn-store-spring -n unicorn-store-spring
kubectl delete namespace unicorn-store-spring

pushd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/cdk
cdk destroy UnicornStoreSpringEKS --force

eksctl delete cluster --name unicorn-store

aws elbv2 delete-load-balancer --load-balancer-arn $(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`unicorn-store-spring`].LoadBalancerArn' --output text)
aws elbv2 delete-target-group --target-group-arn $(aws elbv2 describe-target-groups --query 'TargetGroups[?TargetGroupName==`unicorn-store-spring`].TargetGroupArn' --output text)

export GITOPS_USER=unicorn-store-gitops
export GITOPSC_REPO_NAME=unicorn-store-gitops
export CC_POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AWSCodeCommitPowerUser`].{ARN:Arn}' --output text)

aws iam detach-user-policy --user-name $GITOPS_USER --policy-arn $CC_POLICY_ARN
export SSC_ID=$(aws iam list-service-specific-credentials --user-name $GITOPS_USER --query 'ServiceSpecificCredentials[0].ServiceSpecificCredentialId' --output text)
aws iam delete-service-specific-credential --user-name $GITOPS_USER --service-specific-credential-id $SSC_ID
aws iam delete-user --user-name $GITOPS_USER
aws iam delete-policy --policy-arn=$(aws iam list-policies --query 'Policies[?PolicyName==`unicorn-eks-service-account-policy`].{ARN:Arn}' --output text)
aws codecommit delete-repository --repository-name $GITOPSC_REPO_NAME

cdk destroy UnicornStoreSpringECS --force
cdk destroy UnicornStoreSpringCI --force

aws cloudformation delete-stack --stack-name $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --query 'StackSummaries[?contains(StackName,`ECS-Console-V2-Service-unicorn-store-spring-unicorn-store-spring`)==`true`].StackName' --output text)
aws cloudformation delete-stack --stack-name $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --query 'StackSummaries[?contains(StackName,`Infra-ECS-Cluster-unicorn-store-spring`)==`true`].StackName' --output text)

aws apprunner delete-service --service-arn $(aws apprunner list-services --query 'ServiceSummaryList[?ServiceName==`uss-app-env-dev-uss-svc`].ServiceArn' --output text)
aws apprunner delete-vpc-connector --vpc-connector-arn $(aws apprunner list-vpc-connectors  --query "VpcConnectors[?VpcConnectorName == 'unicornstore-vpc-connector'].VpcConnectorArn" --output text)

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.privateIp')
INTERFACE_NAME=$(ip address | grep $IP | awk ' { print $10 } ')
MAC=$(ip address show dev $INTERFACE_NAME | grep ether | awk ' { print $2 } ')
export CLOUD9_VPC_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-id)

aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $(aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$CLOUD9_VPC_ID" --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text)

aws codecommit delete-repository --repository-name unicorn-store-spring
aws ecr delete-repository --repository-name unicorn-store-spring

aws codebuild delete-project --name unicorn-store-spring-build-ecr-x86_64
aws codebuild delete-project --name unicorn-store-spring-build-ecr-arm64
aws codebuild delete-project --name unicorn-store-spring-build-ecr-manifest
aws codebuild delete-project --name unicorn-store-spring-deploy-ecs

aws codepipeline delete-pipeline --name unicorn-store-spring-pipeline-build-ecr
aws codepipeline delete-pipeline --name unicorn-store-spring-deploy-ecs

aws ecs delete-service --cluster unicorn-store-spring --service unicorn-store-spring --force 1> /dev/null
aws ecs delete-cluster --cluster unicorn-store-spring 1> /dev/null

cdk destroy UnicornStoreInfrastructure --force
cdk destroy UnicornStoreVpc --force

# TODO: delete IAM roles, policies, etc.

popd

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished" $start_time
