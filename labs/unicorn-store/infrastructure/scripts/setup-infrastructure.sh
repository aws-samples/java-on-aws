#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

cd ~/environment/java-on-aws/labs/unicorn-store
# Build the database setup function
mvn clean package -f infrastructure/db-setup/pom.xml 1> /dev/null

# Build the unicorn application
mvn clean package -f software/unicorn-store-spring/pom.xml 1> /dev/null

# Deploy the infrastructure
pushd infrastructure/cdk

cdk bootstrap
cdk deploy UnicornStoreVpc --require-approval never --outputs-file target/output-vpc.json
cdk deploy UnicornStoreInfrastructure --require-approval never --outputs-file target/output-infra.json
cdk deploy UnicornStoreLambdaApp --require-approval never --outputs-file target/output-lambda.json

# Execute the DB Setup function to create the table
aws lambda invoke --function-name $(cat target/output-infra.json | jq -r '.UnicornStoreInfrastructure.DbSetupArn') /dev/stdout | cat;

popd

# Copy the Spring Boot Java Application source code to your local directory
cd ~/environment
mkdir unicorn-store-spring

rsync -av java-on-aws/labs/unicorn-store/software/unicorn-store-spring/ unicorn-store-spring --exclude target --exclude src/test
cp -R java-on-aws/labs/unicorn-store/software/dockerfiles unicorn-store-spring
cp -R java-on-aws/labs/unicorn-store/software/scripts unicorn-store-spring
rm ~/environment/unicorn-store-spring/src/main/resources/schema.sql
echo "target" > unicorn-store-spring/.gitignore

# create AWS CodeCommit for Java Sources
aws codecommit create-repository --repository-name unicorn-store-spring --repository-description "Java application sources"

# create Amazon ECR for images
aws ecr create-repository --repository-name unicorn-store-spring

# Navigate to the application folder and download dependencies via Maven:
cd ~/environment/unicorn-store-spring
mvn dependency:go-offline -f ./pom.xml 1> /dev/null

# Resolution for ECS Service Unavailable
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com
# Resolution for When creating the first service in the account
aws iam create-service-linked-role --aws-service-name apprunner.amazonaws.com

# Disable Temporary credentials on login
echo 'aws cloud9 update-environment --environment-id $C9_PID --managed-credentials-action DISABLE --region $AWS_REGION &> /dev/null' | tee -a /home/ec2-user/.bash_profile
echo 'rm -vf ${HOME}/.aws/credentials  &> /dev/null' | tee -a /home/ec2-user/.bash_profile

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "setup-infrastructure" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

# additional modules setup
start_time=`date +%s`

cd ~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts
source ~/.bashrc
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/setup-vpc-connector.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/setup-vpc-peering.sh
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "setup-vpc" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)
