#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-deploy-eks-eksctl-karpenter ..." $start_time

CLUSTER_NAME=unicorn-store
APP_NAME=unicorn-store-spring

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

# Disable Temporary credentials in Cloud9
aws cloud9 update-environment --environment-id $C9_PID --managed-credentials-action DISABLE --region $AWS_REGION &> /dev/null
rm -vf ${HOME}/.aws/credentials  &> /dev/null

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
K8S_VERSION="1.30"
KARPENTER_VERSION="0.37.0"
KARPENTER_NAMESPACE="kube-system"
TEMPOUT="$(mktemp)"

curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml  > "${TEMPOUT}" \
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
- instanceType: c5.large
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
--tags Key=karpenter.sh/discovery,Value=unicorn-store

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
apiVersion: karpenter.sh/v1beta1
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
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
  limits:
    cpu: 20
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h # 30 * 24h = 720h
---
apiVersion: karpenter.k8s.aws/v1beta1
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
EOF

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

if [ "$?" -ne 0 ]; then touch /home/ec2-user/ws-deploy-eks-eksctl.failed; else touch /home/ec2-user/ws-deploy-eks-eksctl.completed; fi

echo $(date '+%Y.%m.%d %H:%M:%S')

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-deploy-eks-eksctl-karpenter." $start_time
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "eks" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)
