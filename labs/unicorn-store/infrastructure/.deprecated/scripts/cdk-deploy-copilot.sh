#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started cdk-deploy-copilot ..." $start_time

pushd ~/environment/unicorn-store-spring
# uss=unicorn-store-spring - long app/service names may cause problems
COPILOT_APP=uss-app
COPILOT_SVC=uss-svc
COPILOT_ENV=env-dev

UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc --query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)
UNICORN_SUBNET_PUBLIC_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet1" \
--query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PUBLIC_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet2" \
--query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet1" \
--query 'Subnets[0].SubnetId' --output text)
UNICORN_SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet2" \
--query 'Subnets[0].SubnetId' --output text)

# copilot-application=uss-app
# copilot-environment=env-dev
aws secretsmanager tag-resource --secret-id unicornstore-db-secret --tags Key=copilot-application,Value=$COPILOT_APP
aws secretsmanager tag-resource --secret-id unicornstore-db-secret --tags Key=copilot-environment,Value=$COPILOT_ENV
aws ssm add-tags-to-resource --resource-type Parameter --resource-id databaseJDBCConnectionString --tags Key=copilot-application,Value=$COPILOT_APP
aws ssm add-tags-to-resource --resource-type Parameter --resource-id databaseJDBCConnectionString --tags Key=copilot-environment,Value=$COPILOT_ENV

copilot app init $COPILOT_APP

copilot env init --name $COPILOT_ENV --app $COPILOT_APP --profile default \
--import-vpc-id $UNICORN_VPC_ID \
--import-public-subnets $UNICORN_SUBNET_PUBLIC_1,$UNICORN_SUBNET_PUBLIC_2 \
--import-private-subnets $UNICORN_SUBNET_PRIVATE_1,$UNICORN_SUBNET_PRIVATE_2

# update copilot manifests
# /unicorn-store-spring/copilot/environments/env-dev/manifest.yml
yq '.http.public="" | .http.public tag="!!null"' -i ./copilot/environments/$COPILOT_ENV/manifest.yml

copilot env deploy --name $COPILOT_ENV

ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')

copilot svc init --name $COPILOT_SVC --app $COPILOT_APP --image $ECR_URI:latest \
--svc-type "Request-Driven Web Service" --ingress-type Internet --port 8080

# update copilot manifests
# /unicorn-store-spring/copilot/uss-svc/manifest.yml
SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name databaseJDBCConnectionString | jq --raw-output '.Parameter.Value')
SPRING_DATASOURCE_SECRET=$(aws cloudformation describe-stacks --stack-name UnicornStoreInfrastructure --query 'Stacks[0].Outputs[?OutputKey==`arnUnicornStoreDbSecret`].OutputValue' --output text)
yq ".secrets.SPRING_DATASOURCE_PASSWORD=\"'$SPRING_DATASOURCE_SECRET:password::'\"" -i ./copilot/$COPILOT_SVC/manifest.yml
yq ".environments.$COPILOT_ENV.variables.SPRING_DATASOURCE_URL=\"$SPRING_DATASOURCE_URL\"" -i ./copilot/$COPILOT_SVC/manifest.yml
yq '.network.vpc.placement="private"' -i ./copilot/$COPILOT_SVC/manifest.yml

mkdir -p copilot/$COPILOT_SVC/overrides
cat <<EOF > copilot/$COPILOT_SVC/overrides/cfn.patches.yml
- op: add
  path: /Resources/InstanceRole/Properties/Policies/-
  value:
    PolicyName: UnicornStoreEventBusPutPolicy
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Sid: EventBusPut
          Effect: Allow
          Action:
            - events:PutEvents
          Resource:
            Fn::ImportValue:
              !Sub arnUnicornStoreEventBus
EOF

copilot svc deploy --name $COPILOT_SVC --app $COPILOT_APP --env $COPILOT_ENV

SVC_URL=http://$(copilot svc show --name $COPILOT_SVC --json | jq -r '.routes[0].url')
while [[ $(curl -s -o /dev/null -w "%{http_code}" $SVC_URL/) != "200" ]]; do echo "Service not yet available ..." &&  sleep 5; done
echo $SVC_URL
curl --location $SVC_URL; echo
curl --location --request POST $SVC_URL'/unicorns' --header 'Content-Type: application/json' --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq

popd

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished cdk-deploy-copilot." $start_time
