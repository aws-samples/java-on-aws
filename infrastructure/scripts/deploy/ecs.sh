set -e

APP_NAME=${1:-"unicorn-store-spring"}
PROJECT_NAME=${2:-"unicorn-store"}

UNICORNSTORE_DB_CONNECTION_STRING_ARN=$(aws ssm get-parameter --name "unicornstore-db-connection-string" \
  --query 'Parameter.ARN' --output text) && echo $UNICORNSTORE_DB_CONNECTION_STRING_ARN
UNICORNSTORE_DB_PASSWORD_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id unicornstore-db-password-secret \
    --query 'ARN' --output text) && echo $UNICORNSTORE_DB_PASSWORD_SECRET_ARN
cat <<EOF > ~/environment/unicorn-store-spring/esc-container-definitions.json
[
    {
        "name": "unicorn-store-spring",
        "image": "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/unicorn-store-spring:latest",
        "portMappings": [
            {
                "name": "unicorn-store-spring-8080-tcp",
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
                "valueFrom": "$UNICORNSTORE_DB_CONNECTION_STRING_ARN"
            },
            {
                "name": "SPRING_DATASOURCE_PASSWORD",
                "valueFrom": "$UNICORNSTORE_DB_PASSWORD_SECRET_ARN"
            }
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/unicorn-store-spring",
                "awslogs-create-group": "true",
                "awslogs-region": "$AWS_REGION",
                "awslogs-stream-prefix": "ecs"
            }
        }
    }
]
EOF

aws ecs register-task-definition --family unicorn-store-spring --no-cli-pager \
    --requires-compatibilities FARGATE --network-mode awsvpc \
    --cpu 1024 --memory 2048 \
    --task-role-arn arn:aws:iam::$ACCOUNT_ID:role/unicornstore-ecs-task-role \
    --execution-role-arn arn:aws:iam::$ACCOUNT_ID:role/unicornstore-ecs-task-execution-role \
    --container-definitions file://~/environment/unicorn-store-spring/esc-container-definitions.json \
    --runtime-platform '{"cpuArchitecture":"X86_64","operatingSystemFamily":"LINUX"}'
rm ~/environment/unicorn-store-spring/esc-container-definitions.json

aws ecs create-cluster --cluster-name unicorn-store-spring --capacity-providers FARGATE --no-cli-pager

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query 'Vpcs[0].VpcId' --output text) && echo $VPC_ID

aws ec2 create-security-group \
  --group-name unicorn-store-spring-ecs-sg-alb \
  --description "Security group for unicorn-store-spring ALB" \
  --vpc-id $VPC_ID
SECURITY_GROUP_ALB_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" \
  --query 'SecurityGroups[?GroupName==`'unicorn-store-spring-ecs-sg-alb'`].GroupId' --output text) && echo $SECURITY_GROUP_ALB_ID
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ALB_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query 'Vpcs[0].VpcId' --output text) && echo $VPC_ID
SUBNET_PUBLIC_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*PublicSubnet1" \
  --query 'Subnets[0].SubnetId' --output text) && echo $SUBNET_PUBLIC_1
SUBNET_PUBLIC_2=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*PublicSubnet2" \
  --query 'Subnets[0].SubnetId' --output text) && echo $SUBNET_PUBLIC_2
SECURITY_GROUP_ALB_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" \
  --query 'SecurityGroups[?GroupName==`'unicorn-store-spring-ecs-sg-alb'`].GroupId' --output text) && echo $SECURITY_GROUP_ALB_ID

aws elbv2 create-load-balancer --no-cli-pager \
  --name unicorn-store-spring \
  --subnets $SUBNET_PUBLIC_1 $SUBNET_PUBLIC_2 \
  --security-groups $SECURITY_GROUP_ALB_ID

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query 'Vpcs[0].VpcId' --output text) && echo $VPC_ID

