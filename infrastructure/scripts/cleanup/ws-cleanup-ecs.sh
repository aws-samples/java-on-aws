APP_NAME=unicorn-store-spring

ALB_ARN=$(aws elbv2 describe-load-balancers --name $APP_NAME --query 'LoadBalancers[0].LoadBalancerArn' --output text)
aws elbv2 delete-listener --listener-arn $(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query 'Listeners[0].ListenerArn' --output text)
aws elbv2 delete-target-group --target-group-arn $(aws elbv2 describe-target-groups --query 'TargetGroups[?TargetGroupName==`'$APP_NAME'`].TargetGroupArn' --output text)
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN

aws ecs delete-service --cluster $APP_NAME --service $APP_NAME --force --no-cli-pager
CLUSTER_NAME=$(aws ecs list-clusters --query "clusterArns[?contains(@, '$APP_NAME')] | [0]" --output text)
if [ "$CLUSTER_NAME" != "None" ]; then
    while [[ $(aws ecs describe-services --cluster $APP_NAME --services $APP_NAME --query 'services[0].status' --output text) != "INACTIVE" ]]; do echo "Service is in $(aws ecs describe-services --cluster unicorn-store-spring --services unicorn-store-spring --query 'services[0].status' --output text) status. Waiting ... " &&  sleep 10; done
else
    echo "The cluster name is $CLUSTER_NAME"
fi
aws ecs delete-cluster --cluster $APP_NAME --no-cli-pager

TASK_DEFINITION_ARNS=$(aws ecs list-task-definitions --family-prefix $APP_NAME --query 'taskDefinitionArns' --output text)
for TASK_DEFINITION_ARN in $TASK_DEFINITION_ARNS; do
    aws ecs deregister-task-definition --task-definition --no-cli-pager $TASK_DEFINITION_ARN;
    aws ecs delete-task-definitions --task-definition $TASK_DEFINITION_ARN --no-cli-pager;
done

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=unicornstore-vpc" \
  --query 'Vpcs[0].VpcId' --output text) && echo $VPC_ID

aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" --query 'SecurityGroups[?GroupName==`'$APP_NAME-ecs-sg'`].GroupId' --output text)
aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values='$VPC_ID'" --query 'SecurityGroups[?GroupName==`'$APP_NAME-ecs-sg-alb'`].GroupId' --output text)
