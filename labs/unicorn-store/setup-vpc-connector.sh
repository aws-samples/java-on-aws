#bin/sh

aws apprunner delete-vpc-connector --vpc-connector-arn $(aws apprunner list-vpc-connectors  --query "VpcConnectors[?VpcConnectorName == 'unicornstore-vpc-connector'].VpcConnectorArn" --output text) 2>/dev/null

export UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc \
--query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)

export UNICORN_SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet1" \
--query 'Subnets[0].SubnetId' --output text)

export UNICORN_SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet2" \
--query 'Subnets[0].SubnetId' --output text)

aws apprunner create-vpc-connector --vpc-connector-name unicornstore-vpc-connector \
--subnets $UNICORN_SUBNET_PRIVATE_1 $UNICORN_SUBNET_PRIVATE_2
