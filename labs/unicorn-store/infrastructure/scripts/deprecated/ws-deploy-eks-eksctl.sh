#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-deploy-eks-eksctl ..." $start_time

CLUSTER_NAME=unicorn-store
APP_NAME=unicorn-store-spring

if [[ -z "${ACCOUNT_ID}" ]]; then
  export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
fi
if [[ -z "${AWS_REGION}" ]]; then
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
fi

echo Get the existing VPC and Subnet IDs to inform EKS where to create the new cluster
UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc --query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)
UNICORN_SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet1" --query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet2" --query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PUBLIC_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet1" --query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PUBLIC_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet2" --query 'Subnets[0].SubnetId' --output text)

aws ec2 create-tags --resources $UNICORN_SUBNET_PRIVATE_1 $UNICORN_SUBNET_PRIVATE_2 \
--tags Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared Key=kubernetes.io/role/internal-elb,Value=1

aws ec2 create-tags --resources $UNICORN_SUBNET_PUBLIC_1 $UNICORN_SUBNET_PUBLIC_2 \
--tags Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared Key=kubernetes.io/role/elb,Value=1

echo Create the cluster with eksctl
eksctl create cluster \
--name $CLUSTER_NAME \
--version 1.30 --region $AWS_REGION \
--nodegroup-name managed-node-group-x64 --managed --node-type m5.xlarge --nodes 2 --nodes-min 2 --nodes-max 4 \
--with-oidc --full-ecr-access --alb-ingress-access \
--vpc-private-subnets $UNICORN_SUBNET_PRIVATE_1,$UNICORN_SUBNET_PRIVATE_2 \
--vpc-public-subnets $UNICORN_SUBNET_PUBLIC_1,$UNICORN_SUBNET_PUBLIC_2

echo Add the workshop IAM roles to the list of the EKS cluster administrators to get access from the AWS Console
eksctl create iamidentitymapping --cluster $CLUSTER_NAME --region=$AWS_REGION \
    --arn arn:aws:iam::$ACCOUNT_ID:role/WSParticipantRole --username admin --group system:masters \
    --no-duplicate-arns

eksctl create iamidentitymapping --cluster $CLUSTER_NAME --region=$AWS_REGION \
    --arn arn:aws:iam::$ACCOUNT_ID:role/java-on-aws-workshop-user --username admin --group system:masters \
    --no-duplicate-arns

eksctl create iamidentitymapping --cluster $CLUSTER_NAME --region=$AWS_REGION \
    --arn arn:aws:iam::$ACCOUNT_ID:role/java-on-aws-workshop-admin --username admin --group system:masters \
    --no-duplicate-arns

echo Get access to the cluster
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
kubectl get nodes

echo Create an IAM-Policy with the proper permissions to publish to EventBridge, retrieve secrets and parameters and basic monitoring
cat <<EOF > service-account-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "xray:PutTraceSegments",
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": "events:PutEvents",
            "Resource": "arn:aws:events:$AWS_REGION:$ACCOUNT_ID:event-bus/unicorns",
            "Effect": "Allow"
        },
        {
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "$(aws cloudformation describe-stacks --stack-name UnicornStoreInfrastructure --query 'Stacks[0].Outputs[?OutputKey==`arnUnicornStoreDbSecret`].OutputValue' --output text)",
            "Effect": "Allow"
        },
        {
            "Action": [
                "ssm:DescribeParameters",
                "ssm:GetParameters",
                "ssm:GetParameter",
                "ssm:GetParameterHistory"
            ],
            "Resource": "arn:aws:ssm:$AWS_REGION:$ACCOUNT_ID:parameter/databaseJDBCConnectionString",
            "Effect": "Allow"
        }
    ]
}
EOF
aws iam create-policy --policy-name unicorn-eks-service-account-policy --policy-document file://service-account-policy.json
rm service-account-policy.json

echo Install the External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
external-secrets/external-secrets \
-n external-secrets \
--create-namespace \
--set installCRDs=true \
--set webhook.port=9443 \
--wait

if [ "$?" -ne 0 ]; then touch ~/ws-deploy-eks-eksctl.failed; else touch ~/ws-deploy-eks-eksctl.completed; fi

echo $(date '+%Y.%m.%d %H:%M:%S')

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-deploy-eks-eksctl." $start_time
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "eks" $start_time 2>&1 | tee >(cat >> ~/setup-timing.log)