aws elbv2 create-target-group --no-cli-pager \
  --name unicorn-store-spring \
  --port 8080 \
  --protocol HTTP \
  --vpc-id $VPC_ID \
  --target-type ip

TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --name unicorn-store-spring \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 modify-target-group \
  --target-group-arn $TARGET_GROUP_ARN \
  --health-check-path "/actuator/health" \
  --health-check-port "traffic-port" \
  --health-check-protocol HTTP \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3

ALB_ARN=$(aws elbv2 describe-load-balancers --name unicorn-store-spring \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text) && echo $ALB_ARN
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --name unicorn-store-spring \
  --query 'TargetGroups[0].TargetGroupArn' --output text) && echo $TARGET_GROUP_ARN

aws elbv2 create-listener --no-cli-pager \
  --load-balancer-arn $ALB_ARN \
  --port 80 \
  --protocol HTTP \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query 'Vpcs[0].VpcId' --output text) && echo $VPC_ID

EKS_VPC_CIDR=$(aws ec2 describe-vpcs \
  --vpc-ids "$VPC_ID" \
  --query "Vpcs[0].CidrBlock" --output text)

LAMBDA_SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" \
  --query 'SecurityGroups[?GroupName==`'unicornstore-thread-dump-lambda-sg'`].GroupId' --output text)

sleep 1

aws ec2 create-security-group \
  --group-name unicorn-store-spring-ecs-sg \
  --description "Security group for unicorn-store-spring ECS Service" \
  --vpc-id $VPC_ID
SECURITY_GROUP_ECS_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" \
  --query 'SecurityGroups[?GroupName==`'unicorn-store-spring-ecs-sg'`].GroupId' --output text) && echo $SECURITY_GROUP_ECS_ID
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ECS_ID \
  --protocol tcp \
  --port 8080 \
  --source-group-id $SECURITY_GROUP_ALB_ID
aws ec2 authorize-security-group-ingress \
  --group-id "$SECURITY_GROUP_ECS_ID" \
  --protocol tcp \
  --port 9090 \
  --cidr "$EKS_VPC_CIDR"
aws ec2 authorize-security-group-ingress \
  --group-id "$SECURITY_GROUP_ECS_ID" \
  --protocol tcp \
  --port 9404 \
  --cidr "$EKS_VPC_CIDR"
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ECS_ID \
  --protocol tcp \
  --port 8080 \
  --source-group-id $LAMBDA_SG_ID

TASK_DEFINITION_ARN=$(aws ecs describe-task-definition --task-definition unicorn-store-spring \
  --query 'taskDefinition.taskDefinitionArn' --output text) && echo $TASK_DEFINITION_ARN
SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*PrivateSubnet1" \
  --query 'Subnets[0].SubnetId' --output text) && echo $SUBNET_PRIVATE_1
SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*PrivateSubnet2" \
  --query 'Subnets[0].SubnetId' --output text) && echo $SUBNET_PRIVATE_2
SECURITY_GROUP_ECS_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" \
  --query 'SecurityGroups[?GroupName==`'unicorn-store-spring-ecs-sg'`].GroupId' --output text) && echo $SECURITY_GROUP_ECS_ID
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --name unicorn-store-spring \
  --query 'TargetGroups[0].TargetGroupArn' --output text) && echo $TARGET_GROUP_ARN

aws ecs create-service --no-cli-pager \
  --cluster unicorn-store-spring \
  --service-name unicorn-store-spring \
  --task-definition $TASK_DEFINITION_ARN \
  --enable-execute-command \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_PRIVATE_1,$SUBNET_PRIVATE_2],securityGroups=[$SECURITY_GROUP_ECS_ID],assignPublicIp="DISABLED"}" \
  --load-balancer "targetGroupArn=$TARGET_GROUP_ARN,containerName=unicorn-store-spring,containerPort=8080"

SVC_URL=http://$(aws elbv2 describe-load-balancers --names unicorn-store-spring --query "LoadBalancers[0].DNSName" --output text)
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

echo "App deployment to ECS service is complete."
