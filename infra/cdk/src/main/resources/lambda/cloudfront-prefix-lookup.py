from __future__ import print_function
import boto3
import traceback
import cfnresponse

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

            res = ec2.describe_managed_prefix_lists(
               Filters=[{
                  'Name': 'prefix-list-name',
                  'Values': ['com.amazonaws.global.cloudfront.origin-facing']
               }]
            )

            responseData = {'PrefixListId': str(res['PrefixLists'][0]['PrefixListId'])}
        except Exception as e:
            status = cfnresponse.FAILED
            tb_err = traceback.format_exc()
            print(tb_err)
            responseData = {'Error': tb_err}
        finally:
            cfnresponse.send(event, context, status, responseData, 'CustomResourcePhysicalID')