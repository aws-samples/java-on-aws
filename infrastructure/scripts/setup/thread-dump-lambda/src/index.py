import json
import logging
import os
import boto3
import requests
import time
import random
import re
import base64
from datetime import datetime
from typing import Dict, Any
from kubernetes import client, config
from botocore.exceptions import ClientError
from eks_client import EKSClient  # Your own implementation

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def is_invalid(value: str) -> bool:
    return value is None or value.strip() in ["", "[no value]"]

def verify_basic_auth(event: Dict[str, Any]) -> bool:
    """
    Verify Basic Authentication credentials from the request headers.
    Returns True if authentication is successful, False otherwise.
    """
    try:
        # Get headers from the event
        headers = event.get('headers', {})
        if not headers:
            logger.warning("No headers found in the request")
            return False

        # Look for authorization header (case-insensitive)
        auth_header = None
        for key in headers:
            if key.lower() == 'authorization':
                auth_header = headers[key]
                break

        if not auth_header or not auth_header.startswith('Basic '):
            logger.warning("No Basic Authorization header found")
            return False

        # Extract and decode credentials
        encoded_credentials = auth_header.split(' ')[1]
        decoded_credentials = base64.b64decode(encoded_credentials).decode('utf-8')
        username, password = decoded_credentials.split(':')

        # Get expected credentials from AWS Secrets Manager
        secret_name = "grafana-webhook-credentials"
        region_name = os.environ.get('AWS_REGION', 'us-east-1')

        session = boto3.session.Session()
        client = session.client(
            service_name='secretsmanager',
            region_name=region_name
        )

        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])

        # Validate credentials
        if username != secret['username'] or password != secret['password']:
            logger.warning("Invalid credentials provided")
            return False

        logger.info("Authentication successful")
        return True

    except ClientError as e:
        logger.error(f"Error retrieving credentials from Secrets Manager: {str(e)}")
        return False
    except Exception as e:
        logger.error(f"Authentication error: {str(e)}")
        return False

def extract_pod_info_from_valuestring(value_string: str) -> Dict[str, str]:
    """Extract pod information from Grafana alert valueString"""
    try:
        logger.info(f"Extracting pod info from valueString: {value_string}")

        # First, extract the labels section
        labels_match = re.search(r'labels=\{([^}]+)\}', value_string)
        if not labels_match:
            logger.warning("Could not find labels section in valueString")
            return {}

        labels_str = labels_match.group(1)
        logger.info(f"Extracted labels section: {labels_str}")

        # Now extract individual labels from the labels section
        labels = {}
        for label_pair in labels_str.split(', '):
            if '=' in label_pair:
                key, value = label_pair.split('=', 1)
                labels[key.strip()] = value.strip()
                logger.info(f"Parsed label: {key.strip()}={value.strip()}")

        logger.info(f"All parsed labels: {labels}")

        # Map the labels to our expected keys
        result = {
            'cluster': labels.get('cluster'),
            'cluster_type': labels.get('cluster_type'),
            'container_name': labels.get('container_name'),
            'task_pod_id': labels.get('task_pod_id') or labels.get('pod'),  # Use pod if task_pod_id not found
            'namespace': labels.get('namespace'),
            'container_ip': labels.get('container_ip') or labels.get('exported_instance')  # Add container_ip extraction
        }

        logger.info(f"Final extracted values: {result}")
        return result
    except Exception as e:
        logger.error(f"Error extracting pod info from valueString: {str(e)}")
        return {}

def analyze_thread_dump(thread_dump: str) -> str:
    region_name = os.environ.get('AWS_REGION', 'us-east-1')
    bedrock = boto3.client("bedrock-runtime", region_name=region_name)

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
        "max_tokens": 8192,
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
                modelId="us.anthropic.claude-3-7-sonnet-20250219-v1:0",
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


