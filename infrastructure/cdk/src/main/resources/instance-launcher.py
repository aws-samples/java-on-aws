import boto3
import traceback
import cfnresponse

ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    print(f'Event: {event}')
    responseData = {}
    status = cfnresponse.SUCCESS
    physical_id = event.get('PhysicalResourceId', 'InstanceLauncher')

    try:
        if event['RequestType'] == 'Delete':
            # Terminate the instance if it exists
            instance_id = event.get('PhysicalResourceId')
            if instance_id and instance_id.startswith('i-'):
                try:
                    ec2.terminate_instances(InstanceIds=[instance_id])
                    print(f'Terminated instance: {instance_id}')
                except Exception as e:
                    print(f'Error terminating instance: {e}')
            responseData = {'Message': 'Instance terminated'}
            cfnresponse.send(event, context, status, responseData, physical_id)
            return

        if event['RequestType'] == 'Update':
            # For updates, return existing instance
            instance_id = event.get('PhysicalResourceId')
            if instance_id and instance_id.startswith('i-'):
                responseData = {'InstanceId': instance_id}
                cfnresponse.send(event, context, status, responseData, instance_id)
                return

        # Create new instance
        props = event['ResourceProperties']
        subnet_ids = props['SubnetIds'].split(',')
        instance_types = props['InstanceTypes'].split(',')

        instance_id = None
        last_error = None

        # Try each instance type across all AZs
        for instance_type in instance_types:
            for subnet_id in subnet_ids:
                try:
                    print(f'Attempting to launch {instance_type} in subnet {subnet_id}')

                    response = ec2.run_instances(
                        ImageId=props['ImageId'],
                        InstanceType=instance_type,
                        SubnetId=subnet_id,
                        SecurityGroupIds=props['SecurityGroupIds'].split(','),
                        IamInstanceProfile={'Arn': props['IamInstanceProfileArn']},
                        BlockDeviceMappings=[{
                            'DeviceName': '/dev/xvda',
                            'Ebs': {
                                'VolumeSize': int(props['VolumeSize']),
                                'VolumeType': 'gp3',
                                'DeleteOnTermination': True,
                                'Encrypted': True
                            }
                        }],
                        TagSpecifications=[{
                            'ResourceType': 'instance',
                            'Tags': [
                                {'Key': 'Name', 'Value': props['InstanceName']}
                            ]
                        }],
                        UserData=props.get('UserData', ''),
                        MinCount=1,
                        MaxCount=1
                    )

                    instance_id = response['Instances'][0]['InstanceId']
                    print(f'Successfully launched instance {instance_id} ({instance_type} in {subnet_id})')

                    responseData = {
                        'InstanceId': instance_id,
                        'InstanceType': instance_type,
                        'SubnetId': subnet_id
                    }
                    cfnresponse.send(event, context, status, responseData, instance_id)
                    return

                except Exception as e:
                    error_msg = str(e)
                    print(f'Failed to launch {instance_type} in {subnet_id}: {error_msg}')

                    # Check if it's a retryable error (capacity or instance type issues)
                    retryable_errors = [
                        'InsufficientInstanceCapacity',  # No capacity in AZ
                        'Unsupported',                    # Instance type not supported
                        'InstanceLimitExceeded',          # Hit instance limit
                        'VcpuLimitExceeded',              # Hit vCPU limit
                        'InvalidParameterValue',          # Invalid instance type or config
                    ]

                    if any(err in error_msg for err in retryable_errors):
                        last_error = error_msg
                        continue  # Try next combination
                    else:
                        # Other error (permissions, network, etc), fail immediately
                        raise

        # All attempts failed
        status = cfnresponse.FAILED
        responseData = {'Error': f'No capacity available. Last error: {last_error}'}

    except Exception as e:
        status = cfnresponse.FAILED
        tb_err = traceback.format_exc()
        print(tb_err)
        responseData = {'Error': tb_err}

    cfnresponse.send(event, context, status, responseData, physical_id)
