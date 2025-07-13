import traceback
import cfnresponse
import boto3
import json
import time
from botocore.exceptions import ClientError

def get_cluster_arn(cluster_id, region, account_id):
    return f"arn:aws:rds:{region}:{account_id}:cluster:{cluster_id}"

def wait_for_database_availability(rds_data, cluster_arn, secret_arn, database, max_attempts=10, delay=5):
    """Wait for the database to become available"""
    for attempt in range(1, max_attempts + 1):
        try:
            print(f"Checking database availability (attempt {attempt}/{max_attempts})...")
            rds_data.execute_statement(
                resourceArn=cluster_arn,
                secretArn=secret_arn,
                database=database,
                sql="SELECT 1"
            )
            print("Database is available!")
            return True
        except Exception as e:
            print(f"Database not yet available: {str(e)}. Retrying in {delay} seconds...")
            time.sleep(delay)

    print(f"Database did not become available after {max_attempts} attempts")
    return False

def execute_sql_with_retry(rds_data, cluster_arn, secret_arn, database, sql, max_retries=5, backoff_factor=2):
    """Execute SQL with exponential backoff retry logic"""
    retry_count = 0

    while retry_count <= max_retries:
        try:
            response = rds_data.execute_statement(
                resourceArn=cluster_arn,
                secretArn=secret_arn,
                database=database,
                sql=sql
            )
            print(f"Executed SQL: {sql}")
            return response
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', '')
            error_message = str(e)

            # Check if this is a retryable error
            if "InternalServerErrorException" in error_code or "ServiceUnavailable" in error_code:
                retry_count += 1
                if retry_count <= max_retries:
                    wait_time = backoff_factor ** retry_count
                    print(f"Retryable error: {error_message}. Retrying in {wait_time} seconds...")
                    time.sleep(wait_time)
                else:
                    print(f"Max retries reached for SQL: {sql}")
                    raise
            else:
                # Non-retryable error
                print(f"Non-retryable error: {error_message}")
                raise

def lambda_handler(event, context):
    print('Event: {}'.format(event))
    print('context: {}'.format(context))
    responseData = {}
    status = cfnresponse.SUCCESS

    if event['RequestType'] == 'Delete':
        cfnresponse.send(event, context, status, responseData, 'CustomResourcePhysicalID')
        return

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
        try:
            secret_details = secretsmanager.describe_secret(
                SecretId=secret_name
            )
            secret_arn = secret_details['ARN']
            print(f"Secret ARN: {secret_arn}")
        except ClientError as e:
            print(f"Error retrieving secret details: {str(e)}")
            raise

        try:
            secret_response = secretsmanager.get_secret_value(
                SecretId=secret_name
            )
            secret = json.loads(secret_response['SecretString'])
        except ClientError as e:
            print(f"Error retrieving secret value: {str(e)}")
            raise
        except json.JSONDecodeError as e:
            print(f"Error parsing secret JSON: {str(e)}")
            raise

        # Construct cluster ARN
        cluster_arn = get_cluster_arn(
            secret['dbClusterIdentifier'],
            region,
            account_id
        )
        print(f"Cluster ARN: {cluster_arn}")

        # Initialize RDS Data API client
        rds_data = boto3.client('rds-data')

        # Wait for database to be available
        if not wait_for_database_availability(rds_data, cluster_arn, secret_arn, secret['dbname']):
            raise Exception("Database is not available after maximum wait time")

        # Process SQL statements
        statements = [stmt.strip() for stmt in sql_statements.split(';') if stmt.strip()]

        for sql in statements:
            try:
                execute_sql_with_retry(
                    rds_data,
                    cluster_arn,
                    secret_arn,
                    secret['dbname'],
                    sql
                )
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
