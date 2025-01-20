#bin/sh

# Check if parameter is provided
if [ -z "$1" ]; then
    echo "Error: Compute target parameter is required"
    echo "Usage: $0 <compute-target>"
    echo "Valid compute targets: apprunner, ecs, eks, lambda, local"
    exit 1
fi

COMPUTE=$1

SVC_URL=""

if [ "$COMPUTE" = "apprunner" ]; then
    SVC_URL=https://$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName == 'unicorn-store-spring'].ServiceUrl" --output text)
elif [ "$COMPUTE" = "ecs" ]; then
    SVC_URL=http://$(aws elbv2 describe-load-balancers --names unicorn-store-spring --query "LoadBalancers[0].DNSName" --output text)
elif [ "$COMPUTE" = "eks" ]; then
    SVC_URL=http://$(kubectl get ingress unicorn-store-spring -n unicorn-store-spring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
elif [ "$COMPUTE" = "lambda" ]; then
    REST_API_ID=$(aws apigateway get-rest-apis --query 'items[?name==`unicorn-store-spring-api`].[id]' --output text)
    STAGE=$(aws apigateway get-stages --rest-api-id $REST_API_ID --query 'item[].stageName' --output text)
    SVC_URL=https://$REST_API_ID.execute-api.$AWS_REGION.amazonaws.com/$STAGE
elif [ "$COMPUTE" = "local" ]; then
    SVC_URL="http://localhost:8080"
fi

# Check if URL was successfully set
if [ -z "$SVC_URL" ]; then
    echo "Error: Failed to retrieve service URL for compute target '$COMPUTE'"
    exit 1
fi

echo $SVC_URL
