#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-deploy-eks-eksctl-karpenter ..." $start_time

export CLUSTER_NAME=unicorn-store

# Check if script received a parameter and use it as instance type
if [ $# -ge 1 ] && [ -n "$1" ]; then
  MNG_INSTANCE_TYPE="$1"
else
  MNG_INSTANCE_TYPE="c5.large"
fi

echo "MNG_INSTANCE_TYPE is set to: $MNG_INSTANCE_TYPE"

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

stack_name="UnicornStoreVpc"

# Function to check stack status
check_stack_status() {
    stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
    if [ -z "$stack_status" ]; then
        echo "Stack $stack_name does not exist"
        return 1
    elif [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ]; then
        echo "Stack $stack_name is $stack_status"
        return 0
    else
        echo "Stack $stack_name is $stack_status"
        return 2
    fi
}

# Wait for stack to exist and complete
while true; do
    check_stack_status
    case $? in
        0) # Stack exists and is completed
            break
            ;;
        1) # Stack does not exist
            echo "Waiting for stack to be created..."
            sleep 10
            ;;
        2) # Stack exists but is not completed
            echo "Waiting for stack to complete..."
            sleep 10
            ;;
    esac
done

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

echo Create the cluster with eksctl and settings required for Karpenter
K8S_VERSION="1.31"
KARPENTER_VERSION="1.0.8"
KARPENTER_NAMESPACE="kube-system"
TEMPOUT="$(mktemp)"

curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml > ${TEMPOUT} \
&& aws cloudformation deploy \
  --stack-name "${CLUSTER_NAME}-karpenter" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

eksctl create cluster --alb-ingress-access -f - <<EOF
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${K8S_VERSION}"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}

vpc:
  subnets:
    private:
      ${AWS_REGION}a:
        id: "$UNICORN_SUBNET_PRIVATE_1"
      ${AWS_REGION}b:
        id: "$UNICORN_SUBNET_PRIVATE_2"
    public:
      ${AWS_REGION}a:
        id: "$UNICORN_SUBNET_PUBLIC_1"
      ${AWS_REGION}b:
        id: "$UNICORN_SUBNET_PUBLIC_2"

iam:
  withOIDC: true
  podIdentityAssociations:
  - namespace: "${KARPENTER_NAMESPACE}"
    serviceAccountName: karpenter
    roleName: ${CLUSTER_NAME}-karpenter
    permissionPolicyARNs:
    - arn:aws:iam::${ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}

iamIdentityMappings:
- arn: "arn:aws:iam::${ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes

managedNodeGroups:
- instanceType: ${MNG_INSTANCE_TYPE}
  name: mng-x64
  amiFamily: AmazonLinux2023
  privateNetworking: true
  desiredCapacity: 2
  minSize: 1
  maxSize: 2

addons:
- name: eks-pod-identity-agent
EOF

echo Create service linked role, tag subnets for Karpenter nodes and install Karpenter
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true
aws ec2 create-tags --resources $UNICORN_SUBNET_PRIVATE_1 $UNICORN_SUBNET_PRIVATE_2 \
--tags Key=karpenter.sh/discovery,Value=$CLUSTER_NAME

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" --namespace "${KARPENTER_NAMESPACE}" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait

echo Create Karpenter EC2NodeClass and NodePool

cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "t"]
        - key: karpenter.k8s.aws/instance-generation
          operator: In
          values: ["5", "3"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["c5.xlarge"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h # 30 * 24h = 720h
  limits:
    cpu: 20
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2023
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        aws:eks:cluster-name: "${CLUSTER_NAME}"
  amiSelectorTerms:
    - alias: al2023@latest
EOF

echo Add the workshop IAM roles to the list of the EKS cluster administrators to get access from the AWS Console
eksctl create iamidentitymapping --cluster $CLUSTER_NAME --region=$AWS_REGION \
    --arn arn:aws:iam::$ACCOUNT_ID:role/WSParticipantRole --username admin --group system:masters \
    --no-duplicate-arns

eksctl create iamidentitymapping --cluster $CLUSTER_NAME --region=$AWS_REGION \
    --arn arn:aws:iam::$ACCOUNT_ID:role/java-on-aws-workshop-user --username admin --group system:masters \
    --no-duplicate-arns

# eksctl create iamidentitymapping --cluster $CLUSTER_NAME --region=$AWS_REGION \
#     --arn arn:aws:iam::$ACCOUNT_ID:role/java-on-aws-workshop-admin --username admin --group system:masters \
#     --no-duplicate-arns

echo Get access to the cluster
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
kubectl get nodes

# DB_SECRET_ARN=$(aws secretsmanager list-secrets --query 'SecretList[?Name==`unicornstore-db-secret`].ARN' --output text)
# while [ -z "${DB_SECRET_ARN}" ]; do
#   echo Waiting for DB_SECRET_ARN to be created...
#   sleep 10
#   DB_SECRET_ARN=$(aws secretsmanager list-secrets --query 'SecretList[?Name==`unicornstore-db-secret`].ARN' --output text)
# done

# echo Create an IAM-Policy with the proper permissions to publish to EventBridge, retrieve secrets and parameters and basic monitoring
# cat <<EOF > service-account-policy.json
# {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Action": "xray:PutTraceSegments",
#             "Resource": "*",
#             "Effect": "Allow"
#         },
#         {
#             "Action": "events:PutEvents",
#             "Resource": "arn:aws:events:$AWS_REGION:$ACCOUNT_ID:event-bus/unicorns",
#             "Effect": "Allow"
#         },
#         {
#             "Action": [
#                 "secretsmanager:GetSecretValue",
#                 "secretsmanager:DescribeSecret"
#             ],
#             "Resource": "$DB_SECRET_ARN",
#             "Effect": "Allow"
#         },
#         {
#             "Action": [
#                 "ssm:DescribeParameters",
#                 "ssm:GetParameters",
#                 "ssm:GetParameter",
#                 "ssm:GetParameterHistory"
#             ],
#             "Resource": "arn:aws:ssm:$AWS_REGION:$ACCOUNT_ID:parameter/databaseJDBCConnectionString",
#             "Effect": "Allow"
#         }
#     ]
# }
# EOF
# aws iam create-policy --policy-name unicorn-eks-service-account-policy --policy-document file://service-account-policy.json
# rm service-account-policy.json

echo Install the External Secrets Operator

aws eks create-pod-identity-association --cluster-name $CLUSTER_NAME \
  --namespace external-secrets --service-account external-secrets \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/unicornstore-eks-eso-role

sleep 10

helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --wait

cat <<EOF | envsubst | kubectl create -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: unicorn-store
spec:
  provider:
    aws:
      service: SecretsManager
      region: $AWS_REGION
      role: arn:aws:iam::$ACCOUNT_ID:role/unicornstore-eks-eso-sm-role
EOF

echo Get access to the cluster
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
kubectl get ns
kubectl get all -A
kubectl get ClusterSecretStore unicorn-store

if [ "$?" -ne 0 ]; then touch ~/ws-deploy-eks-eksctl.failed; else touch ~/ws-deploy-eks-eksctl.completed; fi

echo $(date '+%Y.%m.%d %H:%M:%S')

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-deploy-eks-eksctl-karpenter." $start_time
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "eks" $start_time 2>&1 | tee >(cat >> ~/setup-timing.log)
