#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')

export C9ID=$(aws cloud9 list-environments --query 'environmentIds[0]' --output text)
echo C9ID=$C9ID
# aws cloud9 update-environment  --environment-id $C9ID --managed-credentials-action DISABLE
# rm -vf ${HOME}/.aws/credentials
# aws sts get-caller-identity --query Arn | grep java-on-aws-workshop-admin -q && echo "IAM role is valid" || echo "IAM role is NOT valid"
