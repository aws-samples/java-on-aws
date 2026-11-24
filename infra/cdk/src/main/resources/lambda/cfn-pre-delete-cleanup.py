# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import boto3
import time
import cfnresponse

ec2 = boto3.client('ec2')
s3 = boto3.client('s3')
s3_resource = boto3.resource('s3')

def lambda_handler(event, context):
    """
    Custom Resource handler to cleanup resources before stack deletion.
    - GuardDuty VPC endpoints that block VPC deletion
    - GuardDuty managed security groups
    - S3 buckets supplied by the stack
    Note: CloudWatch logs are kept for debugging/analysis
    """
    print(f"Event: {event}")

    request_type = event['RequestType']
    vpc_id = event['ResourceProperties'].get('VpcId', '')
    bucket_names = event['ResourceProperties'].get('BucketNames', [])

    try:
        if request_type == 'Delete':
            # Start VPC endpoint deletion (async)
            endpoint_ids = start_guardduty_endpoint_deletion(vpc_id)

            # While endpoints are deleting, clean up S3
            cleanup_s3_buckets(bucket_names)

            # Wait for VPC endpoint deletion to complete
            if endpoint_ids:
                wait_for_deletion(endpoint_ids, max_wait=300)

            # Delete GuardDuty security groups (after endpoints are deleted)
            cleanup_guardduty_security_groups(vpc_id)

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

def cleanup_guardduty_security_groups(vpc_id, max_retries=6, retry_delay=10):
    """Delete GuardDuty managed security groups for the VPC with retry logic."""
    if not vpc_id:
        print("No VPC ID provided, skipping security group cleanup")
        return

    try:
        # Find GuardDuty managed security groups by name pattern
        response = ec2.describe_security_groups(
            Filters=[
                {'Name': 'vpc-id', 'Values': [vpc_id]},
                {'Name': 'group-name', 'Values': [f'GuardDutyManagedSecurityGroup-{vpc_id}']}
            ]
        )

        security_groups = response.get('SecurityGroups', [])

        if not security_groups:
            print("No GuardDuty security groups found")
            return

        for sg in security_groups:
            sg_id = sg['GroupId']
            sg_name = sg['GroupName']
            print(f"Deleting GuardDuty security group: {sg_name} ({sg_id})")

            # Retry deletion - ENIs may take time to detach after endpoint deletion
            for attempt in range(max_retries):
                try:
                    ec2.delete_security_group(GroupId=sg_id)
                    print(f"Deleted security group: {sg_id}")
                    break
                except ec2.exceptions.ClientError as e:
                    if 'DependencyViolation' in str(e) and attempt < max_retries - 1:
                        print(f"Security group has dependencies, waiting {retry_delay}s (attempt {attempt + 1}/{max_retries})...")
                        time.sleep(retry_delay)
                    else:
                        print(f"Error deleting security group {sg_id}: {e}")
                        break

    except Exception as e:
        print(f"Error listing GuardDuty security groups: {e}")

    print("GuardDuty security group cleanup completed")

def cleanup_s3_buckets(bucket_names, attempts=6, retry_delay=10):
    """Empty and delete the S3 buckets supplied by the stack, each up to `attempts` times.
    Raises if a bucket remains, so the custom resource reports FAILED."""
    remaining = []
    for bucket_name in bucket_names:
        if not delete_bucket(bucket_name, attempts, retry_delay):
            remaining.append(bucket_name)
    if remaining:
        raise RuntimeError(f"S3 buckets not deleted: {remaining}")
    print("S3 bucket cleanup completed")

def delete_bucket(bucket_name, attempts, retry_delay):
    """Empty and delete one bucket. Returns True once the bucket is gone."""
    for attempt in range(1, attempts + 1):
        try:
            # Delete all object versions (handles both versioned and non-versioned buckets)
            s3_resource.Bucket(bucket_name).object_versions.delete()
            s3.delete_bucket(Bucket=bucket_name)
            print(f"Deleted bucket: {bucket_name}")
            return True
        except Exception as e:
            if getattr(e, 'response', {}).get('Error', {}).get('Code') == 'NoSuchBucket':
                print(f"Bucket already deleted: {bucket_name}")
                return True
            print(f"Attempt {attempt}/{attempts} for bucket {bucket_name}: {e}")
            if attempt < attempts:
                time.sleep(retry_delay)
    return False

def wait_for_deletion(endpoint_ids, max_wait=300):
    """Poll until endpoints are fully deleted (not just deleting) or timeout."""
    start_time = time.time()

    while time.time() - start_time < max_wait:
        try:
            response = ec2.describe_vpc_endpoints(VpcEndpointIds=endpoint_ids)
            endpoints = response.get('VpcEndpoints', [])

            # Wait for fully deleted state, not just deleting
            remaining = [ep for ep in endpoints if ep['State'] != 'deleted']

            if not remaining:
                print("All endpoints fully deleted")
                return

            states = {ep['VpcEndpointId']: ep['State'] for ep in remaining}
            print(f"Waiting for endpoints: {states}")
            time.sleep(10)
        except ec2.exceptions.ClientError as e:
            if 'InvalidVpcEndpointId.NotFound' in str(e):
                print("All endpoints deleted (not found)")
                return
            raise

    print(f"Timeout waiting for endpoint deletion after {max_wait}s")
