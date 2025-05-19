import json
import logging
import os
import boto3
import requests
from datetime import datetime
from typing import Dict, Any
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

class ECSClient:
    def __init__(self, cluster_name: str):
        self.cluster_name = cluster_name
        self.ecs = boto3.client('ecs')

    def get_container_ip(self, service_name: str) -> str:
        tasks = self.ecs.list_tasks(
            cluster=self.cluster_name,
            serviceName=service_name,
            desiredStatus='RUNNING'
        )
        if not tasks['taskArns']:
            raise ValueError(f"No running tasks found for service {service_name}")

        task_arn = tasks['taskArns'][0]
        task = self.ecs.describe_tasks(cluster=self.cluster_name, tasks=[task_arn])['tasks'][0]

        eni_details = task['attachments'][0]['details']
        private_ip = next((item['value'] for item in eni_details if item['name'] == 'privateIPv4Address'), None)

        if not private_ip:
            raise ValueError("Failed to get private IP of container")

        logger.info(f"Found private IP: {private_ip}")
        return private_ip

class ThreadDumpAnalyzer:
    def __init__(self):
        self.bedrock = boto3.client('bedrock-runtime')

    def analyze_dump(self, thread_dump: str) -> str:
        try:
            prompt = f"""Please analyze this Java thread dump and provide:
1. Summary of thread states and counts
2. Identification of potential bottlenecks
3. Performance optimization recommendations
4. Any concerning patterns or deadlock risks

Thread dump:
{thread_dump}"""

            response = self.bedrock.invoke_model(
                modelId="anthropic.claude-3-sonnet-20240229-v1:0",
                body=json.dumps({
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 4096,
                    "messages": [
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    "temperature": 0.7
                })
            )

            response_body = json.loads(response.get('body').read())
            return response_body.get('content')[0].get('text')

        except Exception as e:
            logger.error(f"Error analyzing thread dump: {str(e)}")
            return f"Error analyzing thread dump: {str(e)}"

def get_validated_parameters(event: Dict[str, Any]) -> Dict[str, str]:
    params = {
        'serviceName': event.get('serviceName', 'unicorn-store-spring'),
        'containerPort': int(event.get('containerPort', 8080))
    }

    logger.info(f"Received event parameters: {event}")
    logger.info(f"Processed parameters: {params}")

    if not params['serviceName']:
        raise ValueError("Missing required parameter: serviceName")

    return params

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        # Validate environment
        env_vars = {
            'ECS_CLUSTER_NAME': os.environ.get('ECS_CLUSTER_NAME'),
            'S3_BUCKET_NAME': os.environ.get('S3_BUCKET_NAME'),
            'SNS_TOPIC_ARN': os.environ.get('SNS_TOPIC_ARN')
        }

        missing_env = [key for key, value in env_vars.items() if not value and key != 'SNS_TOPIC_ARN']
        if missing_env:
            raise ValueError(f"Missing environment variables: {', '.join(missing_env)}")

        # Get parameters
        params = get_validated_parameters(event)
        service_name = params['serviceName']
        port = params['containerPort']

        # Get thread dump from actuator
        ecs_client = ECSClient(env_vars['ECS_CLUSTER_NAME'])
        container_ip = ecs_client.get_container_ip(service_name)

        actuator_url = f"http://{container_ip}:{port}/actuator/threaddump"
        logger.info(f"Calling actuator endpoint: {actuator_url}")
        response = requests.get(actuator_url, timeout=10)
        response.raise_for_status()
        thread_dump = response.text

        # Analyze
        analyzer = ThreadDumpAnalyzer()
        analysis = analyzer.analyze_dump(thread_dump)

        # Upload to S3
        s3_client = boto3.client('s3')
        timestamp = datetime.utcnow().strftime('%Y-%m-%d-%H-%M-%S')
        dump_key = f"thread-dumps/{service_name}/{timestamp}.txt"
        analysis_key = f"thread-dumps/{service_name}/{timestamp}_analysis.txt"

        s3_client.put_object(Bucket=env_vars['S3_BUCKET_NAME'], Key=dump_key, Body=thread_dump.encode('utf-8'))
        s3_client.put_object(Bucket=env_vars['S3_BUCKET_NAME'], Key=analysis_key, Body=analysis.encode('utf-8'))

        dump_url = f"s3://{env_vars['S3_BUCKET_NAME']}/{dump_key}"
        analysis_url = f"s3://{env_vars['S3_BUCKET_NAME']}/{analysis_key}"

        logger.info(f"Thread dump uploaded to {dump_url}")
        logger.info(f"Analysis uploaded to {analysis_url}")

        # Optional SNS
        if env_vars['SNS_TOPIC_ARN']:
            sns_client = boto3.client('sns')
            summary = analysis[:500] + "..." if len(analysis) > 500 else analysis
            sns_client.publish(
                TopicArn=env_vars['SNS_TOPIC_ARN'],
                Subject=f"Thread Dump Analysis - {service_name}",
                Message=json.dumps({
                    'serviceName': service_name,
                    'threadDumpUrl': dump_url,
                    'analysisUrl': analysis_url,
                    'timestamp': timestamp,
                    'summary': summary
                }, indent=2)
            )
            logger.info("SNS notification sent")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Thread dump collected, analyzed, and uploaded successfully',
                'threadDumpUrl': dump_url,
                'analysisUrl': analysis_url
            })
        }

    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        return {'statusCode': 400, 'body': json.dumps({'error': str(e)})}
    except ClientError as e:
        logger.error(f"AWS service error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': f"AWS service error: {str(e)}"})}
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': f"Unexpected error: {str(e)}"})}