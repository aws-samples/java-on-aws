#bin/sh

# Build the database setup function
./mvnw clean package -f infrastructure/db-setup/pom.xml 1> /dev/null

# Build the unicorn application
./mvnw clean package -f software/unicorn-store-spring/pom.xml 1> /dev/null

# Deploy the infrastructure
pushd infrastructure/cdk

cdk bootstrap
cdk deploy UnicornStoreVpc --require-approval never --outputs-file target/output-vpc.json
cdk deploy UnicornStoreInfrastructure --require-approval never --outputs-file target/output-infra.json
cdk deploy UnicornStoreLambdaApp --require-approval never --outputs-file target/output-lambda.json

# Execute the DB Setup function to create the table
aws lambda invoke --function-name $(cat target/output-infra.json | jq -r '.UnicornStoreInfrastructure.DbSetupArn') /dev/stdout | cat;

popd

./setup-vpc-env-vars.sh
source ~/.bashrc
./setup-vpc-connector.sh
./setup-vpc-peering.sh

# Copy the Spring Boot Java Application source code to your local directory
cd ~/environment
mkdir unicorn-store-spring

rsync -av java-on-aws/labs/unicorn-store/software/unicorn-store-spring/ unicorn-store-spring --exclude target
cp -R java-on-aws/labs/unicorn-store/software/dockerfiles unicorn-store-spring
cp -R java-on-aws/labs/unicorn-store/software/maven unicorn-store-spring
echo "target" > unicorn-store-spring/.gitignore

# create AWS CodeCommit for Java Sources
aws codecommit create-repository --repository-name unicorn-store-spring --repository-description "Java application sources"

# create Amazon ECR for images
aws ecr create-repository --repository-name unicorn-store-spring

export ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-store-spring | jq --raw-output '.repositories[0].repositoryUri')
echo "export ECR_URI=${ECR_URI}" | tee -a ~/.bash_profile
echo "export ECR_URI=${ECR_URI}" >> ~/.bashrc

# Navigate to the application folder and download dependencies via Maven:
cd ~/environment/unicorn-store-spring
mvn dependency:go-offline -f ./pom.xml 1> /dev/null

echo "FINISHED: setup-infrastructure"
