#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`

cd ~/environment/java-on-aws/labs/unicorn-store
# Build the database setup function
mvn clean package -f infrastructure/db-setup/pom.xml 1> /dev/null

# Deploy the infrastructure
pushd infrastructure/cdk

cdk bootstrap
cdk deploy UnicornStoreVpc --require-approval never --outputs-file target/output-vpc.json
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "setup-vpc" $start_time 2>&1 | tee >(cat >> ~/setup-timing.log)

# Check if --with-eks is present in the arguments
if [[ "$*" == *"--with-eks"* ]]; then
    echo "--with-eks parameter is present"
    # Deploy EKS cluster in background ...
    # nohup ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-deploy-eks-eksctl-karpenter.sh >> ~/ws-deploy-eks-eksctl-karpenter.log 2>&1 &
    nohup ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/ws-deploy-eks-eksctl-karpenter.sh 2>&1 &
else
    echo "--with-eks parameter is not present"
fi

cdk deploy UnicornStoreInfrastructure --require-approval never --outputs-file target/output-infra.json
cdk deploy UnicornStoreLambdaApp --require-approval never --outputs-file target/output-lambda.json

# Execute the DB Setup function to create the table
aws lambda invoke --function-name $(cat target/output-infra.json | jq -r '.UnicornStoreInfrastructure.DbSetupArn') /dev/stdout | cat;

popd

# create AWS CodeCommit for Java Sources
# aws codecommit create-repository --repository-name unicorn-store-spring --repository-description "Java application sources"

# Resolution for ECS Service Unavailable
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com
# Resolution for When creating the first service in the account
aws iam create-service-linked-role --aws-service-name apprunner.amazonaws.com

# additional modules setup
start_time=`date +%s`

cd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts
source ~/.bashrc
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/setup-vpc-connector.sh
# ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/setup-vpc-peering.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "setup-infrastructure" $start_time 2>&1 | tee >(cat >> ~/setup-timing.log)

# Check if --with-eks is present in the arguments
if [[ "$*" == *"--with-eks"* ]]; then
    echo "--with-eks parameter is present"
    until [ -f ~/ws-deploy-eks-eksctl.completed ]; do sleep 10; done
    echo EKS cluster deployment is finished.
else
    echo "--with-eks parameter is not present"
fi
