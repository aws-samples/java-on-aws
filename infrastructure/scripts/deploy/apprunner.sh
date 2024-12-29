set -e

APP_NAME=${1:-"unicorn-store-spring"}
PROJECT_NAME=${2:-"unicorn-store"}

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query 'Vpcs[0].VpcId' --output text) && echo $VPC_ID
SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*PrivateSubnet1" \
  --query 'Subnets[0].SubnetId' --output text) && echo $SUBNET_PRIVATE_1
SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*PrivateSubnet2" \
  --query 'Subnets[0].SubnetId' --output text) && echo $SUBNET_PRIVATE_2
# aws apprunner create-vpc-connector --vpc-connector-name unicornstore-vpc-connector \
#   --subnets $SUBNET_PRIVATE_1 $SUBNET_PRIVATE_2 --no-cli-pager

UNICORNSTORE_DB_CONNECTION_STRING_ARN=$(aws ssm get-parameter --name "unicornstore-db-connection-string" \
  --query 'Parameter.ARN' --output text) && echo $UNICORNSTORE_DB_CONNECTION_STRING_ARN
UNICORNSTORE_DB_PASSWORD_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id unicornstore-db-password-secret \
    --query 'ARN' --output text) && echo $UNICORNSTORE_DB_PASSWORD_SECRET_ARN
VPC_CONNECTOR_ARN=$(aws apprunner list-vpc-connectors \
--query 'VpcConnectors[?VpcConnectorName==`unicornstore-vpc-connector`].VpcConnectorArn' --output text) && echo $VPC_CONNECTOR_ARN

cat <<EOF > ~/environment/unicorn-store-spring/input.json
{
    "SourceConfiguration": {
        "AuthenticationConfiguration": {
            "AccessRoleArn": "arn:aws:iam::$ACCOUNT_ID:role/unicornstore-apprunner-ecr-access-role"
        },
        "AutoDeploymentsEnabled": true,
        "ImageRepository": {
            "ImageIdentifier": "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/unicorn-store-spring:latest",
            "ImageConfiguration": {
                "Port": "8080",
                "RuntimeEnvironmentSecrets": {
                    "SPRING_DATASOURCE_URL": "$UNICORNSTORE_DB_CONNECTION_STRING_ARN",
                    "SPRING_DATASOURCE_PASSWORD": "$UNICORNSTORE_DB_PASSWORD_SECRET_ARN"
                }
            },
            "ImageRepositoryType": "ECR"
        }
    },
    "InstanceConfiguration": {
        "Cpu": "1 vCPU",
        "Memory": "2 GB",
        "InstanceRoleArn": "arn:aws:iam::$ACCOUNT_ID:role/unicornstore-apprunner-role"
    },
    "HealthCheckConfiguration": {
        "Protocol": "HTTP",
        "Path": "/"
    },
    "NetworkConfiguration": {
        "EgressConfiguration": {
            "EgressType": "VPC",
            "VpcConnectorArn": "$VPC_CONNECTOR_ARN"
        },
        "IngressConfiguration": {
            "IsPubliclyAccessible": true
        }
    }
}
EOF

aws apprunner create-service --service-name unicorn-store-spring --no-cli-pager \
    --cli-input-json file://~/environment/unicorn-store-spring/input.json
rm ~/environment/unicorn-store-spring/input.json

SVC_URL=https://$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName == 'unicorn-store-spring'].ServiceUrl" --output text)
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 10; done
echo $SVC_URL

echo $SVC_URL
curl --location $SVC_URL; echo
curl --location --request POST $SVC_URL'/unicorns' --header 'Content-Type: application/json' --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq

echo "App deployment to App Runner service is complete."
