#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-destroy-cicd ..." $start_time

aws codebuild delete-project --name unicorn-store-spring-build-ecr-x86_64
aws codebuild delete-project --name unicorn-store-spring-build-ecr-arm64
aws codebuild delete-project --name unicorn-store-spring-build-ecr-manifest
aws codebuild delete-project --name unicorn-store-spring-deploy-ecs

aws codepipeline delete-pipeline --name unicorn-store-spring-pipeline-build-ecr
aws codepipeline delete-pipeline --name unicorn-store-spring-deploy-ecs

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-destroy-cicd." $start_time
