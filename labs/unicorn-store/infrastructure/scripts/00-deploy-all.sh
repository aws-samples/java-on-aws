#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started 00-deploy-all ..." $start_time

source ~/.bashrc
# aws cloud9 update-environment  --environment-id $C9_PID --managed-credentials-action DISABLE >/dev/null 2>&1
# rm -vf ${HOME}/.aws/credentials

# RED='\033[0;31m'
# NC='\033[0m' # No Color
# aws sts get-caller-identity --query Arn | grep java-on-aws-workshop-admin -q && echo "IAM role is valid" || printf "${RED}IAM role is NOT valid. To execute the scripts please switch to java-on-aws-workshop-admin profile" && echo

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-containerize.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-deploy-apprunner.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-deploy-ecs.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-deploy-eks-eksctl-karpenter.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-deploy-eks-manifests.sh
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-deploy-gitops.sh

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished 00-deploy-all." $start_time
