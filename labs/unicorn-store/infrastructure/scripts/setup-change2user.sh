#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export INSTANCEID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.instanceId')
echo INSTANCEID=$INSTANCEID

aws ec2 describe-iam-instance-profile-associations --query "IamInstanceProfileAssociations[?InstanceId=='$INSTANCEID'][IamInstanceProfile.Arn]" --output text
export ASSOCIATION_ID=$(aws ec2 describe-iam-instance-profile-associations --query "IamInstanceProfileAssociations[?InstanceId=='$INSTANCEID'][AssociationId]" --output text)
echo ASSOCIATION_ID=$ASSOCIATION_ID

# aws ec2 disassociate-iam-instance-profile --association-id $ASSOCIATION_ID
# aws ec2 associate-iam-instance-profile --iam-instance-profile Arn=arn:aws:iam::$ACCOUNT_ID:instance-profile/java-on-aws-workshop-user,Name=java-on-aws-workshop-user --instance-id $INSTANCEID

aws ec2 replace-iam-instance-profile-association --iam-instance-profile Arn=arn:aws:iam::$ACCOUNT_ID:instance-profile/java-on-aws-workshop-user,Name=java-on-aws-workshop-user --association-id $ASSOCIATION_ID

aws ec2 describe-iam-instance-profile-associations --query "IamInstanceProfileAssociations[?InstanceId=='$INSTANCEID'][IamInstanceProfile.Arn]" --output text

# export C9ID=$(aws cloud9 list-environments --query 'environmentIds[0]' --output text)
# echo C9ID=$C9ID
# aws cloud9 update-environment  --environment-id $C9ID --managed-credentials-action DISABLE
# rm -vf ${HOME}/.aws/credentials
# aws sts get-caller-identity --query Arn | grep java-on-aws-workshop-admin -q && echo "IAM role is valid" || echo "IAM role is NOT valid"
