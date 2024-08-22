#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')

if [[ -z "${ACCOUNT_ID}" ]]; then
  export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
  echo ACCOUNT_ID is set to $ACCOUNT_ID
else
  echo ACCOUNT_ID was set to $ACCOUNT_ID
fi

INSTANCEID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*java-on-aws-workshop*" \
  --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' \
  --output text)
while [ -z "${INSTANCEID}" ]; do
  echo Waiting for VSCodeIde to be created...
  sleep 10
  INSTANCEID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=*java-on-aws-workshop*" \
    --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' \
    --output text)
done
echo INSTANCEID=$INSTANCEID

ASSOCIATION_ID=$(aws ec2 describe-iam-instance-profile-associations --query "IamInstanceProfileAssociations[?InstanceId=='$INSTANCEID'][AssociationId]" --output text)
echo ASSOCIATION_ID=$ASSOCIATION_ID

aws ec2 replace-iam-instance-profile-association --iam-instance-profile Arn=arn:aws:iam::$ACCOUNT_ID:instance-profile/java-on-aws-workshop-user,Name=java-on-aws-workshop-user --association-id $ASSOCIATION_ID

aws ec2 describe-iam-instance-profile-associations --query "IamInstanceProfileAssociations[?InstanceId=='$INSTANCEID'].{Arn:IamInstanceProfile.Arn,State:State}" --output text
