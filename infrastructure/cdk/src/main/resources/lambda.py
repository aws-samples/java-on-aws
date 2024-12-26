from __future__ import print_function
import boto3
import json
import os
import time
import traceback
import cfnresponse
from botocore.exceptions import WaiterError

def lambda_handler(event, context):
    print('Event: {}'.format(event))
    print('context: {}'.format(context))
    responseData = {}

    status = cfnresponse.SUCCESS

    if event['RequestType'] == 'Delete':
        responseData = {'Success': 'Custom Resource removed'}
        cfnresponse.send(event, context, status, responseData, 'CustomResourcePhysicalID')
    else:
        try:
            # Open AWS clients
            ec2 = boto3.client('ec2')
            ssm = boto3.client('ssm')

            instance_id = event['ResourceProperties']['InstanceId']

            print('Waiting for the instance to be ready...')
            # Wait for Instance to become ready
            instance_state = 'unknown'
            print('Instance is currently in state'.format(instance_state))
            while instance_state != 'running':
                time.sleep(5)
                di = ec2.describe_instances(InstanceIds=[instance_id])
                instance_state = di['Reservations'][0]['Instances'][0]['State']['Name']
                print('Waiting for instance in state: {}'.format(instance_state))

            print('Instance is ready')

            print('Waiting for instance to come online in SSM...')
            for i in range(1, 60):
              response = ssm.describe_instance_information(Filters=[{'Key': 'InstanceIds', 'Values': [instance_id]}])
              if len(response["InstanceInformationList"]) == 0:
                print('No instances in SSM')
              elif len(response["InstanceInformationList"]) > 0 and \
                    response["InstanceInformationList"][0]["PingStatus"] == "Online" and \
                    response["InstanceInformationList"][0]["InstanceId"] == instance_id:
                print('Instance is online in SSM')
                break
              time.sleep(10)

            ssm_document = event['ResourceProperties']['SsmDocument']

            ssm.send_command(
                InstanceIds=[instance_id],
                DocumentName=ssm_document,
                CloudWatchOutputConfig={
                    'CloudWatchLogGroupName': event['ResourceProperties']['LogGroupName'],
                    'CloudWatchOutputEnabled': True
                })

            responseData = {'Success': 'Started bootstrapping for instance: '+instance_id}
        except Exception as e:
            status = cfnresponse.FAILED
            tb_err = traceback.format_exc()
            print(tb_err)
            responseData = {'Error': tb_err}
        finally:
            cfnresponse.send(event, context, status, responseData, 'CustomResourcePhysicalID')