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
        secret_name = "unicornstore-ide-password-lambda"
        region_name = os.environ.get('AWS_REGION', 'us-east-1')

        session = boto3.session.Session()
        client = session.client(
            service_name='secretsmanager',
            region_name=region_name
        )

        response = client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])

        # Expected credentials: username is 'grafana-alerts', password from secret
        expected_username = "grafana-alerts"
        expected_password = secret['password']

        # Validate credentials
        if username != expected_username or password != expected_password:
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

def extract_all_metrics_from_valuestring(value_string: str) -> list:
    """Extract all metric information from Grafana alert valueString"""
    try:
        logger.info(f"Extracting all metrics from valueString: {value_string}")

        # Find all metric entries in the valueString
        # Pattern: [ var='...' metric='...' labels={...} value=... ]
        import re
        metric_pattern = r'\[\s*var=\'[^\']+\'\s*metric=\'[^\']+\'\s*labels=\{([^}]+)\}\s*value=(\d+)\s*\]'
        matches = re.findall(metric_pattern, value_string)

        if not matches:
            logger.warning("Could not find any metric entries in valueString")
            return []

        results = []
        for i, (labels_str, value) in enumerate(matches):
            logger.info(f"Processing metric {i+1}: labels={{{labels_str}}} value={value}")

            # Parse individual labels from the labels section
            labels = {}
            for label_pair in labels_str.split(', '):
                if '=' in label_pair:
                    key, label_value = label_pair.split('=', 1)
                    labels[key.strip()] = label_value.strip()

            logger.info(f"All parsed labels for metric {i+1}: {labels}")

            # Map the labels to our expected keys
            task_pod_id = labels.get('task_pod_id')
            # Use pod if task_pod_id is missing, empty, or "unknown"
            if not task_pod_id or task_pod_id == 'unknown':
                task_pod_id = labels.get('pod')

            result = {
                'cluster': labels.get('cluster'),
                'cluster_type': labels.get('cluster_type'),
                'container_name': labels.get('container_name'),
                'task_pod_id': task_pod_id,
                'namespace': labels.get('namespace'),
                'container_ip': labels.get('container_ip') or labels.get('exported_instance'),
                'thread_count': int(value)
            }

            logger.info(f"Final extracted values for metric {i+1}: {result}")
            results.append(result)

        return results
    except Exception as e:
        logger.error(f"Error extracting metrics from valueString: {str(e)}")
        return []

def analyze_thread_dump(thread_dump: str) -> str:
    region_name = os.environ.get('AWS_REGION', 'us-east-1')
    bedrock = boto3.client("bedrock-runtime", region_name=region_name)

    logger.info(f"Using Bedrock in region: {bedrock.meta.region_name}")
    prompt = f"""You are an expert in Java performance analysis with extensive experience diagnosing production issues.

Analyze the following Java thread dump and return your findings as a comprehensive Markdown document with these sections:

1. **Executive Summary**
   - Provide a concise 2-3 sentence overview of the thread dump health
   - Highlight the most critical issue identified
   - Include an overall system health assessment (Healthy/Degraded/Critical)

2. **Summary of Thread States**
   - Count and list all thread states (RUNNABLE, WAITING, BLOCKED, etc.)
   - Include totals and percentages for each state
   - Present a simple ASCII chart or table showing the distribution
   - Note any unusual state distributions that might indicate problems

3. **Key Issues Identified**
   For each issue, include:
   - Issue description with severity rating (Critical/High/Medium/Low)
   - Confidence level in the diagnosis (High/Medium/Low)
   - Affected threads (count and examples)
   - Potential business impact

   Look specifically for:
   - Deadlocks or potential deadlocks
   - Resource contention patterns
   - Threads blocked on synchronization
   - Excessive CPU usage patterns
   - Thread pool saturation
   - Database connection issues
   - I/O bottlenecks
   - Common framework-specific issues (Spring, Hibernate, etc.)

4. **Optimization Recommendations**
   Provide actionable recommendations organized by:
   - Immediate actions (can be implemented quickly with low risk)
   - Short-term improvements (days to implement)
   - Long-term architectural changes (if applicable)

   Include for each recommendation:
   - Specific code, configuration, or architectural changes
   - Expected impact level (High/Medium/Low)
   - Implementation complexity (High/Medium/Low)

   Consider these areas:
   - Thread pool sizing and configuration
   - Synchronization and locking strategies
   - Database query and connection handling
   - Garbage collection tuning
   - Resource allocation
   - Caching strategies
   - Asynchronous processing opportunities

5. **Detailed Analysis of Critical Threads**
   For the 3-5 most problematic threads:
   - Thread name, ID, and state
   - Relevant stack trace snippet (focus on most important frames)
   - Explanation of why this thread is significant
   - What normal behavior would look like
   - Other threads with similar patterns or related issues
   - Specific code areas that should be investigated

6. **System Context Analysis**
   - Identify patterns across multiple threads suggesting systemic issues
   - Note any evidence of recent garbage collection activity
   - Identify potential memory issues (if detectable from thread patterns)
   - Comment on thread creation patterns and lifecycle management

If the thread dump appears incomplete or insufficient for complete analysis, clearly state this limitation and what additional information would be helpful.

**Thread Dump Input**:
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
                modelId="global.anthropic.claude-sonnet-4-20250514-v1:0",
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

                        # Try to extract all metrics from valueString
                        if 'valueString' in alert:
                            extracted_metrics = extract_all_metrics_from_valuestring(alert['valueString'])
                            logger.info(f"Extracted {len(extracted_metrics)} metrics from valueString")

                            # Process each metric separately
                            for i, metric_info in enumerate(extracted_metrics):
                                logger.info(f"Processing metric {i+1}: {metric_info}")

                                # Use extracted values for this metric
                                metric_cluster_type = metric_info.get('cluster_type')
                                metric_cluster_name = metric_info.get('cluster')
                                metric_task_pod_id = metric_info.get('task_pod_id')
                                metric_container_name = metric_info.get('container_name')
                                metric_namespace = metric_info.get('namespace', 'default')
                                metric_container_ip = metric_info.get('container_ip')

                                # Validate this metric's inputs
                                if any(is_invalid(val) for val in [metric_cluster_type, metric_cluster_name, metric_task_pod_id, metric_container_name]):
                                    logger.warning(f"Skipping metric {i+1} due to missing values: cluster_type={metric_cluster_type}, cluster={metric_cluster_name}, task_pod_id={metric_task_pod_id}, container_name={metric_container_name}")
                                    continue

                                # Process this metric
                                try:
                                    result = process_alert(metric_cluster_type, metric_cluster_name, metric_task_pod_id, metric_container_name, metric_namespace, s3_bucket, metric_container_ip)
                                    results.append(result)
                                    logger.info(f"Successfully processed metric {i+1}")
                                except Exception as e:
                                    logger.error(f"Error processing metric {i+1}: {str(e)}")
                                    continue

                            # Skip the original single-metric processing since we handled all metrics
                            continue

                    # Original single-metric processing (fallback)
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
