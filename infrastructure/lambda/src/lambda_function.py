import json
import logging
import os
import boto3
import requests
import time
import random
from datetime import datetime
from typing import Dict, Any
from kubernetes import client, config
from botocore.exceptions import ClientError
from eks_client import EKSClient  # Your own implementation

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def is_invalid(value: str) -> bool:
    return value is None or value.strip() in ["", "[no value]"]


def analyze_thread_dump(thread_dump: str) -> str:
    bedrock = boto3.client("bedrock-runtime", region_name="eu-west-1")

    logger.info(f"Using Bedrock in region: {bedrock.meta.region_name}")
    prompt = f"""Please analyze the following Java thread dump. Your task is to identify performance issues and provide actionable insights. Structure the output into the following four sections:

1. **Summary of Thread States**: Count and categorize all thread states (e.g., RUNNABLE, WAITING).
2. **Key Issues Identified**: Describe any threads that appear stuck, blocked, or problematic (e.g., deadlocks, high CPU).
3. **Optimization Recommendations**: Suggest practical improvements based on your findings (e.g., code, configuration, GC tuning).
4. **Detailed Analysis**: Provide a technical breakdown of the most interesting or problematic threads.

Thread Dump:
{thread_dump}
"""

    payload = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.7
    })

    max_attempts = 5
    base_delay = 10

    # Cap backoff to avoid over-waiting
    max_delay = 30

    for attempt in range(1, max_attempts + 1):
        logger.info(f"Invoking Bedrock with payload ... ")
        try:
            response = bedrock.invoke_model(
                modelId="eu.anthropic.claude-3-7-sonnet-20250219-v1:0",
                body=payload
            )
            body = json.loads(response.get("body").read())
            return body.get("content")[0].get("text")
        except ClientError as e:
            if e.response["Error"]["Code"] == "ThrottlingException" and attempt < max_attempts:
                
                logger.error(f"ClientError during analysis: {str(e)}")

                delay = min(random.uniform(0, base_delay * (2 ** attempt)), max_delay)
                logger.warning(f"Bedrock throttled (attempt {attempt}) — retrying in {delay:.2f}s")
                time.sleep(delay)
            else:
                logger.error(f"ClientError during analysis: {str(e)}")
                return f"ClientError during analysis: {str(e)}"
        except Exception as e:
            logger.error(f"Unexpected error during analysis: {str(e)}")
            return f"Unexpected error during analysis: {str(e)}"

    return "Failed to analyze thread dump after multiple retries due to throttling."


class ECSClient:
    def __init__(self, cluster_name: str):
        self.cluster_name = cluster_name
        self.ecs = boto3.client('ecs')

    def get_container_ip(self, task_id: str) -> str:
        task = self.ecs.describe_tasks(cluster=self.cluster_name, tasks=[task_id])['tasks'][0]
        eni_details = task['attachments'][0]['details']
        private_ip = next((item['value'] for item in eni_details if item['name'] == 'privateIPv4Address'), None)
        if not private_ip:
            raise ValueError("Failed to get private IP of container")
        logger.info(f"Found private IP: {private_ip}")
        return private_ip


