import traceback
import cfnresponse
import boto3
import json

def get_cluster_arn(cluster_id, region, account_id):
    return f"arn:aws:rds:{region}:{account_id}:cluster:{cluster_id}"

def lambda_handler(event, context):
    print('Event: {}'.format(event))
    print('context: {}'.format(context))
    responseData = {}
    status = cfnresponse.SUCCESS

    if event['RequestType'] == 'Delete':
        cfnresponse.send(event, context, status, responseData, 'CustomResourcePhysicalID')
    else:
        try:
            # Get secret name and SQL from resource properties
            secret_name = event['ResourceProperties']['SecretName']
            sql_statements = event['ResourceProperties']['SqlStatements']

            # Get AWS account ID and region
            sts = boto3.client('sts')
            caller_identity = sts.get_caller_identity()
            account_id = caller_identity['Account']
            region = boto3.session.Session().region_name
            caller_arn = caller_identity['Arn']
            print(f"Account ID: {account_id}, Region: {region}")
            print(f"Caller ARN: {caller_arn}")

            # Get the secret
            secretsmanager = boto3.client('secretsmanager')
            secret_details = secretsmanager.describe_secret(
                SecretId=secret_name
            )
            secret_arn = secret_details['ARN']
            print(f"Secret ARN: {secret_arn}")

            secret_response = secretsmanager.get_secret_value(
                SecretId=secret_name
            )

            # Parse the secret JSON
            secret = json.loads(secret_response['SecretString'])
            # print(f"Secret: {secret}")

            # Construct cluster ARN
            cluster_arn = get_cluster_arn(
                secret['dbClusterIdentifier'],
                region,
                account_id
            )
            print(f"Cluster ARN: {cluster_arn}")

            # Initialize RDS Data API client
            rds_data = boto3.client('rds-data')

            # Execute each SQL statement
            for sql in sql_statements.split(';'):
                sql = sql.strip()
                if sql:  # Skip empty statements
                    try:
                        response = rds_data.execute_statement(
                            resourceArn=cluster_arn,
                            secretArn=secret_arn,
                            database=secret['dbname'],
                            sql=sql
                        )
                        print(f"Executed SQL: {sql}")
                        print(f"Response: {response}")
                    except Exception as sql_error:
                        print(f"Error executing SQL: {sql}")
                        print(f"Error: {str(sql_error)}")
                        raise sql_error

            responseData = {'Success': 'Finished database setup.'}

        except Exception as e:
            status = cfnresponse.FAILED
            tb_err = traceback.format_exc()
            print(tb_err)
            responseData = {'Error': tb_err}
        finally:
            cfnresponse.send(event, context, status, responseData, 'CustomResourcePhysicalID')
