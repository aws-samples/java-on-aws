#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-deploy-apprunner ..." $start_time

echo Set required environment variables

APP_NAME=unicorn-store-spring

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

SPRING_DATASOURCE_URL=databaseJDBCConnectionString
SPRING_DATASOURCE_PASSWORD=$(aws cloudformation describe-stacks --stack-name UnicornStoreInfrastructure --query 'Stacks[0].Outputs[?OutputKey==`arnUnicornStoreDbSecretPassword`].OutputValue' --output text)
VPC_CONNECTOR_ARN=$(aws apprunner list-vpc-connectors --query 'VpcConnectors[?VpcConnectorName==`unicornstore-vpc-connector`].VpcConnectorArn' --output text)

echo Create a configuration file for an App Runner service

cat <<EOF > ~/environment/$APP_NAME/input.json
{
    "SourceConfiguration": {
        "AuthenticationConfiguration": {
            "AccessRoleArn": "arn:aws:iam::$ACCOUNT_ID:role/unicornstore-apprunner-ecr-access-role"
        },
        "AutoDeploymentsEnabled": true,
        "ImageRepository": {
            "ImageIdentifier": "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME:latest",
            "ImageConfiguration": {
                "Port": "8080",
                "RuntimeEnvironmentSecrets": {
                    "SPRING_DATASOURCE_URL": "$SPRING_DATASOURCE_URL",
                    "SPRING_DATASOURCE_PASSWORD": "$SPRING_DATASOURCE_PASSWORD"
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
        "Path": "/actuator/health"
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

echo Deploy the App Runner service

aws apprunner create-service --service-name $APP_NAME --no-cli-pager \
    --cli-input-json file://~/environment/$APP_NAME/input.json

echo Testing the application on AWS App Runner

SVC_URL=https://$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName == 'unicorn-store-spring'].ServiceUrl" --output text)
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 10; done
echo $SVC_URL
curl --location $SVC_URL; echo
curl --location --request POST $SVC_URL'/unicorns' --header 'Content-Type: application/json' --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-deploy-apprunner." $start_time
