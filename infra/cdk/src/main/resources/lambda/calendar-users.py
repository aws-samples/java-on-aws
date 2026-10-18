# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Custom resource: creates the calendar users (resource property Usernames) in the calendar user pool
# with a verified <user>@example.com email and the IDE password (secret PasswordSecretArn) as their
# permanent password. Delete is a no-op: the users go with the user pool.

import boto3
import json
import traceback
import cfnresponse

cognito = boto3.client('cognito-idp')
secretsmanager = boto3.client('secretsmanager')


def lambda_handler(event, context):
    print(f"RequestType: {event['RequestType']}")
    physical_id = event.get('PhysicalResourceId', 'CalendarUsers')
    try:
        if event['RequestType'] in ('Create', 'Update'):
            props = event['ResourceProperties']
            pool_id = props['UserPoolId']
            secret = secretsmanager.get_secret_value(SecretId=props['PasswordSecretArn'])
            password = json.loads(secret['SecretString'])['password']
            for username in props['Usernames']:
                try:
                    cognito.admin_get_user(UserPoolId=pool_id, Username=username)
                except cognito.exceptions.UserNotFoundException:
                    cognito.admin_create_user(UserPoolId=pool_id, Username=username, MessageAction='SUPPRESS',
                                              UserAttributes=[{'Name': 'email', 'Value': f'{username}@example.com'},
                                                              {'Name': 'email_verified', 'Value': 'true'}])
                cognito.admin_set_user_password(UserPoolId=pool_id, Username=username, Password=password,
                                                Permanent=True)
                print(f'User {username} ready')
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {}, physical_id)
    except Exception:
        tb = traceback.format_exc()
        print(tb)
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': tb[-500:]}, physical_id)
