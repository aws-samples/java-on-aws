import traceback
import cfnresponse
import boto3
import json

def lambda_handler(event, context):
    print('Event: {}'.format(event))
    print('context: {}'.format(context))
    responseData = {}

    status = cfnresponse.SUCCESS

    if event['RequestType'] == 'Delete':
        cfnresponse.send(event, context, status, responseData, 'CustomResourcePhysicalID')
    else:
        try:
            passwordName = event['ResourceProperties']['PasswordName']

            secretsmanager = boto3.client('secretsmanager')

            response = secretsmanager.get_secret_value(
                SecretId=passwordName,
            )

            responseData = json.loads(response['SecretString'])
        except Exception as e:
            status = cfnresponse.FAILED
            tb_err = traceback.format_exc()
            print(tb_err)
            responseData = {'Error': tb_err}
        finally:
            cfnresponse.send(event, context, status, responseData, 'CustomResourcePhysicalID')