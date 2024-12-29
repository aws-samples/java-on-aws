APP_NAME=unicorn-store-spring

echo Deleting EC2 for Spring app ...

INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*unicorn-store" --query "Reservations[*].Instances[*].InstanceId" --output text)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

aws codeartifact delete-repository --domain unicorn --repository unicorn
aws codeartifact delete-domain --domain unicorn

echo Deleting EC2s for Jakarta app ...

INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*rehost-webserver-instance" --query "Reservations[*].Instances[*].InstanceId" --output text)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*rehost-appserver-instance" --query "Reservations[*].Instances[*].InstanceId" --output text)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*rehost-dbserver-instance" --query "Reservations[*].Instances[*].InstanceId" --output text)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

sleep 60

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query 'Vpcs[0].VpcId' --output text) && echo $VPC_ID

aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-dbserver-sg`].GroupId' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-appserver-sg`].GroupId' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-webserver-sg`].GroupId' --output text)
