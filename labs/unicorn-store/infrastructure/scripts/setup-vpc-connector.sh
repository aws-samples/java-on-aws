#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')

aws apprunner delete-vpc-connector --vpc-connector-arn $(aws apprunner list-vpc-connectors  --query "VpcConnectors[?VpcConnectorName == 'unicornstore-vpc-connector'].VpcConnectorArn" --output text) 2>/dev/null

UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc \
--query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)
UNICORN_SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet1" \
--query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet2" \
--query 'Subnets[0].SubnetId' --output text)

aws apprunner create-vpc-connector --vpc-connector-name unicornstore-vpc-connector \
--subnets $UNICORN_SUBNET_PRIVATE_1 $UNICORN_SUBNET_PRIVATE_2 --no-cli-pager

# CONNECTOR_ARN=$(aws apprunner list-vpc-connectors  --query "VpcConnectors[?VpcConnectorName == 'unicornstore-vpc-connector'].VpcConnectorArn" --output text)

# cat > hello-app-runner-source.json <<EOF
# {
#     "ImageRepository": {
#         "ImageIdentifier": "public.ecr.aws/aws-containers/hello-app-runner:latest",
#         "ImageConfiguration": {
#             "Port": "8000"
#         },
#         "ImageRepositoryType": "ECR_PUBLIC"
#     },
#     "AutoDeploymentsEnabled": false
# }
# EOF

# cat > hello-app-runner-network.json <<EOF
# {
#   "EgressConfiguration": {
#     "EgressType": "VPC",
#     "VpcConnectorArn": "$CONNECTOR_ARN"
#   },
#   "IngressConfiguration": {
#     "IsPubliclyAccessible": true
#   },
#   "IpAddressType": "IPV4"
# }
# EOF

# aws apprunner create-service --service-name hello-app-runner \
#     --source-configuration file://hello-app-runner-source.json \
#     --network-configuration file://hello-app-runner-network.json \
#     --no-cli-pager
