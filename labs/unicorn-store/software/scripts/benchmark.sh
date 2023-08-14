#bin/sh

app=$1

location=""

if [ $app == "apprunner" ]
then
  location=$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName == 'unicorn-store-spring'].ServiceUrl" --output text)
fi

if [ $app == "copilot" ]
then
  location=$(aws apprunner list-services --query "ServiceSummaryList[?ServiceName == 'uss-app-env-dev-uss-svc'].ServiceUrl" --output text)
fi

if [ $app == "ecs" ]
then
  location=$(aws elbv2 describe-load-balancers --names unicorn-store-spring --query "LoadBalancers[0].DNSName" --output text)
fi

if [ $app == "eks" ]
then
  location=$(kubectl get svc unicorn-store-spring -n unicorn-store-spring -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
fi

if [ $app == "lambda" ]
then
  location=$(aws cloudformation describe-stacks --stack-name UnicornStoreLambdaApp | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "ApiEndpointSpring").OutputValue')
fi

artillery run -t http://$location -v '{ "url": "/unicorns" }' ~/environment/unicorn-store-spring/scripts/loadtest.yaml
exit 0
