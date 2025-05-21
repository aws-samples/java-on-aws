#!/bin/bash
set -e

REPOSITORY_NAME="workshop-app"

# Update the ECS service to use the new image
TASK_DEFINITION=$(aws ecs describe-task-definition --task-definition $REPOSITORY_NAME --region $AWS_REGION)
NEW_TASK_DEFINITION=$(echo $TASK_DEFINITION | jq '.taskDefinition' | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')
NEW_CONTAINER_DEFINITION=$(echo $NEW_TASK_DEFINITION | jq '.containerDefinitions[0]' | jq '.image="'$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY_NAME:latest'"')
NEW_TASK_DEFINITION=$(echo $NEW_TASK_DEFINITION | jq --argjson container "$NEW_CONTAINER_DEFINITION" '.containerDefinitions[0]=$container')

# Register the new task definition
NEW_TASK_DEFINITION_ARN=$(aws ecs register-task-definition --region $AWS_REGION --cli-input-json "$(echo $NEW_TASK_DEFINITION)" --query 'taskDefinition.taskDefinitionArn' --output text)

# Update the service to use the new task definition
aws ecs update-service --cluster $REPOSITORY_NAME --service $REPOSITORY_NAME --task-definition $NEW_TASK_DEFINITION_ARN --region $AWS_REGION --no-cli-pager

echo "ECS service $REPOSITORY_NAME updated to use the new image"
