#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-destroy-lambda ..." $start_time

echo Deleting Lambda ...
sam delete --stack-name unicorn-audit-stack --no-prompts
aws events delete-rule --name unicorn-event-rule
aws lambda delete-function --function-name unicorn-audit-service
aws lambda delete-function --function-name unicorn-store-spring
aws dynamodb delete-table --table-name unicorn-events
aws cloudformation delete-stack --stack-name aws-sam-cli-managed-default

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-destroy-lambda." $start_time