def process_alert(cluster_type, cluster_name, task_pod_id, container_name, namespace, s3_bucket):
    """Extract the alert processing logic into a separate function for reuse"""
    # Get the thread dump based on cluster type
    if cluster_type == 'ecs':
        ecs_client = ECSClient(cluster_name)
        container_ip = ecs_client.get_container_ip(task_pod_id)
        response = requests.get(f"http://{container_ip}:9404/actuator/threaddump", timeout=10)
        response.raise_for_status()
        thread_dump = response.text
        
    elif cluster_type == 'eks':
        eks_client = EKSClient(cluster_name)
        thread_dump = eks_client.get_thread_dump(
            namespace=namespace,
            pod_name=task_pod_id,
            container_name=container_name
        )
        
    else:
        raise ValueError(f"Unsupported cluster type: {cluster_type}")
    
    # Analyze and store
    analysis = analyze_thread_dump(thread_dump)
    s3 = boto3.client('s3')
    timestamp = datetime.utcnow().strftime('%Y-%m-%d-%H-%M-%S')
    dump_key = f"thread-dumps/{task_pod_id}/{timestamp}.txt"
    analysis_key = f"thread-dumps/{task_pod_id}/{timestamp}_analysis.txt"
    
    s3.put_object(Bucket=s3_bucket, Key=dump_key, Body=thread_dump.encode('utf-8'))
    s3.put_object(Bucket=s3_bucket, Key=analysis_key, Body=analysis.encode('utf-8'))
    
    result = {
        'message': 'Thread dump handled from alert',
        'taskPodId': task_pod_id,
        'cluster': cluster_name,
        'threadDumpUrl': f"s3://{s3_bucket}/{dump_key}",
        'analysisUrl': f"s3://{s3_bucket}/{analysis_key}"
    }
    
    logger.info(json.dumps(result))
    return result

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        s3_bucket = os.environ['S3_BUCKET_NAME']
        
        # Check if this is a direct webhook call from Grafana
        if 'body' in event:
            logger.info("Processing direct webhook from Grafana")
            try:
                # Parse the webhook payload
                if isinstance(event['body'], str):
                    body = json.loads(event['body'])
                else:
                    body = event['body']
                
                alerts = body.get('alerts', [])
                if not alerts:
                    return {
                        'statusCode': 200,
                        'body': json.dumps({'message': 'No alerts in webhook payload'})
                    }
                
                results = []
                for alert in alerts:
                    if alert.get('status') != 'firing':
                        logger.info("Skipping resolved alert")
                        continue
                        
                    # Extract labels from Grafana alert
                    labels = alert.get('labels', {})
                    cluster_type = labels.get('cluster_type')
                    cluster_name = labels.get('cluster')
                    task_pod_id = labels.get('task_pod_id')
                    container_name = labels.get('container_name')
                    namespace = labels.get('namespace', 'default')
                    
                    # Validate inputs
                    if any(is_invalid(val) for val in [cluster_type, cluster_name, task_pod_id, container_name]):
                        logger.warning(f"Missing or invalid alert labels: cluster_type={cluster_type}, cluster={cluster_name}, task_pod_id={task_pod_id}, container_name={container_name}")
                        continue
                    
                    # Process the alert (reusing your existing logic)
                    result = process_alert(cluster_type, cluster_name, task_pod_id, container_name, namespace, s3_bucket)
                    results.append(result)
                
                if results:
                    return {
                        'statusCode': 200,
                        'body': json.dumps({'message': f'Processed {len(results)} alerts', 'results': results})
                    }
                else:
                    return {
                        'statusCode': 200,
                        'body': json.dumps({'message': 'No valid alerts to process'})
                    }
                    
            except Exception as e:
                logger.error(f"Error processing webhook: {str(e)}")
                return {
                    'statusCode': 500,
                    'body': json.dumps({'error': f"Error processing webhook: {str(e)}"})
                }
        
        # Original SNS handling logic
        elif 'Records' in event and event['Records'][0].get('Sns'):
            record = event['Records'][0]
            sns_message = record['Sns']['Message']
            message_json = json.loads(sns_message)
            
            # Process only alerts with status 'firing'
            for alert in message_json.get('alerts', []):
                if alert.get('status') != 'firing':
                    logger.info("Skipping resolved alert")
                    continue
                
                labels = alert.get('labels', {})
                cluster_type = labels.get('cluster_type')
                cluster_name = labels.get('cluster')
                task_pod_id = labels.get('task_pod_id')
                container_name = labels.get('container_name')
                namespace = labels.get('namespace', 'default')
                
                # Validate inputs
                if any(is_invalid(val) for val in [cluster_type, cluster_name, task_pod_id, container_name]):
                    raise ValueError(f"Missing or invalid alert labels: cluster_type={cluster_type}, cluster={cluster_name}, task_pod_id={task_pod_id}, container_name={container_name}")
                
                # Process the alert
                result = process_alert(cluster_type, cluster_name, task_pod_id, container_name, namespace, s3_bucket)
                
                return {
                    'statusCode': 200,
                    'body': json.dumps(result)
                }
            
            # No firing alerts found
            logger.info("No firing alerts to process")
            return {'statusCode': 204, 'body': json.dumps({'message': 'No active alerts'})}
        
        else:
            logger.warning("Event doesn't match expected formats")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid event format'})
            }
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}