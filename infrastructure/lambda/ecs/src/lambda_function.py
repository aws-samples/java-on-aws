# lambda_function.py

import json
import logging
import os
import boto3
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
        self.ssm = boto3.client('ssm')
        
    def get_thread_dump(self, service_name: str, container_name: str = None) -> str:
        """
        Get thread dump from specified ECS container using ECS Exec
        """
        try:
            # Get task ARN
            tasks = self.ecs.list_tasks(
                cluster=self.cluster_name,
                serviceName=service_name,
                desiredStatus='RUNNING'
            )
            
            if not tasks['taskArns']:
                raise ValueError(f"No running tasks found for service {service_name}")
                
            task_arn = tasks['taskArns'][0]
            
            # Get task details
            task = self.ecs.describe_tasks(
                cluster=self.cluster_name,
                tasks=[task_arn]
            )['tasks'][0]
            
            # Find container
            if not container_name:
                container = task['containers'][0]
                container_name = container['name']
            else:
                container = next(
                    (c for c in task['containers'] if c['name'] == container_name),
                    None
                )
                
            if not container:
                raise ValueError(f"Container {container_name} not found")
            
            # Execute thread dump command
            command = 'jcmd 1 Thread.print -l'
            
            response = self.ecs.execute_command(
                cluster=self.cluster_name,
                task=task_arn,
                container=container_name,
                interactive=False,
                command=command
            )
            
            # Get command output from SSM
            command_id = response['session']['sessionId']
            waiter = self.ssm.get_waiter('command_executed')
            waiter.wait(
                CommandId=command_id,
                InstanceId=task_arn
            )
            
            output = self.ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=task_arn
            )
            
            return output['StandardOutputContent']
            
        except Exception as e:
            logger.error(f"Error getting thread dump: {str(e)}")
            raise

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
    """
    Get and validate parameters with default values
    """
    params = {
        'serviceName': event.get('serviceName', 'thread-demo'),
        'containerName': event.get('containerName')
    }
    
    logger.info(f"Received event parameters: {event}")
    logger.info(f"Processed parameters: {params}")

    if not params['serviceName']:
        raise ValueError("Missing required parameter: serviceName")
    
    return params

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        # Ensure event is a dictionary
        if not isinstance(event, dict):
            raise ValueError(f"Invalid event format. Expected dictionary, got {type(event)}")

        # Get environment variables
        env_vars = {
            'ECS_CLUSTER_NAME': os.environ.get('ECS_CLUSTER_NAME'),
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
        
        # Initialize ECS client
        ecs_client = ECSClient(env_vars['ECS_CLUSTER_NAME'])
        
        # Get thread dump
        logger.info(f"Getting thread dump for service {params['serviceName']}")
        thread_dump = ecs_client.get_thread_dump(
            service_name=params['serviceName'],
            container_name=params.get('containerName')
        )

        # Initialize analyzer and analyze dump
        analyzer = ThreadDumpAnalyzer()
        analysis = analyzer.analyze_dump(thread_dump)

        # Initialize S3 client and upload
        s3_client = boto3.client('s3')
        timestamp = datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
        
        # Upload thread dump
        dump_key = f"thread-dumps/{params['serviceName']}/{timestamp}.txt"
        s3_client.put_object(
            Bucket=env_vars['S3_BUCKET_NAME'],
            Key=dump_key,
            Body=thread_dump.encode('utf-8'),
            ContentType='text/plain'
        )
        
        # Upload analysis
        analysis_key = f"thread-dumps/{params['serviceName']}/{timestamp}_analysis.txt"
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
            'serviceName': params['serviceName'],
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
                Subject=f"Thread Dump Analysis - {params['serviceName']}"
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
