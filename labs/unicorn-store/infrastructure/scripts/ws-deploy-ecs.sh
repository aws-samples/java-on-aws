#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-deploy-ecs ..." $start_time

echo Set required environment variables

APP_NAME=unicorn-store-spring

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

SPRING_DATASOURCE_PASSWORD=$(aws cloudformation describe-stacks --stack-name UnicornStoreInfrastructure --query 'Stacks[0].Outputs[?OutputKey==`arnUnicornStoreDbSecretPassword`].OutputValue' --output text)

echo Creating ECS Task definition

cat <<EOF > ~/environment/$APP_NAME/esc-container-definitions.json
[
    {
        "name": "$APP_NAME",
        "image": "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME:latest",
        "portMappings": [
            {
                "name": "$APP_NAME-8080-tcp",
                "containerPort": 8080,
                "hostPort": 8080,
                "protocol": "tcp",
                "appProtocol": "http"
            }
        ],
        "essential": true,
        "secrets": [
            {
                "name": "SPRING_DATASOURCE_URL",
                "valueFrom": "arn:aws:ssm:$AWS_REGION:$ACCOUNT_ID:parameter/databaseJDBCConnectionString"
            },
            {
                "name": "SPRING_DATASOURCE_PASSWORD",
                "valueFrom": "$SPRING_DATASOURCE_PASSWORD"
            }
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/$APP_NAME",
                "awslogs-create-group": "true",
                "awslogs-region": "$AWS_REGION",
                "awslogs-stream-prefix": "ecs"
            }
        }
    }
]
EOF

aws ecs register-task-definition --family $APP_NAME --no-cli-pager \
    --requires-compatibilities FARGATE --network-mode awsvpc \
    --cpu 1024 --memory 2048 \
    --task-role-arn arn:aws:iam::$ACCOUNT_ID:role/unicornstore-ecs-task-role \
    --execution-role-arn arn:aws:iam::$ACCOUNT_ID:role/unicornstore-ecs-task-execution-role \
    --container-definitions file://~/environment/$APP_NAME/esc-container-definitions.json \
    --runtime-platform '{"cpuArchitecture":"X86_64","operatingSystemFamily":"LINUX"}'
    
echo Create ECS cluster    

aws ecs create-cluster --cluster-name $APP_NAME --capacity-providers FARGATE --no-cli-pager

echo Create Networking configuration

UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc --query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)
UNICORN_SUBNET_PUBLIC_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet1" --query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PUBLIC_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet2" --query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet1" --query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet2" --query 'Subnets[0].SubnetId' --output text)

echo Create a security group for an Application Load Balancer to allow access to port 80 from the Internet

aws ec2 create-security-group \
  --group-name $APP_NAME-ecs-sg-alb \
  --description "Security group for $APP_NAME ALB" \
  --vpc-id $UNICORN_VPC_ID
SECURITY_GROUP_ALB_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$UNICORN_VPC_ID'" --query 'SecurityGroups[?GroupName==`'$APP_NAME-ecs-sg-alb'`].GroupId' --output text)
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ALB_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

echo Create an Application Load Balancer

aws elbv2 create-load-balancer --no-cli-pager \
  --name $APP_NAME \
  --subnets $UNICORN_SUBNET_PUBLIC_1 $UNICORN_SUBNET_PUBLIC_2 \
  --security-groups $SECURITY_GROUP_ALB_ID

echo Create a Target Group

aws elbv2 create-target-group --no-cli-pager \
  --name $APP_NAME \
  --port 8080 \
  --protocol HTTP \
  --vpc-id $UNICORN_VPC_ID \
  --target-type ip

echo Create a Listener

ALB_ARN=$(aws elbv2 describe-load-balancers --name $APP_NAME --query 'LoadBalancers[0].LoadBalancerArn' --output text)
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --name $APP_NAME --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 create-listener --no-cli-pager \
  --load-balancer-arn $ALB_ARN \
  --port 80 \
  --protocol HTTP \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN

echo Create a security group for ECS service to allow access to port 8080 from the Application Load Balancer

aws ec2 create-security-group \
  --group-name $APP_NAME-ecs-sg \
  --description "Security group for $APP_NAME ECS Service" \
  --vpc-id $UNICORN_VPC_ID
SECURITY_GROUP_ECS_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$UNICORN_VPC_ID'" --query 'SecurityGroups[?GroupName==`'$APP_NAME-ecs-sg'`].GroupId' --output text)
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ECS_ID \
  --protocol tcp \
  --port 8080 \
  --source-group $SECURITY_GROUP_ALB_ID

echo Create ECS service
  
TASK_DEFINITION_ARN=$(aws ecs describe-task-definition --task-definition $APP_NAME --query 'taskDefinition.taskDefinitionArn' --output text)
aws ecs create-service --no-cli-pager \
  --cluster $APP_NAME \
  --service-name $APP_NAME \
  --task-definition $TASK_DEFINITION_ARN \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$UNICORN_SUBNET_PRIVATE_1,$UNICORN_SUBNET_PRIVATE_1],securityGroups=[$SECURITY_GROUP_ECS_ID],assignPublicIp="DISABLED"}" \
  --load-balancer "targetGroupArn=$TARGET_GROUP_ARN,containerName=$APP_NAME,containerPort=8080"

echo Testing the application on Amazon ECS

SVC_URL=http://$(aws elbv2 describe-load-balancers --names $APP_NAME --query "LoadBalancers[0].DNSName" --output text)
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 10; done
echo $SVC_URL
curl --location $SVC_URL; echo
curl --location --request POST $SVC_URL'/unicorns' --header 'Content-Type: application/json' --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-deploy-ecs." $start_time
