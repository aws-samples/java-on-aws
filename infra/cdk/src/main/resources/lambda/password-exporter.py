import boto3
import json
import traceback
import cfnresponse

secretsmanager = boto3.client('secretsmanager')

def lambda_handler(event, context):
    print(f'Event: {event}')
    responseData = {}
    status = cfnresponse.SUCCESS
    physical_id = event.get('PhysicalResourceId', 'PasswordExporter')

    try:
        if event['RequestType'] == 'Delete':
            # Nothing to clean up for password export
            responseData = {'Message': 'Password exporter deleted'}
            cfnresponse.send(event, context, status, responseData, physical_id)
            return

        if event['RequestType'] in ['Create', 'Update']:
            # Get password from Secrets Manager
            props = event['ResourceProperties']
            password_name = props['PasswordName']

            print(f'Retrieving password from secret: {password_name}')

            response = secretsmanager.get_secret_value(SecretId=password_name)
            secret_data = json.loads(response['SecretString'])

            # Return the password value for CloudFormation output
            responseData = {
                'password': secret_data['password']
            }

            print('Successfully retrieved password from Secrets Manager')

    except Exception as e:
        status = cfnresponse.FAILED
        tb_err = traceback.format_exc()
        print(tb_err)
        responseData = {'Error': tb_err}

    cfnresponse.send(event, context, status, responseData, physical_id)