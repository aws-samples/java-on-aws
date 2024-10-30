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

# echo Deleting GitOps setup ...

# flux uninstall --silent

# GITOPS_USER=$CLUSTER_NAME-gitops
# GITOPSC_REPO_NAME=$CLUSTER_NAME-gitops

# SSC_ID=$(aws iam list-service-specific-credentials --user-name $GITOPS_USER --query 'ServiceSpecificCredentials[0].ServiceSpecificCredentialId' --output text)
# aws iam delete-service-specific-credential --user-name $GITOPS_USER --service-specific-credential-id $SSC_ID
# aws codecommit delete-repository --repository-name $GITOPSC_REPO_NAME

echo Deleting EKS cluster ...

kubectl delete deployment $APP_NAME -n $APP_NAME --cascade=foreground
kubectl delete service $APP_NAME -n $APP_NAME
eksctl delete iamserviceaccount --cluster=$CLUSTER_NAME --name=$APP_NAME --namespace=$APP_NAME --region=$AWS_REGION
kubectl delete sa $APP_NAME -n $APP_NAME
kubectl delete namespace $APP_NAME

kubectl delete nodeclaims --all

helm uninstall karpenter --namespace kube-system
helm uninstall external-secrets --namespace external-secrets

eksctl delete cluster --name $CLUSTER_NAME

aws iam delete-policy --policy-arn=$(aws iam list-policies --query 'Policies[?PolicyName==`unicorn-eks-service-account-policy`].{ARN:Arn}' --output text)
aws iam remove-role-from-instance-profile --instance-profile-name $(aws iam list-instance-profiles --query 'InstanceProfiles[?starts_with(InstanceProfileName, `unicorn-store`)].InstanceProfileName' --output text) --role-name KarpenterNodeRole-unicorn-store
aws iam delete-role --role-name KarpenterNodeRole-unicorn-store
aws cloudformation delete-stack --stack-name unicorn-store-karpenter

aws cloudformation delete-stack --stack-name eksctl-$CLUSTER_NAME-cluster && \
while aws cloudformation describe-stacks --stack-name eksctl-$CLUSTER_NAME-cluster >/dev/null 2>&1; do
    echo "Waiting for stack eksctl-$CLUSTER_NAME-cluster to be deleted..."
    sleep 30
done && echo "Stack eksctl-$CLUSTER_NAME-cluster has been deleted."

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-destroy-eks." $start_time
