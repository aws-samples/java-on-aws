#!/bin/sh

# Default to EKS if no parameter provided
COMPUTE=${1:-eks}

SVC_URL=""

if [ "$COMPUTE" = "ecs" ]; then
    # Try Express Mode first (HTTPS)
    EXPRESS_URL=$(aws ecs describe-express-gateway-service \
        --service-arn arn:aws:ecs:${AWS_REGION}:${ACCOUNT_ID}:service/unicorn-store-spring/unicorn-store-spring \
        --no-cli-pager 2>/dev/null \
        | jq -r '.service.activeConfigurations[0].ingressPaths[0].endpoint // empty')
    if [ -n "$EXPRESS_URL" ]; then
        SVC_URL=https://${EXPRESS_URL}
    else
        # Fall back to regular ECS with ALB (HTTP)
        ALB_DNS=$(aws elbv2 describe-load-balancers --names unicorn-store-spring \
            --query "LoadBalancers[0].DNSName" --output text --no-cli-pager 2>/dev/null)
        if [ -n "$ALB_DNS" ] && [ "$ALB_DNS" != "None" ]; then
            SVC_URL=http://${ALB_DNS}
        fi
    fi
elif [ "$COMPUTE" = "eks" ]; then
    SVC_URL=http://$(kubectl get ingress unicorn-store-spring \
        -n unicorn-store-spring \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
elif [ "$COMPUTE" = "local" ]; then
    SVC_URL="http://localhost:8080"
fi

# Check if URL was successfully set
if [ -z "$SVC_URL" ] || [ "$SVC_URL" = "http://" ]; then
    echo "Error: Failed to retrieve service URL for compute target '$COMPUTE'"
    exit 1
fi

echo $SVC_URL