def process_alert(cluster_type, cluster_name, task_pod_id, container_name, namespace, s3_bucket, container_ip=None):
    """Extract the alert processing logic into a separate function for reuse"""
    # Get the thread dump based on cluster type
    if cluster_type == 'ecs':
        if container_ip:
            # Use the container_ip provided in the alert
            logger.info(f"Using container IP from alert: {container_ip}")
        else:
            # Fallback to getting IP from ECS API
            ecs_client = ECSClient(cluster_name)
            container_ip = ecs_client.get_container_ip(task_pod_id)

        response = requests.get(f"http://{container_ip}:8080/actuator/threaddump", timeout=10)
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

    # Use environment variable for S3 prefix, fallback to hardcoded value
    s3_prefix = os.environ.get('S3_THREAD_DUMPS_PREFIX', 'thread-dumps/')
    if not s3_prefix.endswith('/'):
        s3_prefix += '/'

    dump_key = f"{s3_prefix}{task_pod_id}/{timestamp}.txt"
    analysis_key = f"{s3_prefix}{task_pod_id}/{timestamp}_analysis.md"

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

            # Verify authentication for webhook calls
            if not verify_basic_auth(event):
                logger.warning("Authentication failed")
                return {
                    'statusCode': 401,
                    'headers': {'WWW-Authenticate': 'Basic'},
                    'body': json.dumps({'error': 'Authentication failed'})
                }

            try:
                # Parse the webhook payload
                if isinstance(event['body'], str):
                    body = json.loads(event['body'])
                else:
                    body = event['body']

                # Rest of your webhook handling code remains the same
                alerts = body.get('alerts', [])
                if not alerts:
                    return {
                        'statusCode': 200,
                        'body': json.dumps({'message': 'No alerts in webhook payload'})
                    }

                results = []
                for alert in alerts:
                    # Your existing alert processing code...
                    # No changes needed here
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
                    container_ip = labels.get('instance')  # Get container_ip from the instance label

                    # Check if we need to extract from valueString
                    if any(is_invalid(val) for val in [cluster_type, cluster_name, task_pod_id, container_name]):
                        logger.info("Some labels are missing or invalid, trying to extract from valueString")

                        # Try to extract from valueString
                        if 'valueString' in alert:
                            extracted_info = extract_pod_info_from_valuestring(alert['valueString'])
                            logger.info(f"Raw extracted info: {extracted_info}")

                            # Update missing values
                            if is_invalid(cluster_type) and extracted_info.get('cluster_type'):
                                cluster_type = extracted_info['cluster_type']

                            if is_invalid(cluster_name) and extracted_info.get('cluster'):
                                cluster_name = extracted_info['cluster']

                            if is_invalid(task_pod_id) and extracted_info.get('task_pod_id'):
                                task_pod_id = extracted_info['task_pod_id']

                            if is_invalid(container_name) and extracted_info.get('container_name'):
                                container_name = extracted_info['container_name']

                            if is_invalid(container_ip) and extracted_info.get('container_ip'):
                                container_ip = extracted_info['container_ip']
                                logger.info(f"Using container_ip from valueString: {container_ip}")

                            # IMPORTANT: Always override namespace with extracted value if available
                            if extracted_info.get('namespace'):
                                namespace = extracted_info['namespace']
                                logger.info(f"Overriding namespace with extracted value: {namespace}")

                            logger.info(f"Final extracted values: cluster_type={cluster_type}, cluster={cluster_name}, task_pod_id={task_pod_id}, container_name={container_name}, namespace={namespace}")

                    # Validate inputs after extraction attempt
                    if any(is_invalid(val) for val in [cluster_type, cluster_name, task_pod_id, container_name]):
                        logger.warning(f"Still missing or invalid alert labels after extraction: cluster_type={cluster_type}, cluster={cluster_name}, task_pod_id={task_pod_id}, container_name={container_name}")
                        continue

                    # Process the alert (reusing your existing logic)
                    result = process_alert(cluster_type, cluster_name, task_pod_id, container_name, namespace, s3_bucket, container_ip)
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

                # Check if we need to extract from valueString (adding the same logic to SNS handling)
                if any(is_invalid(val) for val in [cluster_type, cluster_name, task_pod_id, container_name]):
                    logger.info("Some labels are missing or invalid in SNS message, trying to extract from valueString")

                    # Try to extract from valueString
                    if 'valueString' in alert:
                        extracted_info = extract_pod_info_from_valuestring(alert['valueString'])

                        # Update missing values
                        if is_invalid(cluster_type) and 'cluster_type' in extracted_info:
                            cluster_type = extracted_info['cluster_type']

                        if is_invalid(cluster_name) and 'cluster' in extracted_info:
                            cluster_name = extracted_info['cluster']

                        if is_invalid(task_pod_id) and 'task_pod_id' in extracted_info:
                            task_pod_id = extracted_info['task_pod_id']

                        if is_invalid(container_name) and 'container_name' in extracted_info:
                            container_name = extracted_info['container_name']

                        if is_invalid(namespace) and 'namespace' in extracted_info:
                            namespace = extracted_info['namespace']

                        logger.info(f"Extracted values from valueString in SNS: cluster_type={cluster_type}, cluster={cluster_name}, task_pod_id={task_pod_id}, container_name={container_name}, namespace={namespace}")

                # Validate inputs after extraction attempt
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

        # Direct invocation (non-webhook, non-SNS)
        else:
            # Check if this is a direct invocation with parameters
            cluster_type = event.get('cluster_type')
            cluster_name = event.get('cluster')
            task_pod_id = event.get('task_pod_id')
            container_name = event.get('container_name')
            namespace = event.get('namespace', 'default')

            # Validate inputs
            if any(is_invalid(val) for val in [cluster_type, cluster_name, task_pod_id, container_name]):
                logger.warning("Event doesn't match expected formats and is missing required parameters")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Invalid event format or missing required parameters'})
                }

            # Process direct invocation
            result = process_alert(cluster_type, cluster_name, task_pod_id, container_name, namespace, s3_bucket)
            return {
                'statusCode': 200,
                'body': json.dumps(result)
            }

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}