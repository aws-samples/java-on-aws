#bin/sh

echo $(date '+%Y.%m.%d %H:%M:%S')
start_time=`date +%s`
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started ws-destroy-apprunner ..." $start_time

APPRUNNER_ARN=$(aws apprunner list-services --query 'ServiceSummaryList[?ServiceName==`unicorn-store-spring`].ServiceArn' --output text)
aws apprunner delete-service --service-arn $APPRUNNER_ARN --no-cli-pager
if [[ "$APPRUNNER_ARN" != "" ]]
    then
        while [[ $(aws apprunner list-services --query 'ServiceSummaryList[?ServiceName==`unicorn-store-spring`].ServiceArn' --output text) == $APPRUNNER_ARN ]] && [[ $(aws apprunner list-operations --service-arn $APPRUNNER_ARN) != "SUCCEEDED" ]]; do echo "Service not yet deleted ..." &&  sleep 10; done
fi

# APPRUNNER_ARN=$(aws apprunner list-services --query 'ServiceSummaryList[?ServiceName==`uss-app-env-dev-uss-svcr`].ServiceArn' --output text)
# aws apprunner delete-service --service-arn $APPRUNNER_ARN --no-cli-pager
# if [[ "$APPRUNNER_ARN" != "" ]]
#     then
#         while [[ $(aws apprunner list-services --query 'ServiceSummaryList[?ServiceName==`uss-app-env-dev-uss-svcr`].ServiceArn' --output text) == $APPRUNNER_ARN ]] && [[ $(aws apprunner list-operations --service-arn $APPRUNNER_ARN) != "SUCCEEDED" ]]; do echo "Service not yet deleted ..." &&  sleep 10; done
# fi

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Finished ws-destroy-apprunner." $start_time
