#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')

if [[ -z "${ACCOUNT_ID}" ]]; then
  export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
  echo ACCOUNT_ID is set to $ACCOUNT_ID
else
  echo ACCOUNT_ID was set to $ACCOUNT_ID
fi
if [[ -z "${AWS_REGION}" ]]; then
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
  echo AWS_REGION is set to $AWS_REGION
else
  echo AWS_REGION was set to $AWS_REGION
fi

UNICORN_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*UnicornVPC*" --query "Vpcs[*].VpcId" --output text)
while [ -z "${UNICORN_VPC_ID}" ]; do
  echo Waiting for UnicornVPC to be created...
  sleep 10
  UNICORN_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*UnicornVPC*" --query "Vpcs[*].VpcId" --output text)
done

IDE_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*IdeVPC*" --query "Vpcs[*].VpcId" --output text)
while [ -z "${IDE_VPC_ID}" ]; do
  echo Waiting for IdeVPC to be created...
  sleep 10
  IDE_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*IdeVPC*" --query "Vpcs[*].VpcId" --output text)
done

echo UNICORN_VPC_ID = $UNICORN_VPC_ID
echo IDE_VPC_ID = $IDE_VPC_ID

VPC_PEERING_ID=$(aws ec2 create-vpc-peering-connection --vpc-id $IDE_VPC_ID \
--peer-vpc-id $UNICORN_VPC_ID \
--query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)

sleep 10

aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $VPC_PEERING_ID --output text

IDE_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
--filters "Name=vpc-id,Values=$IDE_VPC_ID" "Name=tag:Name,Values=*java-on-aws-workshop*" \
--query 'RouteTables[0].RouteTableId' --output text)

UNICORN_DB_ROUTE_TABLE_ID_1=$(aws ec2 describe-route-tables \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet1" \
--query 'RouteTables[0].RouteTableId' --output text)
UNICORN_DB_ROUTE_TABLE_ID_2=$(aws ec2 describe-route-tables \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet2" \
--query 'RouteTables[0].RouteTableId' --output text)

aws ec2 create-route --route-table-id $IDE_ROUTE_TABLE_ID \
--destination-cidr-block 10.0.0.0/16 --vpc-peering-connection-id $VPC_PEERING_ID

aws ec2 create-route --route-table-id $UNICORN_DB_ROUTE_TABLE_ID_1 \
--destination-cidr-block 192.168.0.0/16 --vpc-peering-connection-id $VPC_PEERING_ID
aws ec2 create-route --route-table-id $UNICORN_DB_ROUTE_TABLE_ID_2 \
--destination-cidr-block 192.168.0.0/16 --vpc-peering-connection-id $VPC_PEERING_ID
