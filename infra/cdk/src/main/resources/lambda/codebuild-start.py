import boto3
import json
import traceback
import cfnresponse

codebuild = boto3.client('codebuild')

def lambda_handler(event, context):
    print(f'Event: {event}')
    responseData = {}
    status = cfnresponse.SUCCESS
    physical_id = event.get('PhysicalResourceId', 'CodeBuildSetup')

    try:
        if event['RequestType'] == 'Delete':
            # Nothing to clean up for CodeBuild
            responseData = {'Message': 'CodeBuild setup deleted'}
            cfnresponse.send(event, context, status, responseData, physical_id)
            return

        if event['RequestType'] == 'Update':
            # For updates, trigger a new build
            pass

        # Start CodeBuild project
        props = event['ResourceProperties']
        project_name = props['ProjectName']

        print(f'Starting CodeBuild project: {project_name}')

        response = codebuild.start_build(
            projectName=project_name
        )

        build_id = response['build']['id']
        build_arn = response['build']['arn']

        print(f'Started build: {build_id}')

        responseData = {
            'BuildId': build_id,
            'BuildArn': build_arn,
            'ProjectName': project_name
        }

        # Use build ID as physical resource ID for tracking
        physical_id = build_id

    except Exception as e:
        status = cfnresponse.FAILED
        tb_err = traceback.format_exc()
        print(tb_err)
        responseData = {'Error': tb_err}

    cfnresponse.send(event, context, status, responseData, physical_id)