#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-destroy-ec2 ..." $start_time

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

UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc --query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$UNICORN_VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-dbserver-sg`].GroupId' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$UNICORN_VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-appserver-sg`].GroupId' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$UNICORN_VPC_ID'" --query 'SecurityGroups[?GroupName==`rehost-webserver-sg`].GroupId' --output text)

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-destroy-ec2." $start_time
