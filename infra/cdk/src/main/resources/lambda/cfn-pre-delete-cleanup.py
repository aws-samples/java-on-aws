import boto3
import time
import cfnresponse

ec2 = boto3.client('ec2')
logs = boto3.client('logs')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Custom Resource handler to cleanup resources before stack deletion.
    - GuardDuty VPC endpoints that block VPC deletion
    - CloudWatch log groups with workshop- or unicornstore- prefix
    - S3 bucket contents for workshop- buckets
    """
    print(f"Event: {event}")

    request_type = event['RequestType']
    vpc_id = event['ResourceProperties'].get('VpcId', '')

    try:
        if request_type == 'Delete':
            # Start VPC endpoint deletion (async)
            endpoint_ids = start_guardduty_endpoint_deletion(vpc_id)

            # While endpoints are deleting, clean up logs and S3
            cleanup_cloudwatch_logs()
            cleanup_s3_buckets()

            # Wait for VPC endpoint deletion to complete
            if endpoint_ids:
                wait_for_deletion(endpoint_ids, max_wait=300)

        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"Error: {e}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': str(e)})

def start_guardduty_endpoint_deletion(vpc_id):
    """Find and start deletion of GuardDuty VPC endpoints."""

    # Find GuardDuty data endpoints
    filters = [{'Name': 'service-name', 'Values': ['*guardduty-data*']}]
    if vpc_id:
        filters.append({'Name': 'vpc-id', 'Values': [vpc_id]})

    response = ec2.describe_vpc_endpoints(Filters=filters)
    endpoints = response.get('VpcEndpoints', [])

    if not endpoints:
        print("No GuardDuty endpoints found")
        return []

    endpoint_ids = [ep['VpcEndpointId'] for ep in endpoints]
    print(f"Found GuardDuty endpoints: {endpoint_ids}")

    # Start deletion (don't wait yet)
    for endpoint_id in endpoint_ids:
        print(f"Deleting endpoint: {endpoint_id}")
        try:
            ec2.delete_vpc_endpoints(VpcEndpointIds=[endpoint_id])
        except Exception as e:
            print(f"Error deleting {endpoint_id}: {e}")

    return endpoint_ids

def cleanup_cloudwatch_logs():
    """Delete CloudWatch log groups with workshop- or unicornstore- prefix."""
    prefixes = ['workshop-', 'unicornstore-', '/aws/lambda/workshop-', '/aws/lambda/unicornstore-']

    for prefix in prefixes:
        try:
            paginator = logs.get_paginator('describe_log_groups')
            for page in paginator.paginate(logGroupNamePrefix=prefix):
                for log_group in page.get('logGroups', []):
                    log_group_name = log_group['logGroupName']
                    print(f"Deleting log group: {log_group_name}")
                    try:
                        logs.delete_log_group(logGroupName=log_group_name)
                    except Exception as e:
                        print(f"Error deleting log group {log_group_name}: {e}")
        except Exception as e:
            print(f"Error listing log groups with prefix {prefix}: {e}")

    print("CloudWatch log cleanup completed")

def cleanup_s3_buckets():
    """Empty S3 buckets with workshop- prefix."""
    try:
        response = s3.list_buckets()
        for bucket in response.get('Buckets', []):
            bucket_name = bucket['Name']
            if bucket_name.startswith('workshop-'):
                print(f"Emptying S3 bucket: {bucket_name}")
                empty_bucket(bucket_name)
    except Exception as e:
        print(f"Error listing S3 buckets: {e}")

    print("S3 bucket cleanup completed")

def empty_bucket(bucket_name):
    """Delete all objects and versions from a bucket."""
    try:
        # Delete all object versions (for versioned buckets)
        paginator = s3.get_paginator('list_object_versions')
        try:
            for page in paginator.paginate(Bucket=bucket_name):
                objects_to_delete = []

                # Collect versions
                for version in page.get('Versions', []):
                    objects_to_delete.append({
                        'Key': version['Key'],
                        'VersionId': version['VersionId']
                    })

                # Collect delete markers
                for marker in page.get('DeleteMarkers', []):
                    objects_to_delete.append({
                        'Key': marker['Key'],
                        'VersionId': marker['VersionId']
                    })

                if objects_to_delete:
                    s3.delete_objects(
                        Bucket=bucket_name,
                        Delete={'Objects': objects_to_delete}
                    )
                    print(f"Deleted {len(objects_to_delete)} objects from {bucket_name}")
        except s3.exceptions.ClientError as e:
            # Bucket might not have versioning, try regular delete
            if 'NoSuchBucket' not in str(e):
                delete_objects_without_versions(bucket_name)

    except Exception as e:
        print(f"Error emptying bucket {bucket_name}: {e}")

def delete_objects_without_versions(bucket_name):
    """Delete objects from non-versioned bucket."""
    try:
        paginator = s3.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=bucket_name):
            objects = page.get('Contents', [])
            if objects:
                objects_to_delete = [{'Key': obj['Key']} for obj in objects]
                s3.delete_objects(
                    Bucket=bucket_name,
                    Delete={'Objects': objects_to_delete}
                )
                print(f"Deleted {len(objects_to_delete)} objects from {bucket_name}")
    except Exception as e:
        print(f"Error deleting objects from {bucket_name}: {e}")

def wait_for_deletion(endpoint_ids, max_wait=300):
    """Poll until endpoints are deleted or timeout."""
    start_time = time.time()

    while time.time() - start_time < max_wait:
        try:
            response = ec2.describe_vpc_endpoints(VpcEndpointIds=endpoint_ids)
            remaining = [ep for ep in response.get('VpcEndpoints', [])
                        if ep['State'] not in ['deleted', 'deleting']]

            if not remaining:
                print("All endpoints deleted")
                return

            print(f"Waiting for {len(remaining)} endpoints to delete...")
            time.sleep(10)
        except ec2.exceptions.ClientError as e:
            if 'InvalidVpcEndpointId.NotFound' in str(e):
                print("All endpoints deleted")
                return
            raise

    print(f"Timeout waiting for endpoint deletion after {max_wait}s")
