import json
import logging
import os
import boto3
from datetime import datetime
from typing import Dict, Any
from eks_client import EKSClient
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def analyze_thread_dump(thread_dump: str) -> str:
    """
    Analyze thread dump using Bedrock and Claude 3.7
    
    Args:
        thread_dump: Thread dump content
        
    Returns:
        Analysis results as string
    """
    try:
        bedrock = boto3.client('bedrock-runtime')

        prompt = f"""Please analyze the following thread dump. Summarize the results and explain how the application can be optimized based on the data in the dump:

            {thread_dump}

            Please structure your response in the following sections:
            1. Summary of Thread States
            2. Key Issues Identified
            3. Optimization Recommendations
            4. Detailed Analysis
            """

        response = bedrock.converse(
            modelId="eu.anthropic.claude-3-7-sonnet-20250219-v1:0",
            system=[
                {
                    "text": "Your response should be in JSON format."
                }],
            messages=[{
                "role": "user",
                "content": [{"text": prompt}]
            }], inferenceConfig={"temperature": 0.1})

        response_message = response['output']['message']['content']
        response_message_dump = json.dumps(response_message, indent=4)
        logger.info(f"Received response: {response_message_dump}")

        return response_message_dump
        
    except Exception as e:
        logger.error(f"Error analyzing thread dump: {str(e)}")
        return f"Error analyzing thread dump: {str(e)}"

def get_validated_parameters(event: Dict[str, Any]) -> Dict[str, str]:
    """
    Get and validate parameters with default values
    """
    params = {
        'namespace': event.get('namespace', 'unicorn-store-spring'),
        'podPattern': event.get('podPattern', 'unicorn-store-*'),
        'containerName': event.get('containerName')
    }
    
    logger.info(f"Received event parameters: {event}")
    logger.info(f"Processed parameters: {params}")

    if not params['podPattern']:
        raise ValueError("Missing required parameter: podPattern")
    
    return params

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        # Ensure event is a dictionary
        if not isinstance(event, dict):
            raise ValueError(f"Invalid event format. Expected dictionary, got {type(event)}")

        # Get environment variables
        env_vars = {
            'EKS_CLUSTER_NAME': os.environ.get('EKS_CLUSTER_NAME'),
            'S3_BUCKET_NAME': os.environ.get('S3_BUCKET_NAME'),
            'SNS_TOPIC_ARN': os.environ.get('SNS_TOPIC_ARN')
        }
        
        # Validate environment variables
        missing_env_vars = [var for var, value in env_vars.items() if not value]
        if missing_env_vars:
            raise ValueError(f"Missing environment variables: {', '.join(missing_env_vars)}")
        
        # Get and validate parameters
        params = get_validated_parameters(event)
        logger.info(f"Using parameters: {params}")
        
        # Initialize EKS client
        eks_client = EKSClient(env_vars['EKS_CLUSTER_NAME'])
        
        # Get thread dump
        logger.info(f"Getting thread dump for pod pattern {params['podPattern']} in namespace {params['namespace']}")
        thread_dump = eks_client.get_thread_dump(
            namespace=params['namespace'],
            pod_name=params['podPattern'],
            container_name=params.get('containerName')
        )
        
        # Analyze thread dump
        analysis = analyze_thread_dump(thread_dump)

        # Initialize S3 client and upload
        s3_client = boto3.client('s3')
        timestamp = datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
        
        # Upload thread dump
        dump_key = f"thread-dumps/{params['namespace']}/{params['podPattern']}/{timestamp}.txt"
        s3_client.put_object(
            Bucket=env_vars['S3_BUCKET_NAME'],
            Key=dump_key,
            Body=thread_dump.encode('utf-8'),
            ContentType='text/plain'
        )
        
        # Upload analysis
        analysis_key = f"thread-dumps/{params['namespace']}/{params['podPattern']}/{timestamp}_analysis.txt"
        s3_client.put_object(
            Bucket=env_vars['S3_BUCKET_NAME'],
            Key=analysis_key,
            Body=analysis.encode('utf-8'),
            ContentType='text/plain'
        )
        
        dump_url = f"s3://{env_vars['S3_BUCKET_NAME']}/{dump_key}"
        analysis_url = f"s3://{env_vars['S3_BUCKET_NAME']}/{analysis_key}"
        
        logger.info(f"Thread dump uploaded to {dump_url}")
        logger.info(f"Analysis uploaded to {analysis_url}")

        # Prepare response data
        response_data = {
            'podPattern': params['podPattern'],
            'namespace': params['namespace'],
            'threadDumpUrl': dump_url,
            'analysisUrl': analysis_url,
            'message': 'Thread dump collected, analyzed and stored successfully'
        }

        # Send SNS notification if configured
        if env_vars['SNS_TOPIC_ARN']:
            sns_client = boto3.client('sns')
            sns_message = {
                **response_data,
                'timestamp': timestamp,
                'analysis_summary': analysis[:500] + "..." if len(analysis) > 500 else analysis
            }
            sns_client.publish(
                TopicArn=env_vars['SNS_TOPIC_ARN'],
                Message=json.dumps(sns_message, indent=2),
                Subject=f"Thread Dump Analysis - {params['namespace']}/{params['podPattern']}"
            )
            logger.info("SNS notification sent successfully")

        return {
            'statusCode': 200,
            'body': json.dumps(response_data)
        }

    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        return {
            'statusCode': 400,
            'body': json.dumps({'error': str(e)})
        }
    except ClientError as e:
        logger.error(f"AWS service error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f"AWS service error: {str(e)}"})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f"Unexpected error: {str(e)}"})
        }