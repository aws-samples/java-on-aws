#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-destroy-eks ..." $start_time

CLUSTER_NAME=unicorn-store
APP_NAME=unicorn-store-spring

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME

echo Deleting GitOps setup ...

flux uninstall --silent

GITOPS_USER=$CLUSTER_NAME-gitops
GITOPSC_REPO_NAME=$CLUSTER_NAME-gitops

SSC_ID=$(aws iam list-service-specific-credentials --user-name $GITOPS_USER --query 'ServiceSpecificCredentials[0].ServiceSpecificCredentialId' --output text)
aws iam delete-service-specific-credential --user-name $GITOPS_USER --service-specific-credential-id $SSC_ID
aws codecommit delete-repository --repository-name $GITOPSC_REPO_NAME

echo Deleting EKS cluster ...

kubectl delete deployment $APP_NAME -n $APP_NAME --cascade=foreground
kubectl delete service $APP_NAME -n $APP_NAME
eksctl delete iamserviceaccount --cluster=$CLUSTER_NAME --name=$APP_NAME --namespace=$APP_NAME --region=$AWS_REGION
kubectl delete sa $APP_NAME -n $APP_NAME
kubectl delete namespace $APP_NAME

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

# pushd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/cdk
# cdk destroy UnicornStoreSpringEKS --force
# popd

kubectl delete nodeclaims --all

helm uninstall karpenter --namespace kube-system
helm uninstall external-secrets --namespace external-secrets

eksctl delete cluster --name $CLUSTER_NAME

aws iam delete-policy --policy-arn=$(aws iam list-policies --query 'Policies[?PolicyName==`unicorn-eks-service-account-policy`].{ARN:Arn}' --output text)
aws iam remove-role-from-instance-profile --instance-profile-name $(aws iam list-instance-profiles --query 'InstanceProfiles[?starts_with(InstanceProfileName, `unicorn-store`)].InstanceProfileName' --output text) --role-name KarpenterNodeRole-unicorn-store
aws iam delete-role --role-name KarpenterNodeRole-unicorn-store
aws cloudformation delete-stack --stack-name unicorn-store-karpenter

echo Deleting AppMod data ...

for x in `aws ecr list-images --repository-name unicorn-store-wildfly --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-wildfly --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name unicorn-store-wildfly --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-wildfly --image-ids imageDigest=$x; done
aws ecr delete-repository --repository-name unicorn-store-wildfly

for x in `aws ecr list-images --repository-name unicorn-store-quarkus --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-quarkus --image-ids imageDigest=$x; done
for x in `aws ecr list-images --repository-name unicorn-store-quarkus --query 'imageIds[*][imageDigest]' --output text`; do aws ecr batch-delete-image --repository-name unicorn-store-quarkus --image-ids imageDigest=$x; done
aws ecr delete-repository --repository-name unicorn-store-quarkus

aws codecommit delete-repository --repository-name unicorn-store-jakarta

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-destroy-eks." $start_time
