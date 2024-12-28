APPRUNNER_ARN=$(aws apprunner list-services --query 'ServiceSummaryList[?ServiceName==`unicorn-store-spring`].ServiceArn' --output text)
aws apprunner delete-service --service-arn $APPRUNNER_ARN --no-cli-pager
if [[ "$APPRUNNER_ARN" != "" ]]
    then
        while [[ $(aws apprunner list-services --query 'ServiceSummaryList[?ServiceName==`unicorn-store-spring`].ServiceArn' --output text) == $APPRUNNER_ARN ]] && [[ $(aws apprunner list-operations --service-arn $APPRUNNER_ARN) != "SUCCEEDED" ]]; do echo "Service not yet deleted ..." &&  sleep 10; done
fi

# # Get the VPC connector ARN
# VPC_CONNECTOR_ARN=$(aws apprunner list-vpc-connectors --query 'VpcConnectors[?VpcConnectorName==`unicornstore-vpc-connector`].VpcConnectorArn' --output text)

# # Delete the VPC connector
# aws apprunner delete-vpc-connector --vpc-connector-arn $VPC_CONNECTOR_ARN --no-cli-pager
