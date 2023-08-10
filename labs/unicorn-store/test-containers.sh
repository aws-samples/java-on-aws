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
  # location=$(cat infrastructure/cdk/target/output-eks.json | jq -r '.UnicornStoreSpringEKS.UnicornStoreServiceURL')
  location=$(kubectl get svc unicorn-store-spring -n unicorn-store-spring -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
fi

id=$(curl --location --request POST $location'/unicorns' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "name": "Something",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq -r '.id')
echo POST ...
echo id=$id
echo GET id=$id ...
curl --location --request GET $location'/unicorns/'$id | jq
echo PUT ...
curl --location --request PUT $location'/unicorns/'$id \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "name": "Something smaller",
    "age": "10",
    "type": "Animal",
    "size": "Small"
}' | jq -r
echo GET id=$id ...
curl --location --request GET $location'/unicorns/'$id | jq
echo DELETE id=$id ...
curl --location --request DELETE $location'/unicorns/'$id | jq
echo GET id=$id ...
curl --location --request GET $location'/unicorns/'$id | jq
