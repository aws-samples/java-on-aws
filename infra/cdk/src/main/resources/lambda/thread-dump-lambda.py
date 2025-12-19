"""
Thread Dump Lambda - Placeholder for CDK deployment.
This is a minimal placeholder that will be replaced by the full implementation
via post-deployment script (infra/scripts/setup/thread-dump-lambda/).

The full implementation includes:
- EKS client for thread dump collection via kubectl exec
- ECS client for thread dump collection via container IP
- Bedrock integration for AI-powered thread analysis
- S3 storage for thread dumps and analysis results
- Grafana webhook authentication
"""
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Placeholder handler - returns instructions for full deployment.
    Run the post-deployment script to enable full functionality.
    """
    logger.info(f'Thread Dump Lambda invoked (placeholder)')
    logger.info(f'Event: {json.dumps(event)}')

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Thread dump Lambda placeholder - run post-deployment script for full functionality',
            'instructions': 'Execute: ~/java-on-aws/infra/scripts/setup/thread-dump-lambda/deploy.sh',
            'function_name': context.function_name,
            'request_id': context.aws_request_id
        })
    }
