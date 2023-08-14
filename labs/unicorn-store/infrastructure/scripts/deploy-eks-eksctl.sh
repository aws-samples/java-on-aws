#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')

# Build an image
export ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

cd ~/environment/unicorn-store-spring
docker buildx build --load -t unicorn-store-spring:latest .
IMAGE_TAG=i$(date +%Y%m%d%H%M%S)
docker tag unicorn-store-spring:latest $ECR_URI:$IMAGE_TAG
docker tag unicorn-store-spring:latest $ECR_URI:latest
docker push $ECR_URI:$IMAGE_TAG
docker push $ECR_URI:latest

# define VPC
export UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc --query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)
export UNICORN_SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet1" --query 'Subnets[0].SubnetId' --output text)
export UNICORN_SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet2" --query 'Subnets[0].SubnetId' --output text)
export UNICORN_SUBNET_PUBLIC_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet1" --query 'Subnets[0].SubnetId' --output text)
export UNICORN_SUBNET_PUBLIC_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet2" --query 'Subnets[0].SubnetId' --output text)

# create EKS cluster
eksctl create cluster \
--name unicorn-store-spring \
--version 1.27 --region $AWS_REGION \
--nodegroup-name managed-node-group-x64 --managed --node-type m5.large --nodes 2 --nodes-min 2 --nodes-max 4 \
--with-oidc --full-ecr-access --alb-ingress-access \
--vpc-private-subnets $UNICORN_SUBNET_PRIVATE_1,$UNICORN_SUBNET_PRIVATE_2 \
--vpc-public-subnets $UNICORN_SUBNET_PUBLIC_1,$UNICORN_SUBNET_PUBLIC_2

# add our IAM role to the list of administrators in EKS cluster to get access to the cluster from AWS Console.
eksctl create iamidentitymapping --cluster unicorn-store-spring --region=$AWS_REGION \
    --arn arn:aws:iam::$ACCOUNT_ID:role/WSParticipantRole --username admin --group system:masters \
    --no-duplicate-arns

# Create IAM Policy and a Service Account
kubectl create namespace unicorn-store-spring

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

eksctl create iamserviceaccount --cluster=unicorn-store-spring --name=unicorn-store-spring --namespace=unicorn-store-spring \
--attach-policy-arn=$(aws iam list-policies --query 'Policies[?PolicyName==`unicorn-eks-service-account-policy`].Arn' --output text) --approve --region=$AWS_REGION

# use External Secrets and install it via Helm
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
external-secrets/external-secrets \
-n external-secrets \
--create-namespace \
--set installCRDs=true \
--set webhook.port=9443 \
--wait

cat <<EOF | envsubst | kubectl create -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: unicorn-store-spring-secret-store
  namespace: unicorn-store-spring
spec:
  provider:
    aws:
      service: SecretsManager
      region: $AWS_REGION
      auth:
        jwt:
          serviceAccountRef:
            name: unicorn-store-spring
EOF

cat <<EOF | kubectl create -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: unicorn-store-spring-external-secret
  namespace: unicorn-store-spring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: unicorn-store-spring-secret-store
    kind: SecretStore
  target:
    name: unicornstore-db-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: unicornstore-db-secret
        property: password
EOF
